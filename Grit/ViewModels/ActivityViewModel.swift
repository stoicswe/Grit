import Foundation
import SwiftUI

// MARK: - Primary filter

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all             = "All"
    case yourActivity    = "Your Activity"
    case yourProjects    = "Your Projects"
    case starredProjects = "Starred"
    case followedUsers   = "Following"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:             return "waveform"
        case .yourActivity:    return "person.fill"
        case .yourProjects:    return "folder.fill"
        case .starredProjects: return "star.fill"
        case .followedUsers:   return "person.2.fill"
        }
    }
}

// MARK: - Activity-type sub-filter (Starred only)

enum ActivityTypeFilter: String, CaseIterable, Identifiable {
    case all           = "All"
    case pushes        = "Pushes"
    case issues        = "Issues"
    case mergeRequests = "Merge Requests"
    case comments      = "Comments"
    case other         = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:           return "line.3.horizontal.decrease"
        case .pushes:        return "arrow.up.circle"
        case .issues:        return "exclamationmark.circle"
        case .mergeRequests: return "arrow.triangle.merge"
        case .comments:      return "bubble.left"
        case .other:         return "ellipsis.circle"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ActivityViewModel: ObservableObject {

    // Primary filter; resets type sub-filter when leaving Starred.
    @Published var activeFilter: ActivityFilter = .all {
        didSet { if activeFilter != .starredProjects { activeTypeFilter = .all } }
    }

    // Starred sub-filter — only applied when activeFilter == .starredProjects.
    @Published var activeTypeFilter: ActivityTypeFilter = .all

    @Published var feedEvents:    [ActivityEvent] = []
    @Published var yourEvents:    [ActivityEvent] = []
    @Published var starredEvents: [ActivityEvent] = []
    @Published var isLoading    = false
    @Published var error:         String?

    private var followingUserIDs: Set<Int>      = []
    private var memberProjectIDs: Set<Int>      = []
    private var projectNames:     [Int: String] = [:]
    private var projectURLs:      [Int: String] = [:]

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    /// Cancellable handle for the background starred-events fetch.
    private var starredFetchTask: Task<Void, Never>?

    // MARK: - Lookups

    func projectName(for id: Int?) -> String? {
        guard let id else { return nil }
        return projectNames[id]
    }

    func projectURL(for id: Int?) -> String? {
        guard let id else { return nil }
        return projectURLs[id]
    }

    // MARK: - Filtered events

    var filteredEvents: [ActivityEvent] {
        let base: [ActivityEvent]
        switch activeFilter {
        case .all:
            let merged = feedEvents + starredEvents.filter { starred in
                !feedEvents.contains { $0.id == starred.id }
            }
            base = merged.sorted { $0.createdAt > $1.createdAt }
        case .yourActivity:
            base = yourEvents
        case .yourProjects:
            base = feedEvents.filter { event in
                guard let pid = event.projectID else { return false }
                return memberProjectIDs.contains(pid)
            }
        case .starredProjects:
            base = starredEvents
        case .followedUsers:
            base = feedEvents.filter { event in
                guard let authorID = event.author?.id else { return false }
                return followingUserIDs.contains(authorID)
            }
        }

        // Apply type sub-filter only for Starred.
        guard activeFilter == .starredProjects, activeTypeFilter != .all else { return base }
        return base.filter { $0.matchesTypeFilter(activeTypeFilter) }
    }

    var isEmpty: Bool { filteredEvents.isEmpty }

    // MARK: - Load

    func load() async {
        // Cancel any in-flight starred fetch so a fresh pull-to-refresh starts clean.
        starredFetchTask?.cancel()

        // Show cached data immediately so the UI is never blank on refresh.
        restoreFromCache()

        guard let token = auth.accessToken,
              let currentUser = auth.currentUser else { return }

        // Show the skeleton only when there is truly nothing to display yet.
        isLoading = feedEvents.isEmpty && yourEvents.isEmpty
        error = nil
        defer { isLoading = false }

        let userID  = currentUser.id
        let baseURL = auth.baseURL

        // ── Fast parallel fetches ──────────────────────────────────────────────
        async let feedTask      = api.fetchActivityFeed(baseURL: baseURL, token: token)
        async let userEvtTask   = api.fetchUserActivityEvents(userID: userID,
                                                               baseURL: baseURL, token: token)
        async let followingTask = api.fetchFollowing(userID: userID,
                                                      baseURL: baseURL, token: token)
        async let projectsTask  = api.fetchMemberProjects(baseURL: baseURL, token: token)

        var feed:      [ActivityEvent] = []
        var userEvts:  [ActivityEvent] = []
        var following: [GitLabUser]    = []
        var projects:  [Repository]    = []

        do { feed      = try await feedTask }      catch { setFirstError(error) }
        do { userEvts  = try await userEvtTask }   catch { setFirstError(error) }
        do { following = try await followingTask } catch { }
        do { projects  = try await projectsTask }  catch { }

        // Merge fresh results with what was cached — no duplicates, no lost history.
        feedEvents       = merging(fresh: feed,      withExisting: feedEvents)
        yourEvents       = merging(fresh: userEvts,  withExisting: yourEvents)
        followingUserIDs = Set(following.map(\.id))
        memberProjectIDs = Set(projects.map(\.id))

        // Build lookup maps from known repos + event resource_parent.
        for repo in projects {
            projectNames[repo.id] = repo.nameWithNamespace
            projectURLs[repo.id]  = repo.webURL
        }
        for event in (feed + userEvts) {
            if let pid = event.projectID {
                if projectNames[pid] == nil {
                    projectNames[pid] = event.resourceParent?.fullName ?? event.resourceParent?.name
                }
                if projectURLs[pid] == nil {
                    projectURLs[pid] = event.resourceParent?.url
                }
            }
        }

        // Save fast-data snapshot so the next open is instant.
        saveToCache()

        // ── Background: starred events (non-blocking) ─────────────────────────
        // Fired as a detached task so load() returns here, letting .refreshable
        // complete its spinner immediately rather than waiting for 15+ fetches.
        starredFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshStarredInBackground(baseURL: baseURL, token: token)
        }
    }

    // MARK: - Background starred fetch

    private func refreshStarredInBackground(baseURL: String, token: String) async {
        await StarredReposViewModel.shared.loadIfNeeded()
        let starredRepos = StarredReposViewModel.shared.repos
        let topStarred   = Array(starredRepos.prefix(15))
        guard !topStarred.isEmpty else { return }

        var collected: [ActivityEvent] = []
        await withTaskGroup(of: [ActivityEvent].self) { group in
            for repo in topStarred {
                guard !Task.isCancelled else { return }
                let repoID = repo.id
                group.addTask {
                    (try? await GitLabAPIService.shared.fetchProjectEvents(
                        projectID: repoID, baseURL: baseURL, token: token
                    )) ?? []
                }
            }
            for await batch in group {
                guard !Task.isCancelled else { return }
                collected.append(contentsOf: batch)
            }
        }

        guard !Task.isCancelled else { return }

        // Deduplicate and sort newest-first.
        var seen = Set<Int>()
        let sorted = collected
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }

        // Supplement lookup maps from starred repo data.
        var names = projectNames
        var urls  = projectURLs
        for repo in StarredReposViewModel.shared.repos {
            names[repo.id] = repo.nameWithNamespace
            urls[repo.id]  = repo.webURL
        }
        for event in sorted {
            if let pid = event.projectID {
                if names[pid] == nil { names[pid] = event.resourceParent?.fullName ?? event.resourceParent?.name }
                if urls[pid]  == nil { urls[pid]  = event.resourceParent?.url }
            }
        }

        // Merge with any cached starred events so history beyond the fetched page is kept.
        starredEvents = merging(fresh: sorted, withExisting: starredEvents)
        projectNames  = names
        projectURLs   = urls
        saveToCache()
    }

    // MARK: - Helpers

    private func setFirstError(_ err: Error) {
        if error == nil { error = err.localizedDescription }
    }

    /// Merges a fresh API result with whatever was previously in the array (cache or prior
    /// fetch), ensuring no event appears twice.  Fresh events win on conflict (same ID);
    /// any cached event whose ID is absent from the fresh page is appended so older history
    /// is not discarded just because it fell off the latest API page.  Result is sorted
    /// newest-first by `createdAt`.
    private func merging(fresh: [ActivityEvent],
                         withExisting existing: [ActivityEvent]) -> [ActivityEvent] {
        let freshIDs = Set(fresh.map(\.id))
        let combined = fresh + existing.filter { !freshIDs.contains($0.id) }
        return combined.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Cache

    private struct ActivityCache: Codable {
        var feedEvents:    [ActivityEvent]
        var yourEvents:    [ActivityEvent]
        var starredEvents: [ActivityEvent]
        /// Stored as [String:String] because JSON requires string keys.
        var projectNames:  [String: String]
        var projectURLs:   [String: String]
        var savedAt:       Date
    }

    private var cacheFileURL: URL? {
        guard let uid = auth.currentUser?.id else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("activity_cache_\(uid).json")
    }

    private func saveToCache() {
        guard let url = cacheFileURL else { return }
        let cache = ActivityCache(
            feedEvents:    feedEvents,
            yourEvents:    yourEvents,
            starredEvents: starredEvents,
            projectNames:  Dictionary(uniqueKeysWithValues: projectNames.map { (String($0.key), $0.value) }),
            projectURLs:   Dictionary(uniqueKeysWithValues: projectURLs.map  { (String($0.key), $0.value) }),
            savedAt:       Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func restoreFromCache() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cache = try? decoder.decode(ActivityCache.self, from: data) else { return }

        feedEvents    = cache.feedEvents
        yourEvents    = cache.yourEvents
        starredEvents = cache.starredEvents
        projectNames  = Dictionary(uniqueKeysWithValues: cache.projectNames.compactMap { k, v in Int(k).map { ($0, v) } })
        projectURLs   = Dictionary(uniqueKeysWithValues: cache.projectURLs.compactMap  { k, v in Int(k).map { ($0, v) } })
    }
}

// MARK: - ActivityEvent type-filter matching

private extension ActivityEvent {
    func matchesTypeFilter(_ filter: ActivityTypeFilter) -> Bool {
        let actionLower = actionName.lowercased()
        let typeLower   = targetType?.lowercased() ?? ""
        switch filter {
        case .all:
            return true
        case .pushes:
            return actionLower.contains("push")
        case .issues:
            return typeLower == "issue"
        case .mergeRequests:
            return typeLower == "mergerequest"
        case .comments:
            return typeLower == "note" || typeLower == "diffnote" || typeLower == "discussionnote"
        case .other:
            return !actionLower.contains("push")
                && typeLower != "issue"
                && typeLower != "mergerequest"
                && typeLower != "note"
                && typeLower != "diffnote"
                && typeLower != "discussionnote"
        }
    }
}
