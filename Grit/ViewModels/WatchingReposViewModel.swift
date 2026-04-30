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

    // MARK: - Non-member watched project IDs
    //
    // The GitLab `/projects?membership=true` endpoint only returns repos where
    // the authenticated user is a project member. If the user watches a public
    // repo from the Explore tab (where they are NOT a member), that repo is
    // invisible to the membership query.
    //
    // We solve this by persisting the project IDs of any repo the user explicitly
    // watches outside of their own membership list. On each load we fetch those
    // repos by ID and verify the notification level is still "watch" before
    // including them — which also cleans up IDs the user has since unwatched.

    private let externalWatchKey = "grit_external_watched_project_ids"

    /// In-memory mirror of the UserDefaults-persisted set, so computed properties
    /// don't hit disk on every view render.
    private var cachedExternalIDs: Set<Int> = []

    private var externalWatchedIDs: Set<Int> {
        get { cachedExternalIDs }
        set {
            cachedExternalIDs = newValue
            UserDefaults.standard.set(Array(newValue), forKey: externalWatchKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.array(forKey: externalWatchKey) as? [Int] ?? []
        cachedExternalIDs = Set(stored)
    }

    // MARK: - Section splits (used by WatchingReposView)

    /// Repos the user has membership in — returned by the `/projects?membership=true` query.
    var myRepos: [Repository] {
        repos.filter { !cachedExternalIDs.contains($0.id) }
    }

    /// Repos watched from the Explore tab where the user is not a project member.
    var publicRepos: [Repository] {
        repos.filter { cachedExternalIDs.contains($0.id) }
    }

    // MARK: - Load

    func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error     = nil
        defer { isLoading = false }

        do {
            // ── Member repos ──────────────────────────────────────────────────
            var watched = try await api.fetchWatchedRepositories(
                baseURL: auth.baseURL, token: token)
            let memberIDs = Set(watched.map(\.id))

            // ── Non-member repos (watched from Explore) ───────────────────────
            // Clean up any member IDs that addWatchedRepo() temporarily placed
            // in externalWatchedIDs (it can't tell them apart at insert time).
            // This keeps the two sets non-overlapping so section splits are correct.
            let memberOverlap = externalWatchedIDs.intersection(memberIDs)
            if !memberOverlap.isEmpty {
                externalWatchedIDs.subtract(memberOverlap)
            }

            // Only check IDs that weren't already returned by the member query.
            let externalIDs = externalWatchedIDs.subtracting(memberIDs)

            if !externalIDs.isEmpty {
                let baseURL = auth.baseURL
                var idsToRemove = Set<Int>()

                for id in externalIDs {
                    // Verify the watch level is still active on the server.
                    let level = try? await api.fetchProjectNotificationLevel(
                        projectID: id, baseURL: baseURL, token: token)

                    if level?.level == "watch" {
                        if let repo = try? await api.fetchRepository(
                            projectID: id, baseURL: baseURL, token: token) {
                            watched.append(repo)
                        }
                    } else {
                        // User unwatched this repo (e.g. on the web) — clean up.
                        idsToRemove.insert(id)
                    }
                }

                if !idsToRemove.isEmpty {
                    externalWatchedIDs.subtract(idsToRemove)
                }

                // Re-sort so newest activity appears first.
                watched.sort {
                    ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
                }
            }

            repos      = watched
            lastLoaded = Date()
            // Keep the background notification service's repo list in sync.
            WatchedRepoNotificationService.persistWatchedRepos(watched)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadIfNeeded() async {
        guard repos.isEmpty || lastLoaded.map({ Date().timeIntervalSince($0) > 300 }) ?? true
        else { return }
        await load()
    }

    // MARK: - Immediate list sync (called by RepositoryViewModel.toggleWatch)

    /// Inserts `repo` into the list and persists its ID so future loads include
    /// it via the non-member fetch path. Member repos that end up in
    /// `externalWatchedIDs` are cleaned up by `load()` once the membership
    /// query confirms they are covered there.
    func addWatchedRepo(_ repo: Repository) {
        if !repos.contains(where: { $0.id == repo.id }) {
            repos.insert(repo, at: 0)
        }
        // Always track the ID here. We cannot reliably distinguish a new
        // member repo from a non-member repo at this point because myRepos
        // is derived from `repos`, which was just mutated above. load() will
        // subtract any member IDs from externalWatchedIDs after the membership
        // query returns, keeping the two sets non-overlapping.
        externalWatchedIDs.insert(repo.id)
        // Invalidate TTL so next loadIfNeeded does a full refresh.
        lastLoaded = nil
        WatchedRepoNotificationService.persistWatchedRepos(repos)
    }

    /// Removes the repo from the in-memory list and clears its persisted ID.
    func removeWatchedRepo(projectID: Int) {
        repos.removeAll { $0.id == projectID }
        externalWatchedIDs.remove(projectID)
        lastLoaded = nil
        WatchedRepoNotificationService.persistWatchedRepos(repos)
    }
}
