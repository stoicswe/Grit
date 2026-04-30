import Foundation
import BackgroundTasks
import UserNotifications

// MARK: - Watched Repo Notification Service

/// Polls GitLab project events for every repo the user is watching and
/// delivers local notifications filtered by the user's notification settings.
///
/// **Background behaviour:**
/// Registers a `BGAppRefreshTask` with a 30-minute earliest interval.
/// iOS wakes the app opportunistically; the actual gap may be longer depending
/// on device usage patterns, battery, and network state.
///
/// **Event filtering:**
/// Each `ActivityEvent` is matched against `NotificationSettings` (from
/// `SettingsStore`) so the user only receives the types they've opted into
/// (pushes, MRs, issues, pipelines, notes/comments).
///
/// **Deduplication:**
/// Delivered event IDs are stored per-project in UserDefaults. The last-checked
/// timestamp is also stored per-project and passed to the GitLab API as the
/// `after` parameter, capping how many events are returned.
///
/// **Persistence across launches:**
/// `persistWatchedRepos(_:)` is called by `WatchingReposViewModel` after every
/// successful load so the background task always has a fresh repo list even when
/// the VM is not in memory.
final class WatchedRepoNotificationService {

    static let shared = WatchedRepoNotificationService()

    /// Must be added to `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.stoicswe.grit.watch.poll"

    // MARK: - UserDefaults keys

    private static let seenEventsKey    = "grit.watch.seenEventIDs"    // [String: [Int]]
    private static let lastCheckedKey   = "grit.watch.lastChecked"     // [String: TimeInterval]
    private static let persistedReposKey = "grit.watch.persistedRepos" // Data (JSON [PersistedRepo])

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    private init() {}

    // MARK: - Scheduling

    /// Submits a `BGAppRefreshTaskRequest` so iOS wakes the app ~30 minutes later.
    /// Call on launch and every time the app enters the background.
    func scheduleNextPoll() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Poll (invoked by .backgroundTask scene modifier in GritApp)

    func performPoll() async {
        // Always re-schedule so the queue stays alive even if we exit early.
        scheduleNextPoll()

        // All three services are @MainActor — read their values in one hop.
        let (token, baseURL, currentUserID, notifSettings) = await MainActor.run {
            (
                auth.accessToken,
                auth.baseURL,
                auth.currentUser?.id,
                SettingsStore.shared.notificationSettings
            )
        }
        guard let token, !baseURL.isEmpty else { return }

        let watchedRepos = Self.loadPersistedRepos()
        guard !watchedRepos.isEmpty else { return }

        let checkedAt = Date()

        // Poll each repo concurrently — a failure on one project doesn't abort the rest.
        await withTaskGroup(of: Void.self) { group in
            for repo in watchedRepos {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.pollRepo(
                        repo:          repo,
                        token:         token,
                        baseURL:       baseURL,
                        currentUserID: currentUserID,
                        settings:      notifSettings,
                        checkedAt:     checkedAt
                    )
                }
            }
        }
    }

    // MARK: - Per-repo polling

    private func pollRepo(
        repo:          PersistedRepo,
        token:         String,
        baseURL:       String,
        currentUserID: Int?,
        settings:      NotificationSettings,
        checkedAt:     Date
    ) async {
        let afterStr = afterDateString(for: repo.id)

        guard let events = try? await api.fetchProjectEvents(
            projectID: repo.id,
            baseURL:   baseURL,
            token:     token,
            after:     afterStr
        ) else { return }

        let seenIDs = loadSeenEventIDs(for: repo.id)

        // Keep events that are:
        //   • not already delivered
        //   • not caused by the watching user themselves
        //   • matching the user's notification-type preferences
        let fresh = events.filter { event in
            !seenIDs.contains(event.id) &&
            (currentUserID == nil || event.author?.id != currentUserID) &&
            matchesSettings(event: event, settings: settings)
        }

        if !fresh.isEmpty {
            await deliverNotifications(for: fresh, repo: repo)
            saveSeenEventIDs(seenIDs.union(Set(fresh.map(\.id))), for: repo.id)
        }

        saveLastChecked(checkedAt, for: repo.id)
    }

    // MARK: - Notification settings filter

    private func matchesSettings(event: ActivityEvent, settings: NotificationSettings) -> Bool {
        let action = event.actionName.lowercased()
        let type   = event.targetType?.lowercased() ?? ""

        if action.contains("push") || action.contains("commit") {
            return settings.pushEvents
        }
        if type == "mergerequest" || action.contains("merge") {
            return settings.mergeRequestEvents
        }
        if type == "issue" {
            return settings.issueEvents
        }
        if type == "pipeline" || action.contains("build") || action.contains("pipeline") {
            return settings.pipelineEvents
        }
        if type == "note" || type == "discussionnote" ||
           action.contains("comment") || action.contains("note") {
            return settings.noteEvents
        }
        return true   // unrecognised event type — allow through
    }

    // MARK: - Local notification delivery

    private func deliverNotifications(for events: [ActivityEvent], repo: PersistedRepo) async {
        let center   = UNUserNotificationCenter.current()
        let authStatus = await center.notificationSettings()
        guard authStatus.authorizationStatus == .authorized else { return }

        if events.count > 3 {
            // Batch into a single summary to avoid flooding the lock screen.
            let content      = UNMutableNotificationContent()
            content.title    = "\(repo.name) - \(events.count) new events"
            content.body     = events.prefix(3)
                                     .map(\.summaryLine)
                                     .joined(separator: "\n")
            content.sound    = .default
            content.userInfo = ["grit.projectId": repo.id, "grit.source": "watch"]
            try? await center.add(
                UNNotificationRequest(
                    identifier: "grit-watch-\(repo.id)-batch-\(Int(Date().timeIntervalSince1970))",
                    content: content, trigger: nil)
            )
        } else {
            for event in events {
                let content      = UNMutableNotificationContent()
                content.title    = repo.name
                content.subtitle = event.author.map { "@\($0.username)" } ?? repo.nameWithNamespace
                content.body     = event.summaryLine
                content.sound    = .default
                content.userInfo = [
                    "grit.projectId": repo.id,
                    "grit.eventId":   event.id,
                    "grit.source":    "watch"
                ]
                try? await center.add(
                    UNNotificationRequest(
                        identifier: "grit-watch-\(repo.id)-\(event.id)",
                        content: content, trigger: nil)
                )
            }
        }
    }

    // MARK: - Watched repo persistence (called by WatchingReposViewModel)

    /// Lightweight representation stored in UserDefaults so the background
    /// task can access the list without `WatchingReposViewModel` being alive.
    struct PersistedRepo: Codable {
        let id:                 Int
        let name:               String
        let nameWithNamespace:  String
    }

    /// Call after every successful `WatchingReposViewModel.load()` and after
    /// `addWatchedRepo` / `removeWatchedRepo` to keep the list in sync.
    static func persistWatchedRepos(_ repos: [Repository]) {
        let slim = repos.map {
            PersistedRepo(id: $0.id, name: $0.name, nameWithNamespace: $0.nameWithNamespace)
        }
        if let data = try? JSONEncoder().encode(slim) {
            UserDefaults.standard.set(data, forKey: persistedReposKey)
        }
    }

    static func loadPersistedRepos() -> [PersistedRepo] {
        guard
            let data  = UserDefaults.standard.data(forKey: persistedReposKey),
            let repos = try? JSONDecoder().decode([PersistedRepo].self, from: data)
        else { return [] }
        return repos
    }

    // MARK: - Seen event ID persistence

    private func loadSeenEventIDs(for projectID: Int) -> Set<Int> {
        let dict = UserDefaults.standard.dictionary(forKey: Self.seenEventsKey) ?? [:]
        let arr  = dict["\(projectID)"] as? [Int] ?? []
        return Set(arr)
    }

    private func saveSeenEventIDs(_ ids: Set<Int>, for projectID: Int) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.seenEventsKey) ?? [:]
        // Cap at 500 per project to prevent unbounded UserDefaults growth.
        let trimmed = ids.count > 500 ? Set(ids.sorted().suffix(500)) : ids
        dict["\(projectID)"] = Array(trimmed)
        UserDefaults.standard.set(dict, forKey: Self.seenEventsKey)
    }

    // MARK: - Last-checked timestamp persistence

    /// Returns an ISO date string (`YYYY-MM-DD`) suitable for the GitLab
    /// `after` API parameter, offset by 5 minutes to cover boundary gaps.
    private func afterDateString(for projectID: Int) -> String? {
        let dict = UserDefaults.standard.dictionary(forKey: Self.lastCheckedKey) ?? [:]
        guard let ts = dict["\(projectID)"] as? TimeInterval else { return nil }
        let adjusted = Date(timeIntervalSince1970: ts).addingTimeInterval(-5 * 60)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        fmt.timeZone   = TimeZone(abbreviation: "UTC")
        return fmt.string(from: adjusted)
    }

    private func saveLastChecked(_ date: Date, for projectID: Int) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.lastCheckedKey) ?? [:]
        dict["\(projectID)"] = date.timeIntervalSince1970
        UserDefaults.standard.set(dict, forKey: Self.lastCheckedKey)
    }
}
