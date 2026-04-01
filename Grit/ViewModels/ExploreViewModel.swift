import Foundation

// MARK: - Sort

enum ExploreSort: String, CaseIterable, Identifiable {
    case stars          = "star_count"
    case recentActivity = "last_activity_at"
    case newest         = "created_at"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stars:          return "Stars"
        case .recentActivity: return "Recent activity"
        case .newest:         return "Newest"
        }
    }

    var icon: String {
        switch self {
        case .stars:          return "star.fill"
        case .recentActivity: return "clock.fill"
        case .newest:         return "plus.circle.fill"
        }
    }
}

// MARK: - View model

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var projects:              [Repository] = []
    @Published var searchResults:         [Repository] = []
    @Published var isLoading:             Bool         = false   // full-screen shimmer
    @Published var isBackgroundRefreshing: Bool        = false   // subtle header indicator
    @Published var isSearching:           Bool         = false
    @Published var error:                 String?
    @Published var sort:                  ExploreSort  = .stars
    @Published var hasMore:               Bool         = false

    private var currentPage        = 1
    private var isPaginating       = false   // guard against concurrent page loads
    private var searchTask:        Task<Void, Never>?
    private var backgroundRefresh: Task<Void, Never>?

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Cache helpers

    /// One cached page per sort order. Stored in UserDefaults as JSON.
    private struct CacheEntry: Codable {
        let projects: [Repository]
        let savedAt:  Date

        /// Entries older than 5 minutes are considered stale; we still show them
        /// immediately but kick off a background refresh.
        var isStale: Bool {
            Date().timeIntervalSince(savedAt) > 5 * 60
        }
    }

    /// UserDefaults key is scoped to both sort order and instance URL so
    /// switching GitLab instances doesn't serve wrong-server data.
    private func cacheKey(for sort: ExploreSort) -> String {
        let host = URL(string: auth.baseURL)?.host ?? auth.baseURL
        return "explore_cache_\(sort.rawValue)_\(host)"
    }

    private func readCache(for sort: ExploreSort) -> CacheEntry? {
        guard
            let data  = UserDefaults.standard.data(forKey: cacheKey(for: sort)),
            let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
            !entry.projects.isEmpty
        else { return nil }
        return entry
    }

    private func writeCache(_ projects: [Repository], for sort: ExploreSort) {
        let entry = CacheEntry(projects: Array(projects.prefix(25)), savedAt: Date())
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey(for: sort))
        }
    }

    // MARK: - Trending

    /// Call with `refresh: true` on every tab appearance / manual pull-to-refresh.
    ///
    /// - If a cache entry exists it is served **immediately** (no shimmer) and a
    ///   background `Task` silently fetches fresh data.
    /// - If no cache exists the shimmer overlay is shown and the fetch blocks
    ///   the caller until the first page arrives.
    func loadTrending(refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }

        // ── Pagination (load next page) ───────────────────────────────────────
        guard refresh else {
            // Guard against concurrent pagination triggered by onAppear re-fires
            guard !isPaginating else { return }
            isPaginating = true
            defer { isPaginating = false }
            do {
                let page = currentPage
                let fetched = try await api.fetchExploreProjects(
                    orderBy: sort.rawValue,
                    baseURL: auth.baseURL,
                    token: token,
                    page: page
                )
                // Only append if currentPage hasn't been reset underneath us
                // (e.g. sort changed or refresh was triggered during the await)
                if currentPage == page {
                    projects.append(contentsOf: fetched)
                    hasMore = fetched.count == 25
                    if hasMore { currentPage += 1 }
                }
            } catch {
                self.error = error.localizedDescription
            }
            return
        }

        // ── Refresh (tab appear / pull-to-refresh) ────────────────────────────
        currentPage  = 1
        isPaginating = false
        error        = nil

        let cached = readCache(for: sort)

        if let cached, !cached.projects.isEmpty {
            // Serve cache instantly — no visible loading state
            if projects.isEmpty {
                // First visit: populate immediately so the list appears at once
                projects = cached.projects
                hasMore  = false   // pagination resets after background refresh
            }
            // Always kick a background refresh (cancel any in-flight one first)
            scheduleBackgroundRefresh(token: token, currentSort: sort)
        } else {
            // No cache: show full shimmer and await the first page
            isLoading = true
            defer { isLoading = false }
            do {
                let fetched = try await api.fetchExploreProjects(
                    orderBy: sort.rawValue,
                    baseURL: auth.baseURL,
                    token: token,
                    page: 1
                )
                projects    = fetched
                hasMore     = fetched.count == 25
                currentPage = 2
                writeCache(fetched, for: sort)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Fires a cancellable background `Task` that fetches page 1 fresh and
    /// updates `projects` without showing the full-screen shimmer. Runs on a
    /// detached task so it never blocks the caller.
    private func scheduleBackgroundRefresh(token: String, currentSort: ExploreSort) {
        backgroundRefresh?.cancel()
        backgroundRefresh = Task {
            // Small yield so the UI can render the cached list first
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            await MainActor.run { isBackgroundRefreshing = true }

            do {
                let fetched = try await api.fetchExploreProjects(
                    orderBy: currentSort.rawValue,
                    baseURL: auth.baseURL,
                    token: token,
                    page: 1
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    // Only apply if the sort hasn't changed since we started AND
                    // the user hasn't already paginated beyond page 1.
                    // If currentPage > 2 the list contains pages 2+ that the
                    // user has already scrolled to — replacing projects with page 1
                    // only would reset their position and cause duplicate fetches.
                    if self.sort == currentSort && self.currentPage <= 2 {
                        self.projects    = fetched
                        self.hasMore     = fetched.count == 25
                        self.currentPage = 2
                    }
                    self.isBackgroundRefreshing = false
                }
                writeCache(fetched, for: currentSort)
            } catch {
                await MainActor.run { isBackgroundRefreshing = false }
                // Background failure is silent — cached data remains visible
            }
        }
    }

    func changeSort(_ newSort: ExploreSort) async {
        sort         = newSort
        projects     = []          // clear so the correct shimmer/cache is shown
        hasMore      = false
        isPaginating = false
        await loadTrending(refresh: true)
    }

    // MARK: - Search

    func search(query: String) {
        guard !query.isEmpty else { searchResults = []; return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                searchResults = try await api.searchRepositories(
                    query: query,
                    baseURL: auth.baseURL,
                    token: token
                )
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
