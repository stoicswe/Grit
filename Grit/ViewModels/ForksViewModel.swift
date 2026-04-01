import Foundation

@MainActor
final class ForksViewModel: ObservableObject {
    @Published var forks:    [Repository] = []
    @Published var isLoading = false
    @Published var error:    String?
    @Published var hasMore   = false

    private var currentPage = 1
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(projectID: Int, refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }
        if refresh {
            currentPage = 1
            forks = []
            hasMore = false
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchForks(
                projectID: projectID,
                baseURL: auth.baseURL,
                token: token,
                page: currentPage
            )
            forks += fetched
            hasMore = fetched.count == 20
            if hasMore { currentPage += 1 }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
