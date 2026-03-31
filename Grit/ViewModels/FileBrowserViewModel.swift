import Foundation
import SwiftUI

@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published var files: [RepositoryFile] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func loadDirectory(projectID: Int, path: String, ref: String) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let all = try await api.fetchRepositoryTree(
                projectID: projectID, path: path, ref: ref,
                baseURL: auth.baseURL, token: token
            )
            // Directories first, then files, both alphabetically
            files = all.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            self.error = error.localizedDescription
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
