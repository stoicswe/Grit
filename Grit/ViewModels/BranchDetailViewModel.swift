import Foundation

@MainActor
final class BranchDetailViewModel: ObservableObject {
    @Published var commits: [Commit] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = false

    private var currentPage = 1
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(projectID: Int, branch: String, refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }
        if refresh { currentPage = 1 }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchCommits(
                projectID: projectID,
                branch: branch,
                baseURL: auth.baseURL,
                token: token,
                page: currentPage
            )
            if refresh {
                commits = fetched
            } else {
                commits.append(contentsOf: fetched)
            }
            // GitLab returns up to 20 commits per page by default
            hasMore = fetched.count == 20
            if hasMore { currentPage += 1 }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
