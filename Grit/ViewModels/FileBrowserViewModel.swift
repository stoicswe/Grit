import Foundation
import SwiftUI

@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published var files: [RepositoryFile] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api   = GitLabAPIService.shared
    private let auth  = AuthenticationService.shared
    private let cache = RepoCacheStore.shared

    func loadDirectory(projectID: Int, path: String, ref: String) async {
        guard let token = auth.accessToken else { return }

        let isRoot = path.isEmpty
        let cacheKey = CacheKey.rootTree(projectID: projectID, ref: ref)

        // Root path: serve stale cache immediately, then refresh in background
        if isRoot, let cached: [RepositoryFile] = await cache.get(cacheKey, allowStale: true) {
            withAnimation(.easeOut(duration: 0.25)) { files = cached }
            // Silently refresh without showing the loading spinner
            Task(priority: .background) { [weak self] in
                await self?.silentRootRefresh(
                    projectID: projectID, ref: ref,
                    token: token, baseURL: self?.auth.baseURL ?? ""
                )
            }
            return
        }

        isLoading = true
        error = nil
        defer {
            withAnimation(.easeOut(duration: 0.25)) { isLoading = false }
        }
        do {
            let sorted = try await fetchSorted(projectID: projectID, path: path, ref: ref,
                                               token: token, baseURL: auth.baseURL)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { files = sorted }
            if isRoot {
                await cache.set(sorted, for: cacheKey, ttl: RepoCacheStore.rootTreeTTL)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func silentRootRefresh(projectID: Int, ref: String,
                                   token: String, baseURL: String) async {
        guard let fresh = try? await fetchSorted(
            projectID: projectID, path: "", ref: ref,
            token: token, baseURL: baseURL
        ) else { return }

        let cacheKey = CacheKey.rootTree(projectID: projectID, ref: ref)
        await cache.set(fresh, for: cacheKey, ttl: RepoCacheStore.rootTreeTTL)

        // Only animate in if the listing actually changed
        let currentIDs = await MainActor.run { files.map(\.id) }
        if fresh.map(\.id) != currentIDs {
            await MainActor.run {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { files = fresh }
            }
        }
    }

    private func fetchSorted(projectID: Int, path: String, ref: String,
                              token: String, baseURL: String) async throws -> [RepositoryFile] {
        let all = try await api.fetchRepositoryTree(
            projectID: projectID, path: path, ref: ref,
            baseURL: baseURL, token: token
        )
        return all.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

@MainActor
final class FileContentViewModel: ObservableObject {
    @Published var content: String?
    @Published var fileInfo: FileContent?
    @Published var isLoading = false
    @Published var error: String?
    @Published var aiExplanation: String?
    @Published var isAILoading = false

    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared
    private let ai = AIAssistantService.shared

    func load(projectID: Int, filePath: String, ref: String) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let info = try await api.fetchFileContent(
                projectID: projectID, filePath: filePath, ref: ref,
                baseURL: auth.baseURL, token: token
            )
            fileInfo = info
            content = info.decodedContent
        } catch {
            self.error = error.localizedDescription
        }
    }

    func explainWithAI() async {
        guard let code = content, !code.isEmpty else { return }
        isAILoading = true
        defer { isAILoading = false }
        do {
            aiExplanation = try await ai.analyzeCode(
                code,
                instruction: "Explain what this file does clearly and concisely."
            )
        } catch {
            aiExplanation = "AI unavailable: \(error.localizedDescription)"
        }
    }
}
