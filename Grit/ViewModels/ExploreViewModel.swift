import Foundation
import SwiftUI

// MARK: - Sort

enum ExploreSort: String, CaseIterable, Identifiable {
    case stars          = "star_count"
    case recentActivity = "last_activity_at"
    case newest         = "created_at"
    case alphabetical   = "name"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stars:          return "Stars"
        case .recentActivity: return "Recent Activity"
        case .newest:         return "Newest"
        case .alphabetical:   return "Alphabetical"
        }
    }

    var icon: String {
        switch self {
        case .stars:          return "star.fill"
        case .recentActivity: return "clock.fill"
        case .newest:         return "plus.circle.fill"
        case .alphabetical:   return "textformat"
        }
    }

    /// Maps to a GitLab-supported `order_by` for the /groups preview on the main Explore page.
    var groupOrderBy: String {
        switch self {
        case .stars:          return "name"
        case .recentActivity: return "name"
        case .newest:         return "id"
        case .alphabetical:   return "name"
        }
    }

    /// Sort direction sent to the API ("asc" or "desc").
    var sortDirection: String {
        switch self {
        case .alphabetical: return "asc"
        default:            return "desc"
        }
    }
}

// MARK: - Public Group Sort

/// Dedicated sort options for the Public Groups list.
/// Replaces `ExploreSort` in `ExploreAllGroupsView` so groups can have
/// their own set of options independent from the repos sort.
/// Note: the GitLab Groups API only supports order_by = name | path | id |
/// last_activity_at | created_at — member-count sorting is not available.
enum PublicGroupSort: String, CaseIterable, Identifiable {
    case recentActivity = "recent_activity"
    case newest         = "newest"
    case oldest         = "oldest"
    case alphabetical   = "alphabetical"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentActivity: return "Recent Activity"
        case .newest:         return "Newest"
        case .oldest:         return "Oldest"
        case .alphabetical:   return "Alphabetical"
        }
    }

    var icon: String {
        switch self {
        case .recentActivity: return "clock.fill"
        case .newest:         return "plus.circle.fill"
        case .oldest:         return "clock.arrow.circlepath"
        case .alphabetical:   return "textformat"
        }
    }

    /// Maps to a GitLab-supported `order_by` for the /groups API.
    /// "last_activity_at" has a 400-fallback in fetchPublicGroups for older instances.
    var groupOrderBy: String {
        switch self {
        case .recentActivity: return "last_activity_at"
        case .newest:         return "id"
        case .oldest:         return "id"
        case .alphabetical:   return "name"
        }
    }

    /// Sort direction sent to the API ("asc" or "desc").
    var sortDirection: String {
        switch self {
        case .oldest, .alphabetical: return "asc"
        default:                     return "desc"
        }
    }

    /// Maps to a GitLab-supported `order_by` for repos inside a group.
    var repoOrderBy: String {
        switch self {
        case .recentActivity: return "last_activity_at"
        case .newest:         return "created_at"
        case .oldest:         return "created_at"
        case .alphabetical:   return "name"
        }
    }
}

// MARK: - View model

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var projects:               [Repository]  = []
    @Published var groups:                 [GitLabGroup] = []
    @Published var searchResults:          [Repository]  = []   // repos matching by name/description
    @Published var topicResults:           [Repository]  = []   // repos matching by topic/tag
    @Published var userResults:            [GitLabUser]  = []
    @Published var groupResults:           [GitLabGroup] = []   // groups matching by name/path
    @Published var isLoading:              Bool          = false   // full-screen shimmer
    @Published var isBackgroundRefreshing: Bool          = false   // subtle header indicator
    @Published var isLoadingGroups:        Bool          = false
    @Published var isSearching:            Bool          = false
    @Published var error:                  String?
    @Published var sort:                   ExploreSort   = .stars
    @Published var hasMore:                Bool          = false

    /// True when every search result category is empty.
    var searchIsEmpty: Bool {
        searchResults.isEmpty && topicResults.isEmpty &&
        userResults.isEmpty   && groupResults.isEmpty
    }

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
                    orderBy:       sort.rawValue,
                    sortDirection: sort.sortDirection,
                    baseURL:       auth.baseURL,
                    token:         token,
                    page:          page
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

        // Load top-4 public groups in parallel (non-fatal)
        Task { await loadTopGroups() }

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
            do {
                let fetched = try await api.fetchExploreProjects(
                    orderBy:       sort.rawValue,
                    sortDirection: sort.sortDirection,
                    baseURL:       auth.baseURL,
                    token:         token,
                    page:          1
                )
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    projects    = fetched
                    hasMore     = fetched.count == 25
                    currentPage = 2
                }
                writeCache(fetched, for: sort)
            } catch {
                self.error = error.localizedDescription
            }
            withAnimation(.easeOut(duration: 0.25)) { isLoading = false }
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
                    orderBy:       currentSort.rawValue,
                    sortDirection: currentSort.sortDirection,
                    baseURL:       auth.baseURL,
                    token:         token,
                    page:          1
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    // Only apply if the sort hasn't changed since we started AND
                    // the user hasn't already paginated beyond page 1.
                    // If currentPage > 2 the list contains pages 2+ that the
                    // user has already scrolled to — replacing projects with page 1
                    // only would reset their position and cause duplicate fetches.
                    if self.sort == currentSort && self.currentPage <= 2 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            self.projects    = fetched
                            self.hasMore     = fetched.count == 25
                            self.currentPage = 2
                        }
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
        groups       = []
        hasMore      = false
        isPaginating = false
        await loadTrending(refresh: true)
    }

    /// Fetches the top 4 public groups for the current sort and exposes them
    /// in `groups`. Non-fatal — a failure simply leaves `groups` empty.
    func loadTopGroups() async {
        guard let token = auth.accessToken else { return }
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        groups = (try? await api.fetchPublicGroups(
            orderBy: sort.groupOrderBy,
            baseURL: auth.baseURL,
            token:   token,
            page:    1,
            perPage: 4
        )) ?? []
    }

    // MARK: - Search

    /// Fires five concurrent searches. Each section is published immediately when
    /// its own call completes — users see groups, people, and repos appear one by one
    /// rather than waiting for all five to finish.
    ///
    /// Project results (public + member) are accumulated and re-merged each time
    /// either call lands, so member repos are visible before the public search returns.
    func search(query: String) {
        guard !query.isEmpty else {
            searchResults = []; topicResults = []; userResults = []; groupResults = []
            return
        }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true

            let base = auth.baseURL

            // Per-task accumulators so we can re-merge whenever either project
            // query lands (member results appear before the slower public search).
            var landedPublic: [Repository] = []
            var landedMember: [Repository] = []
            var landedTopics: [Repository] = []

            let spring = Animation.spring(response: 0.38, dampingFraction: 0.85)

            await withTaskGroup(of: ExploreChunk.self) { group in
                group.addTask {
                    .publicRepos((try? await self.api.searchProjects(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .memberRepos((try? await self.api.searchMemberProjects(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .topics((try? await self.api.searchRepositoriesByTopic(
                        topic: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .users((try? await self.api.searchUsers(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .groups((try? await self.api.searchGroups(
                        query: query, baseURL: base, token: token)) ?? [])
                }

                for await chunk in group {
                    if Task.isCancelled { break }
                    withAnimation(spring) {
                        switch chunk {
                        case .publicRepos(let r):
                            landedPublic = r
                            applyProjectMerge(public: landedPublic, member: landedMember, topics: landedTopics)

                        case .memberRepos(let r):
                            landedMember = r
                            applyProjectMerge(public: landedPublic, member: landedMember, topics: landedTopics)

                        case .topics(let r):
                            landedTopics = r
                            applyProjectMerge(public: landedPublic, member: landedMember, topics: landedTopics)

                        case .users(let r):  userResults  = r
                        case .groups(let r): groupResults = r
                        }
                    }
                }
            }

            isSearching = false
        }
    }

    // MARK: - Helpers

    private func applyProjectMerge(public publicRepos: [Repository],
                                   member memberRepos: [Repository],
                                   topics topicRepos:  [Repository]) {
        var merged = memberRepos
        let ids    = Set(merged.map(\.id))
        merged.append(contentsOf: publicRepos.filter { !ids.contains($0.id) })
        let allIDs    = Set(merged.map(\.id))
        searchResults = merged
        topicResults  = topicRepos.filter { !allIDs.contains($0.id) }
    }
}

// MARK: - Explore chunk (progressive delivery type)

private enum ExploreChunk: Sendable {
    case publicRepos([Repository])
    case memberRepos([Repository])
    case topics([Repository])
    case users([GitLabUser])
    case groups([GitLabGroup])
}
