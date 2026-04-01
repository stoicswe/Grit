import Foundation
import BackgroundTasks
import UserNotifications

/// Manages background app refresh for GitLab notification polling.
///
/// Flow:
///  1. App launches → GritApp schedules the first refresh via scheduleNextRefresh().
///  2. App enters background → GritApp calls scheduleNextRefresh() again (required by iOS).
///  3. iOS wakes the app at an opportune time and triggers the .backgroundTask handler.
///  4. performRefresh() fetches unread GitLab notifications, compares against the set of
///     already-delivered IDs stored in UserDefaults, fires local notifications for anything
///     new, and schedules the next refresh.
final class BackgroundRefreshService {

    static let shared = BackgroundRefreshService()

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "com.stoicswe.grit.background.refresh"

    // UserDefaults key for the set of notification IDs we've already delivered locally.
    private static let seenIDsKey = "grit.background.seenNotificationIDs"

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    private init() {}

    // MARK: - Scheduling

    /// Submits a BGAppRefreshTaskRequest so iOS will wake the app in the background.
    /// Call this on launch and every time the app enters the background.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        // Earliest possible wake — iOS may delay further based on device usage patterns.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Refresh (invoked by the .backgroundTask scene modifier)

    /// Fetches unread notifications from GitLab, fires local notifications for any
    /// that haven't been delivered yet, and updates the app badge.
    func performRefresh() async {
        // Always schedule the next run first so it's queued even if we exit early.
        scheduleNextRefresh()

        // Auth properties are @MainActor — hop there to read them safely.
        let (token, baseURL) = await MainActor.run {
            (auth.accessToken, auth.baseURL)
        }
        guard let token, !baseURL.isEmpty else { return }

        do {
            let all    = try await api.fetchNotifications(baseURL: baseURL, token: token)
            let unread = all.filter { $0.unread }

            // Deliver local notifications only for IDs we haven't seen before.
            let seen  = loadSeenIDs()
            let fresh = unread.filter { !seen.contains($0.id) }

            if !fresh.isEmpty {
                await deliverLocalNotifications(fresh)
                saveSeenIDs(seen.union(fresh.map(\.id)))
            }

            // Keep badge in sync.
            try? await UNUserNotificationCenter.current().setBadgeCount(unread.count)

        } catch {
            // Background tasks must not crash — silently swallow errors.
        }
    }

    // MARK: - Seen ID persistence

    private func loadSeenIDs() -> Set<Int> {
        let arr = UserDefaults.standard.array(forKey: Self.seenIDsKey) as? [Int] ?? []
        return Set(arr)
    }

    private func saveSeenIDs(_ ids: Set<Int>) {
        // Keep the set bounded to the 1 000 largest IDs (GitLab IDs are monotonically
        // increasing, so this effectively keeps the most recent ones).
        let trimmed = ids.count > 1_000 ? Set(ids.sorted().suffix(1_000)) : ids
        UserDefaults.standard.set(Array(trimmed), forKey: Self.seenIDsKey)
    }

    // MARK: - Local notification delivery

    private func deliverLocalNotifications(_ notifications: [GitLabNotification]) async {
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        if notifications.count > 3 {
            // Batch multiple items into a single summary to avoid flooding the lock screen.
            let content      = UNMutableNotificationContent()
            content.title    = "Grit"
            content.body     = "\(notifications.count) new GitLab notifications"
            content.sound    = .default
            try? await center.add(
                UNNotificationRequest(identifier: UUID().uuidString,
                                      content: content, trigger: nil)
            )
        } else {
            for notification in notifications {
                let content   = UNMutableNotificationContent()
                content.title = Self.title(for: notification)
                if let project = notification.project {
                    content.subtitle = project.nameWithNamespace
                }
                content.body  = notification.body
                content.sound = .default
                try? await center.add(
                    UNNotificationRequest(identifier: "grit-notif-\(notification.id)",
                                          content: content, trigger: nil)
                )
            }
        }
    }

    // MARK: - Helpers

    private static func title(for notification: GitLabNotification) -> String {
        switch notification.targetType?.lowercased() {
        case "mergerequest": return "Merge Request"
        case "issue":        return "Issue"
        case "commit":       return "Commit"
        case "pipeline":     return "Pipeline"
        case "note":         return "Comment"
        default:             return "GitLab"
        }
    }
}
