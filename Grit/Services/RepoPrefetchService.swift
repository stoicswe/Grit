import Foundation

/// Orchestrates background prefetching of repository detail data for the
/// repositories the user is most likely to open next.
///
/// ## How it works
///
/// 1. `RepoAccessTracker` provides a ranked list of predicted repositories.
/// 2. For each candidate, `RepoCacheStore` is checked — if the cache is already
///    warm, no network call is made.
/// 3. A cooldown prevents the same project from being re-fetched more often than
///    every `prefetchCooldown` seconds.
/// 4. All network calls run at `.background` priority so they never compete with
///    user-initiated loads.
///
/// When the user finally taps a prefetched repository, `RepositoryDetailViewModel`
/// finds a warm cache entry and renders the view without a loading spinner.
actor RepoPrefetchService {
    static let shared = RepoPrefetchService()

    // MARK: Configuration
    /// Minimum time between prefetch runs for the same project (avoids hammering the API).
    private let prefetchCooldown: TimeInterval = 5 * 60  // 5 min
    /// Max repos prefetched in one pass (keeps background traffic low).
    private let maxPerPass = 3

    // MARK: State
    private var lastPrefetched: [Int: Date] = [:]

    // MARK: Dependencies
    private let api     = GitLabAPIService.shared
    private let auth    = AuthenticationService.shared
    private let cache   = RepoCacheStore.shared
    private let tracker = RepoAccessTracker.shared

    // MARK: - Triggered Prefetch

    /// Called when the app returns to the foreground.
    ///
    /// Runs two housekeeping tasks concurrently at background priority:
    /// 1. **Prefetch** — warms the cache for the top-predicted repositories.
    /// 2. **Age-based trim** — purges cache entries for projects the user
    ///    hasn't visited recently enough to justify keeping around.
    func prefetchOnForeground() async {
        let (isAuth, token, baseURL) = await MainActor.run {
            (auth.isAuthenticated, auth.accessToken, auth.baseURL)
        }
        guard isAuth, let token else { return }
        let candidates = await tracker.topPredicted(count: maxPerPass)

        await withTaskGroup(of: Void.self) { group in
            // Prefetch each predicted repo (no-op if already warm)
            for candidate in candidates {
                group.addTask(priority: .background) { [weak self] in
                    await self?.prefetchIfNeeded(
                        projectID: candidate.repoID,
                        token:     token,
                        baseURL:   baseURL
                    )
                }
            }
            // Trim aging entries concurrently — uses separate resources from prefetch
            group.addTask(priority: .background) { [weak self] in
                await self?.performAgeBasedTrim()
            }
        }
    }

    // MARK: - Age-Based Cache Trim

    /// Asks `RepoAccessTracker` which projects have exceeded their adaptive
    /// max-age and tells `RepoCacheStore` to evict them.
    ///
    /// The max-age for each project is computed by `RepoAccessTracker` based
    /// on 30-day access frequency:
    /// - Never/rarely accessed → 14-day max age
    /// - Accessed daily        → 42-day max age
    ///
    /// This keeps the disk cache lean without ever prematurely evicting repos
    /// the user visits regularly.
    func performAgeBasedTrim() async {
        let toEvict = await tracker.projectIDsToEvict()
        guard !toEvict.isEmpty else { return }
        await cache.evictProjects(toEvict)
    }

    /// Called by `RepositoryViewModel` after the repository list loads.
    /// Intersects the predicted list with already-known repos and prefetches detail data.
    func prefetchAfterListLoad(repos: [Repository]) async {
        let (isAuth, token, baseURL) = await MainActor.run {
            (auth.isAuthenticated, auth.accessToken, auth.baseURL)
        }
        guard isAuth, let token else { return }
        let predicted = await tracker.topPredicted(count: maxPerPass)

        // Only prefetch repos we know exist in the loaded list
        let knownIDs = Set(repos.map(\.id))
        let targets  = predicted.filter { knownIDs.contains($0.repoID) }
        guard !targets.isEmpty else { return }

        // Fire-and-forget at background priority with a small yield between each
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            for target in targets {
                await self.prefetchIfNeeded(
                    projectID: target.repoID,
                    token:     token,
                    baseURL:   baseURL
                )
                await Task.yield()  // let user-initiated work proceed between prefetches
            }
        }
    }

    // MARK: - Per-Project Prefetch

    private func prefetchIfNeeded(projectID: Int, token: String, baseURL: String) async {
        // Respect the cooldown — don't spam the API for the same repo
        if let last = lastPrefetched[projectID],
           Date().timeIntervalSince(last) < prefetchCooldown { return }

        // If the detail cache is already warm (valid TTL), skip
        let existing: CachedRepoDetail? = await cache.get(.repoDetail(projectID: projectID))
        if existing != nil { return }

        await prefetchDetail(projectID: projectID, token: token, baseURL: baseURL)
    }

    private func prefetchDetail(projectID: Int, token: String, baseURL: String) async {
        // Parallel fetch — mirrors what RepositoryDetailViewModel.load() does,
        // but at background priority with fully non-fatal error handling.
        async let repoFetch     = api.fetchRepository(
            projectID: projectID, baseURL: baseURL, token: token)
        async let branchesFetch = api.fetchBranches(
            projectID: projectID, baseURL: baseURL, token: token)
        async let mrsFetch      = api.fetchMergeRequests(
            projectID: projectID, baseURL: baseURL, token: token)

        // Repository metadata is the anchor — bail if it fails
        guard let repo = try? await repoFetch else { return }

        let branches = (try? await branchesFetch) ?? []
        let mrs      = (try? await mrsFetch)      ?? []
        let selectedBranch = repo.defaultBranch
            ?? branches.first(where: { $0.isDefault })?.name

        var commits: [Commit] = []
        if let branch = selectedBranch {
            commits = (try? await api.fetchCommits(
                projectID: projectID, branch: branch,
                baseURL: baseURL, token: token
            )) ?? []
        }

        // Write the bundle to cache as a single atomic entry.
        // hasPipeline is left nil — prefetch doesn't call fetchLatestPipeline so
        // we have no information yet; the detail view will discover it on first open.
        let detail = CachedRepoDetail(
            repository:    repo,
            branches:      branches,
            mergeRequests: mrs,
            commits:       commits,
            selectedBranch: selectedBranch,
            hasPipeline:   nil
        )
        await cache.set(detail, for: .repoDetail(projectID: projectID),
                        ttl: RepoCacheStore.repoDetailTTL)

        // Also cache the sub-collections individually so branch/MR list views
        // can independently benefit from the warm cache
        if !branches.isEmpty {
            await cache.set(branches, for: .branches(projectID: projectID),
                            ttl: RepoCacheStore.branchesTTL)
        }
        if !mrs.isEmpty {
            await cache.set(mrs, for: .mrList(projectID: projectID),
                            ttl: RepoCacheStore.mrListTTL)
        }

        // Prefetch root tree for the default branch if not already cached
        if let branch = selectedBranch {
            let treeKey = CacheKey.rootTree(projectID: projectID, ref: branch)
            let existingTree: [RepositoryFile]? = await cache.get(treeKey)
            if existingTree == nil,
               let tree = try? await api.fetchRepositoryTree(
                    projectID: projectID, path: "", ref: branch,
                    baseURL: baseURL, token: token
               ) {
                let sorted = tree.sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                await cache.set(sorted, for: treeKey, ttl: RepoCacheStore.rootTreeTTL)
            }
        }

        lastPrefetched[projectID] = Date()
    }

    // MARK: - Root Tree Background Checker

    /// Checks every repo in the user's list for top-level file/folder changes and
    /// silently updates the cache when entries are added, removed, or renamed.
    ///
    /// Called at background priority so it never interferes with user interaction.
    func checkRootTreesForUpdates(repos: [Repository]) async {
        let (isAuth, token, baseURL) = await MainActor.run {
            (auth.isAuthenticated, auth.accessToken, auth.baseURL)
        }
        guard isAuth, let token else { return }

        for repo in repos {
            guard let branch = repo.defaultBranch else { continue }
            let treeKey = CacheKey.rootTree(projectID: repo.id, ref: branch)

            // Only check repos that have a cached root tree
            guard let cached: [RepositoryFile] = await cache.get(treeKey, allowStale: true)
            else { continue }

            guard let fresh = try? await api.fetchRepositoryTree(
                projectID: repo.id, path: "", ref: branch,
                baseURL: baseURL, token: token
            ) else { continue }

            let freshSorted = fresh.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            // Update cache only when the listing has actually changed
            if freshSorted.map(\.id) != cached.map(\.id) {
                await cache.set(freshSorted, for: treeKey, ttl: RepoCacheStore.rootTreeTTL)
            }

            // Yield between repos to avoid monopolising the background executor
            await Task.yield()
        }
    }
}
