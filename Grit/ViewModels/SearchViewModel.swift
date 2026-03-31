import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var globalResults: [SearchProject] = []
    @Published var repoResults: [SearchBlob] = []
    @Published var isSearching = false
    @Published var error: String?

    private var searchTask: Task<Void, Never>?
    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    /// Search all of GitLab for projects matching the query
    func searchGlobal(query: String) {
        guard !query.isEmpty else { globalResults = []; return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                globalResults = try await api.searchGlobal(
                    query: query, scope: "projects",
                    baseURL: auth.baseURL, token: token
                )
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    /// Search within a specific repository's file blobs
    func searchRepo(query: String, projectID: Int) {
        guard !query.isEmpty else { repoResults = []; return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                repoResults = try await api.searchRepository(
                    projectID: projectID, query: query, scope: "blobs",
                    baseURL: auth.baseURL, token: token
                )
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    func reset() {
        searchTask?.cancel()
        globalResults = []
        repoResults = []
        error = nil
    }
}
