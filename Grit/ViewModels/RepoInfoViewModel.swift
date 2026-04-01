import Foundation

@MainActor
final class RepoInfoViewModel: ObservableObject {
    @Published var contributors:   [GitLabContributor] = []
    @Published var readmeContent:  String?             = nil
    @Published var isLoading:      Bool                = false
    @Published var error:          String?             = nil

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Load

    func load(projectID: Int, ref: String) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error     = nil
        defer { isLoading = false }

        // Fire off contributors (throwing) and README (non-throwing) concurrently.
        async let contribsTask: [GitLabContributor] = api.fetchContributors(
            projectID: projectID, baseURL: auth.baseURL, token: token
        )
        async let readmeTask: String? = api.fetchReadme(
            projectID: projectID, ref: ref, baseURL: auth.baseURL, token: token
        )

        do {
            contributors = try await contribsTask
        } catch {
            self.error = error.localizedDescription
        }
        readmeContent = await readmeTask
    }
}
