import Foundation
import SwiftUI

// MARK: - Group Filter

enum RepoGroupFilter: Hashable, Equatable {
    case all
    case personal
    case group(GitLabGroup)

    var label: String {
        switch self {
        case .all:          return String(localized: "All",      comment: "Repository group filter: show all repositories")
        case .personal:     return String(localized: "Personal", comment: "Repository group filter: show only the user's personal repositories")
        case .group(let g): return g.name   // Group names come from the server, not localised
        }
    }

    var avatarURL: String? {
        if case .group(let g) = self { return g.avatarURL }
        return nil
    }
}

// MARK: - Sort Order

enum RepoSortOrder: String, CaseIterable, Identifiable {
    case recentlyEdited = "recently_edited"
    case alphabetical   = "alphabetical"
    case newestFirst    = "newest_first"

    // `id` uses the stable rawValue key so Picker selection persists across locale changes.
    var id: String { rawValue }

    /// Localised display label.  Use this in UI instead of `rawValue`.
    var label: String {
        switch self {
        case .recentlyEdited: return String(localized: "Recently Edited", comment: "Repository sort order: most recently edited first")
        case .alphabetical:   return String(localized: "Alphabetical",    comment: "Repository sort order: alphabetical by name")
        case .newestFirst:    return String(localized: "Newest First",    comment: "Repository sort order: newest repository first")
        }
    }

    var icon: String {
        switch self {
        case .recentlyEdited: return "clock"
        case .alphabetical:   return "textformat.abc"
        case .newestFirst:    return "calendar.badge.plus"
        }
    }
}

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var repositories:   [Repository]     = []
    @Published var searchResults:  [Repository]     = []
    @Published var groups:         [GitLabGroup]    = []
    @Published var groupFilter:    RepoGroupFilter  = .all
    @Published var sortOrder:      RepoSortOrder    = .recentlyEdited
    @Published var isLoading              = false
    @Published var isLoadingGroups        = false
    @Published var isSearching            = false
    @Published var isBackgroundRefreshing = false
    @Published var error:                 String?
    @Published var currentPage     = 1
    @Published var hasMore         = true

    // Repos after applying the active group filter, then sort order.
    var filteredAndSorted: [Repository] {
        switch groupFilter {
        case .all:
            return sortedRepositories
        case .personal:
            return sortedRepositories.filter { $0.namespace?.kind == "user" }
        case .group(let g):
            return sortedRepositories.filter { $0.namespace?.id == g.id }
        }
    }

    var sortedRepositories: [Repository] {
        switch sortOrder {
        case .recentlyEdited:
            return repositories.sorted {
                ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
            }
        case .alphabetical:
            return repositories.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .newestFirst:
            return repositories.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
        }
    }

    /// Guards against concurrent pagination calls triggered by SwiftUI
    /// re-firing the load-more `onAppear` when the list re-renders.
    private var isPaginating = false
    private var searchTask: Task<Void, Never>?
    private let api   = GitLabAPIService.shared
    private let auth  = AuthenticationService.shared
    private let cache = RepoCacheStore.shared

    // MARK: - Groups

    func loadGroups() async {
        // Serve stale-or-valid cached groups immediately; groups change infrequently
        // so showing cached data while a background refresh runs is a good trade-off.
        if let cached: [GitLabGroup] = await cache.get(.groups, allowStale: true),
           !cached.isEmpty {
            groups = cached
            // If the cache is still valid, skip the network call entirely.
            if let _: [GitLabGroup] = await cache.get(.groups) { return }
        }

        guard let token = auth.accessToken else { return }
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        if let fresh = try? await api.fetchUserGroups(baseURL: auth.baseURL, token: token) {
            groups = fresh
            await cache.set(fresh, for: .groups, ttl: RepoCacheStore.groupsTTL)
        }
    }

    // MARK: - Repository List

    func loadRepositories(refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }

        if refresh {
            // Reset state for a full reload; cancels any in-flight pagination.
            currentPage  = 1
            hasMore      = true
            isPaginating = false
            // Reload groups in parallel on every full refresh.
            Task { await loadGroups() }

            // ── Stale-while-revalidate for the repo list ───────────────────
            // If we have any cached page 1 (even expired), show it instantly so
            // the user sees content immediately rather than a blank loading screen.
            // The network result will replace it moments later, silently.
            if let cached: [Repository] = await cache.get(.repoList(page: 1), allowStale: true),
               !cached.isEmpty {
                withAnimation(.easeOut(duration: 0.25)) { repositories = cached }
                // No loading spinner — cached data is already showing.
            } else {
                isLoading = true
            }
        } else {
            // Pagination path — bail if already loading or nothing left.
            guard !isPaginating, hasMore else { return }
            isPaginating = true
            isLoading = true
        }

        error = nil
        defer {
            withAnimation(.easeOut(duration: 0.25)) { isLoading = false }
            isPaginating = false
        }

        // Snapshot the page we're about to fetch so we can detect if a concurrent
        // refresh reset currentPage underneath us while awaiting.
        let page = currentPage

        do {
            let results = try await api.fetchUserRepositories(
                baseURL: auth.baseURL, token: token, page: page
            )

            if refresh {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    repositories = results
                }
                // Cache page 1 so the next launch / foreground can show it instantly.
                await cache.set(results, for: .repoList(page: 1),
                                ttl: RepoCacheStore.repoListTTL)
                // Kick off background prefetch for the user's predicted repos.
                Task(priority: .background) {
                    await RepoPrefetchService.shared.prefetchAfterListLoad(repos: results)
                }
            } else if currentPage == page {
                // Only append if currentPage hasn't been reset by a concurrent refresh.
                let existingIDs = Set(repositories.map(\.id))
                let fresh = results.filter { !existingIDs.contains($0.id) }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    repositories.append(contentsOf: fresh)
                }
            }

            hasMore     = results.count == 20
            currentPage = page + 1
        } catch {
            // Only surface the error to the user if we have nothing to show.
            // If cached data is already displayed, the network failure is silent.
            if repositories.isEmpty {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Background Refresh

    /// Periodic refresh loop for use with SwiftUI's `.task` modifier.
    /// Cancelled automatically when the hosting view disappears.
    func backgroundRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { break }
            await silentlyRefreshList()
            // Check cached root trees for top-level file/folder changes
            let reposSnapshot = repositories
            Task(priority: .background) {
                await RepoPrefetchService.shared.checkRootTreesForUpdates(repos: reposSnapshot)
            }
        }
    }

    /// Fetches page 1 and merges any new or updated repos into the list with animation.
    /// Does not replace the full list — preserves paginated pages 2+.
    private func silentlyRefreshList() async {
        guard let token = auth.accessToken, !repositories.isEmpty else { return }
        isBackgroundRefreshing = true
        defer { isBackgroundRefreshing = false }

        guard let results = try? await api.fetchUserRepositories(
            baseURL: auth.baseURL, token: token, page: 1
        ) else { return }

        let existingIDs = Set(repositories.map(\.id))
        let newRepos    = results.filter { !existingIDs.contains($0.id) }
        var updated     = repositories
        var didChange   = !newRepos.isEmpty

        // Merge updated metadata (e.g. lastActivityAt, star count) for existing repos.
        for fresh in results {
            guard let idx = updated.firstIndex(where: { $0.id == fresh.id }) else { continue }
            if updated[idx].lastActivityAt != fresh.lastActivityAt ||
               updated[idx].starCount      != fresh.starCount {
                updated[idx] = fresh
                didChange = true
            }
        }

        if !newRepos.isEmpty {
            updated.insert(contentsOf: newRepos, at: 0)
        }

        guard didChange else { return }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            repositories = updated
        }
        await cache.set(Array(results), for: .repoList(page: 1),
                        ttl: RepoCacheStore.repoListTTL)
        hasMore = results.count == 20
    }

    // MARK: - Search

    func search(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                searchResults = try await api.searchRepositories(
                    query: query, baseURL: auth.baseURL, token: token
                )
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

// MARK: - Repository Detail View Model

@MainActor
final class RepositoryDetailViewModel: ObservableObject {
    @Published var repository:    Repository?
    @Published var branches:      [Branch]       = []
    @Published var commits:       [Commit]        = []
    @Published var mergeRequests: [MergeRequest]  = []
    @Published var selectedBranch: String?
    @Published var isLoading      = false
    @Published var error:         String?

    /// The user's current notification level for this project as returned by the GitLab API.
    /// Possible values: "disabled", "mention", "participating", "watch", "global", "custom"
    @Published var notificationLevel: String? = nil
    @Published var isTogglingWatch = false
    /// Latest pipeline for the default branch; nil when the project has no CI.
    /// This is NEVER cached — always fetched fresh to show the real build status.
    @Published var defaultBranchPipeline: Pipeline?
    @Published var isPipelineLoading: Bool = false

    /// True when the current level is "watch".
    var isWatching: Bool { notificationLevel == "watch" }

    private let api   = GitLabAPIService.shared
    private let auth  = AuthenticationService.shared
    private let cache = RepoCacheStore.shared

    // Whether this repo has CI/CD configured, persisted across load()/loadCommits()
    // calls so it can be written into every CachedRepoDetail update.
    // nil = unknown (never fetched), false = confirmed no CI, true = CI exists.
    private var knownHasPipeline: Bool? = nil

    // MARK: - Background Polling

    private var pollingTask: Task<Void, Never>?
    /// How often branches and MRs are silently refreshed while the repo view is open.
    private let pollIntervalSeconds: TimeInterval = 30

    /// Starts a background loop that silently refreshes branches and open MRs
    /// every `pollIntervalSeconds` while the user is on this view.
    /// Cancel with `stopPolling()` when the view disappears.
    func startPolling(projectID: Int) {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollIntervalSeconds))
                guard !Task.isCancelled, let token = auth.accessToken else { break }

                // Branches — silent update, does not touch selectedBranch or commits
                if let fresh = try? await api.fetchBranches(
                    projectID: projectID, baseURL: auth.baseURL, token: token
                ) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                        branches = fresh
                    }
                    await cache.set(fresh, for: .branches(projectID: projectID),
                                    ttl: RepoCacheStore.branchesTTL)
                    await writeDetailBundle(projectID: projectID,
                                            freshBranches: fresh, freshMRs: nil)
                }

                guard !Task.isCancelled else { break }

                // MRs — silent update
                if let fresh = try? await api.fetchMergeRequests(
                    projectID: projectID, baseURL: auth.baseURL, token: token
                ) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                        mergeRequests = fresh
                    }
                    await cache.set(fresh, for: .mrList(projectID: projectID),
                                    ttl: RepoCacheStore.mrListTTL)
                    await writeDetailBundle(projectID: projectID,
                                            freshBranches: nil, freshMRs: fresh)
                }

                guard !Task.isCancelled else { break }

                // Pipeline — always poll so the badge stays live
                if let branch = selectedBranch {
                    let fresh = try? await api.fetchLatestPipeline(
                        projectID: projectID, ref: branch,
                        baseURL: auth.baseURL, token: token
                    )
                    withAnimation(.easeOut(duration: 0.25)) {
                        defaultBranchPipeline = fresh
                    }
                    knownHasPipeline = fresh != nil
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Writes an updated `CachedRepoDetail` bundle, substituting `freshBranches`
    /// and/or `freshMRs` while preserving all other currently-known state.
    private func writeDetailBundle(projectID: Int,
                                   freshBranches: [Branch]?,
                                   freshMRs: [MergeRequest]?) async {
        guard let repo = repository else { return }
        let updated = CachedRepoDetail(
            repository:    repo,
            branches:      freshBranches ?? branches,
            mergeRequests: freshMRs      ?? mergeRequests,
            commits:       commits,
            selectedBranch: selectedBranch,
            hasPipeline:   knownHasPipeline
        )
        await cache.set(updated, for: .repoDetail(projectID: projectID),
                        ttl: RepoCacheStore.repoDetailTTL)
    }

    // MARK: - Load

    func load(projectID: Int) async {
        guard let token = auth.accessToken else { return }

        // ── Serve cache immediately (stale-while-revalidate) ──────────────
        let cachedDetail: CachedRepoDetail? = await cache.get(
            .repoDetail(projectID: projectID), allowStale: true
        )
        if let cached = cachedDetail {
            withAnimation(.easeOut(duration: 0.25)) {
                repository     = cached.repository
                branches       = cached.branches
                mergeRequests  = cached.mergeRequests
                commits        = cached.commits
                selectedBranch = cached.selectedBranch
            }
            knownHasPipeline = cached.hasPipeline
            // isLoading stays false — the user sees content immediately.
        } else {
            isLoading = true
        }

        // ── Track this access for ML predictions ──────────────────────────
        let nameForTracking = cachedDetail?.repository.name ?? ""
        Task.detached(priority: .utility) {
            await RepoAccessTracker.shared.track(repoID: projectID, repoName: nameForTracking)
        }

        error = nil
        defer { withAnimation(.easeOut(duration: 0.25)) { isLoading = false } }

        // ── Network refresh ───────────────────────────────────────────────
        async let repoTask     = api.fetchRepository(
            projectID: projectID, baseURL: auth.baseURL, token: token)
        async let branchesTask = api.fetchBranches(
            projectID: projectID, baseURL: auth.baseURL, token: token)
        async let mrsTask      = api.fetchMergeRequests(
            projectID: projectID, baseURL: auth.baseURL, token: token)

        do {
            let freshRepo = try await repoTask
            withAnimation(.easeOut(duration: 0.28)) { repository = freshRepo }
        } catch {
            self.error = error.localizedDescription
            _ = try? await branchesTask
            _ = try? await mrsTask
            return
        }

        let freshBranches = (try? await branchesTask) ?? []
        let freshMRs      = (try? await mrsTask)      ?? []
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            branches      = freshBranches
            mergeRequests = freshMRs
        }
        selectedBranch = repository?.defaultBranch
            ?? freshBranches.first(where: { $0.isDefault })?.name

        // ── Commits + pipeline + notification level — all concurrent ─────────
        // Pipeline is always fetched unconditionally: the knownHasPipeline==false
        // skip was too aggressive and prevented the badge from ever appearing on
        // repos that later added CI/CD.
        if let branch = selectedBranch {
            isPipelineLoading = true
            async let commitsTask      = api.fetchCommits(
                projectID: projectID, branch: branch,
                baseURL: auth.baseURL, token: token)
            async let pipelineTask     = api.fetchLatestPipeline(
                projectID: projectID, ref: branch,
                baseURL: auth.baseURL, token: token)
            async let notifTask        = api.fetchProjectNotificationLevel(
                projectID: projectID, baseURL: auth.baseURL, token: token)

            let freshCommits   = (try? await commitsTask)  ?? []
            let latestPipeline =  try? await pipelineTask
            let notifLevel     =  try? await notifTask

            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                commits               = freshCommits
                defaultBranchPipeline = latestPipeline
            }
            notificationLevel    = notifLevel?.level
            isPipelineLoading    = false
            knownHasPipeline     = latestPipeline != nil
        } else {
            notificationLevel = (try? await api.fetchProjectNotificationLevel(
                projectID: projectID, baseURL: auth.baseURL, token: token
            ))?.level
        }

        // ── Write the full detail bundle to cache ─────────────────────────
        if let repo = repository {
            let freshDetail = CachedRepoDetail(
                repository:    repo,
                branches:      branches,
                mergeRequests: mergeRequests,
                commits:       commits,
                selectedBranch: selectedBranch,
                hasPipeline:   knownHasPipeline
            )
            await cache.set(freshDetail, for: .repoDetail(projectID: projectID),
                            ttl: RepoCacheStore.repoDetailTTL)

            if repo.name != nameForTracking {
                Task.detached(priority: .utility) {
                    await RepoAccessTracker.shared.track(repoID: projectID, repoName: repo.name)
                }
            }
        }
    }

    // MARK: - Load Commits (branch switch)

    func loadCommits(projectID: Int, branch: String) async {
        guard let token = auth.accessToken else { return }
        do {
            commits = try await api.fetchCommits(
                projectID: projectID, branch: branch,
                baseURL: auth.baseURL, token: token
            )
            selectedBranch = branch
            if let repo = repository {
                let updated = CachedRepoDetail(
                    repository:    repo,
                    branches:      branches,
                    mergeRequests: mergeRequests,
                    commits:       commits,
                    selectedBranch: branch,
                    hasPipeline:   knownHasPipeline
                )
                await cache.set(updated, for: .repoDetail(projectID: projectID),
                                ttl: RepoCacheStore.repoDetailTTL)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Watch Toggle

    /// Toggles the watch state between "watch" and "global" (the user's default).
    ///
    /// Passing the full `Repository` lets us immediately update
    /// `WatchingReposViewModel` so the Watching tab reflects the change without
    /// waiting for the next full reload — including repos watched from Explore
    /// where the user is not a project member.
    func toggleWatch(repo: Repository) async {
        guard let token = auth.accessToken else { return }
        isTogglingWatch = true
        defer { isTogglingWatch = false }

        let targetLevel = isWatching ? "global" : "watch"
        do {
            let result = try await api.setProjectNotificationLevel(
                projectID: repo.id,
                level: targetLevel,
                baseURL: auth.baseURL,
                token: token
            )
            notificationLevel = result.level

            // Immediately sync the shared Watching list so the tab updates
            // without requiring a manual refresh.
            let watchVM = WatchingReposViewModel.shared
            if result.level == "watch" {
                watchVM.addWatchedRepo(repo)
            } else {
                watchVM.removeWatchedRepo(projectID: repo.id)
            }
        } catch {
            self.error = "Could not update watch status: \(error.localizedDescription)"
        }
    }
}
