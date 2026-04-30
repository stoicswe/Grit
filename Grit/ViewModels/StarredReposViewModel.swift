import Foundation
import SwiftUI

@MainActor
final class StarredReposViewModel: ObservableObject {
    static let shared = StarredReposViewModel()

    @Published var repos:                  [Repository] = []
    @Published var starredIDs:             Set<Int>     = []
    @Published var isLoading              = false
    @Published var isBackgroundRefreshing = false
    @Published var error:                  String?

    private var hasLoaded   = false
    private var togglingIDs: Set<Int> = []
    private let api   = GitLabAPIService.shared
    private let auth  = AuthenticationService.shared
    private let cache = RepoCacheStore.shared

    // MARK: - Load

    /// Shows cached data instantly for a smooth first appearance, then fetches fresh on first call.
    func loadIfNeeded() async {
        // Serve stale cache immediately so the list appears without a blank flash.
        if repos.isEmpty,
           let cached: [Repository] = await cache.get(.starredList, allowStale: true),
           !cached.isEmpty {
            withAnimation(.easeOut(duration: 0.25)) {
                repos      = cached
                starredIDs = Set(cached.map(\.id))
            }
        }
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        guard let token = auth.accessToken else { return }
        if repos.isEmpty { isLoading = true }
        error = nil

        do {
            let fresh = try await api.fetchStarredProjects(baseURL: auth.baseURL, token: token)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                repos      = fresh
                starredIDs = Set(fresh.map(\.id))
            }
            await cache.set(fresh, for: .starredList, ttl: RepoCacheStore.starredListTTL)
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
        }

        withAnimation(.easeOut(duration: 0.2)) { isLoading = false }
    }

    // MARK: - Background Refresh

    /// Periodic refresh loop for use with SwiftUI's `.task` modifier.
    /// Cancelled automatically when the view disappears.
    func backgroundRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, hasLoaded else { continue }
            await silentRefresh()
        }
    }

    private func silentRefresh() async {
        guard let token = auth.accessToken, !repos.isEmpty else { return }
        isBackgroundRefreshing = true
        defer { isBackgroundRefreshing = false }

        guard let fresh = try? await api.fetchStarredProjects(baseURL: auth.baseURL, token: token)
        else { return }

        let freshIDs = Set(fresh.map(\.id))
        guard freshIDs != starredIDs || fresh.count != repos.count else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            repos      = fresh
            starredIDs = freshIDs
        }
        await cache.set(fresh, for: .starredList, ttl: RepoCacheStore.starredListTTL)
    }

    // MARK: - Section splits (used by StarredReposView)

    /// Repos in the authenticated user's own personal namespace — i.e. repos they
    /// created themselves and have also starred.
    /// Determined by matching `namespace.kind == "user"` + `namespace.path` against
    /// the current user's username; no extra API call required.
    var myRepos: [Repository] {
        let username = auth.currentUser?.username.lowercased() ?? ""
        guard !username.isEmpty else { return [] }
        return repos.filter {
            $0.namespace?.kind == "user" &&
            $0.namespace?.path.lowercased() == username
        }
    }

    /// All other starred repos — other users' projects, group repos, etc.
    var publicRepos: [Repository] {
        let username = auth.currentUser?.username.lowercased() ?? ""
        guard !username.isEmpty else { return repos }
        return repos.filter {
            !($0.namespace?.kind == "user" &&
              $0.namespace?.path.lowercased() == username)
        }
    }

    // MARK: - Query

    func isStarred(_ projectID: Int) -> Bool {
        starredIDs.contains(projectID)
    }

    // MARK: - Toggle

    func toggleStar(repo: Repository) async {
        guard let token = auth.accessToken else { return }
        guard !togglingIDs.contains(repo.id) else { return }
        togglingIDs.insert(repo.id)
        defer { togglingIDs.remove(repo.id) }

        let wasStarred = isStarred(repo.id)

        // Optimistic update with animation
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if wasStarred {
                starredIDs.remove(repo.id)
                repos.removeAll { $0.id == repo.id }
            } else {
                starredIDs.insert(repo.id)
                repos.insert(repo, at: 0)
            }
        }
        await cache.set(repos, for: .starredList, ttl: RepoCacheStore.starredListTTL)

        do {
            if wasStarred {
                try await api.unstarProject(projectID: repo.id, baseURL: auth.baseURL, token: token)
            } else {
                try await api.starProject(projectID: repo.id, baseURL: auth.baseURL, token: token)
            }
        } catch {
            // Roll back on failure
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if wasStarred {
                    starredIDs.insert(repo.id)
                    repos.insert(repo, at: 0)
                } else {
                    starredIDs.remove(repo.id)
                    repos.removeAll { $0.id == repo.id }
                }
            }
            await cache.set(repos, for: .starredList, ttl: RepoCacheStore.starredListTTL)
            self.error = error.localizedDescription
        }
    }
}
