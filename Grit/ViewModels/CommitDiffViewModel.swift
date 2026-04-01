import Foundation

@MainActor
final class CommitDiffViewModel: ObservableObject {
    @Published var fileDiffs: [ParsedFileDiff] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(projectID: Int, sha: String) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let raw = try await api.fetchCommitDiff(
                projectID: projectID, sha: sha,
                baseURL: auth.baseURL, token: token
            )
            // Parse off the main thread — regex + string work can be slow for large diffs
            fileDiffs = await Task.detached(priority: .userInitiated) {
                DiffParser.build(raw)
            }.value
        } catch {
            self.error = error.localizedDescription
        }
    }
}
