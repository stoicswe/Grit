import Foundation

@MainActor
final class StarredReposViewModel: ObservableObject {
    static let shared = StarredReposViewModel()

    @Published var repos: [Repository] = []
    @Published var starredIDs: Set<Int> = []
    @Published var isLoading = false
    @Published var error: String?

    private var hasLoaded = false
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Load

    /// Loads once; subsequent calls are no-ops unless refresh=true.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            repos = try await api.fetchStarredProjects(baseURL: auth.baseURL, token: token)
            starredIDs = Set(repos.map(\.id))
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Query

    func isStarred(_ projectID: Int) -> Bool {
        starredIDs.contains(projectID)
    }

    // MARK: - Toggle

    func toggleStar(repo: Repository) async {
        guard let token = auth.accessToken else { return }
        let wasStarred = isStarred(repo.id)

        // Optimistic update
        if wasStarred {
            starredIDs.remove(repo.id)
            repos.removeAll { $0.id == repo.id }
        } else {
            starredIDs.insert(repo.id)
            repos.insert(repo, at: 0)
        }

        do {
            if wasStarred {
                try await api.unstarProject(projectID: repo.id, baseURL: auth.baseURL, token: token)
            } else {
                try await api.starProject(projectID: repo.id, baseURL: auth.baseURL, token: token)
            }
        } catch {
            // Roll back on failure
            if wasStarred {
                starredIDs.insert(repo.id)
                repos.insert(repo, at: 0)
            } else {
                starredIDs.remove(repo.id)
                repos.removeAll { $0.id == repo.id }
            }
            self.error = error.localizedDescription
        }
    }
}
