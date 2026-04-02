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
            let all = try await api.fetchNotifications(baseURL: baseURL, token: token)
            await processNewNotifications(all)
        } catch {
            // Background tasks must not crash — silently swallow errors.
        }
    }

    // MARK: - Shared processing (called by background refresh AND InboxViewModel.load)

    /// Compares `all` against already-seen IDs, fires local banners for anything new,
    /// updates the seenIDs store, and keeps the badge count in sync.
    /// Safe to call from any context — foreground or background.
    func processNewNotifications(_ all: [GitLabNotification]) async {
        let unread = all.filter { $0.unread }

        let seen  = loadSeenIDs()
        let fresh = unread.filter { !seen.contains($0.id) }

        if !fresh.isEmpty {
            await deliverLocalNotifications(fresh)
            saveSeenIDs(seen.union(fresh.map(\.id)))
        }

        // Keep badge in sync.
        try? await UNUserNotificationCenter.current().setBadgeCount(unread.count)
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
            content.title    = "Grit · \(notifications.count) New Notifications"
            content.body     = notifications.compactMap { Self.actionSummary(for: $0) }
                                            .prefix(3)
                                            .joined(separator: "\n")
            content.sound    = .default
            try? await center.add(
                UNNotificationRequest(identifier: UUID().uuidString,
                                      content: content, trigger: nil)
            )
        } else {
            for notification in notifications {
                let content      = UNMutableNotificationContent()
                content.title    = Self.title(for: notification)
                content.subtitle = notification.project?.nameWithNamespace ?? ""
                content.body     = notification.body.isEmpty
                                   ? Self.actionSummary(for: notification) ?? ""
                                   : notification.body
                content.sound    = .default
                content.userInfo = [
                    "grit.notificationId": notification.id,
                    "grit.targetType":     notification.targetType ?? "",
                    "grit.targetURL":      notification.targetURL  ?? "",
                    "grit.projectId":      notification.project?.id ?? 0
                ]
                try? await center.add(
                    UNNotificationRequest(identifier: "grit-notif-\(notification.id)",
                                          content: content, trigger: nil)
                )
            }
        }
    }

    // MARK: - Content helpers

    /// "{Type} · {Action}" — e.g. "Issue · Assigned to You" or "Merge Request · Review Requested"
    private static func title(for notification: GitLabNotification) -> String {
        let type   = typeName(for: notification)
        let action = actionName(for: notification)
        return "\(type) · \(action)"
    }

    /// Short one-line summary used for batch-notification bodies and empty-body fallbacks.
    private static func actionSummary(for notification: GitLabNotification) -> String? {
        guard let project = notification.project else { return actionName(for: notification) }
        return "\(actionName(for: notification)) — \(project.name)"
    }

    private static func typeName(for notification: GitLabNotification) -> String {
        switch notification.targetType?.lowercased() {
        case "mergerequest": return "Merge Request"
        case "issue":        return "Issue"
        case "commit":       return "Commit"
        case "pipeline":     return "Pipeline"
        case "note":         return "Comment"
        default:             return "GitLab"
        }
    }

    private static func actionName(for notification: GitLabNotification) -> String {
        switch notification.actionName?.lowercased() {
        case "assigned":              return "Assigned to You"
        case "mentioned":             return "You Were Mentioned"
        case "directly_addressed":    return "You Were Directly Addressed"
        case "review_requested":      return "Review Requested"
        case "approval_required":     return "Approval Required"
        case "approved":              return "Approved"
        case "unapproved":            return "Approval Removed"
        case "merge_train_removed":   return "Removed from Merge Train"
        case "unmergeable":           return "Cannot Be Merged"
        case "build_failed":          return "Pipeline Failed"
        case "marked":                return "Marked"
        case "all_todos":             return "All Todos"
        default:
            // Fall back to a capitalised version of the raw action name if unrecognised.
            return notification.actionName?
                .replacingOccurrences(of: "_", with: " ")
                .capitalized ?? "New Notification"
        }
    }
}
