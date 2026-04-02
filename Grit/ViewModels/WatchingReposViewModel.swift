import Foundation

@MainActor
final class WatchingReposViewModel: ObservableObject {
    static let shared = WatchingReposViewModel()

    @Published var repos:     [Repository] = []
    @Published var isLoading: Bool         = false
    @Published var error:     String?

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    private var lastLoaded: Date?

    private init() {}

    func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error     = nil
        defer { isLoading = false }
        do {
            repos      = try await api.fetchWatchedRepositories(baseURL: auth.baseURL, token: token)
            lastLoaded = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadIfNeeded() async {
        guard repos.isEmpty || lastLoaded.map({ Date().timeIntervalSince($0) > 300 }) ?? true
        else { return }
        await load()
    }
}
