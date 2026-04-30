import SwiftUI

// MARK: - Filter

enum InboxFilter: String, CaseIterable, Identifiable {
    case all           = "All"
    case mergeRequests = "MRs"
    case tasks         = "Tasks"
    case issues        = "My Issues"
    case incidents     = "Incidents"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:           return "tray"
        case .mergeRequests: return "arrow.triangle.merge"
        case .tasks:         return "checkmark.square"
        case .issues:        return "exclamationmark.circle"
        case .incidents:     return "flame"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class InboxViewModel: ObservableObject {

    // MARK: Active filter
    @Published var activeFilter: InboxFilter = .all

    // MARK: Raw data
    @Published var reviewerMRs:   [MergeRequest]       = []
    @Published var assignedMRs:   [MergeRequest]       = []
    /// Issues authored AND assigned to the user (self-created tasks).
    @Published var tasks:         [GitLabIssue]        = []
    /// Issues authored by the user that are NOT self-assigned.
    @Published var createdIssues: [GitLabIssue]        = []
    /// Task-type issues assigned to the user (regardless of author).
    @Published var assignedTasks: [GitLabIssue]        = []
    @Published var notifications: [GitLabNotification] = []

    @Published var isLoading = false
    @Published var error: String?

    /// Drives programmatic navigation inside InboxView's NavigationStack.
    /// Push a GitLabNotification to open its NotificationTargetView directly.
    @Published var navigationPath = NavigationPath()

    private let api                 = GitLabAPIService.shared
    private let auth                = AuthenticationService.shared
    private let notificationService = NotificationService.shared

    /// How often to re-fetch while the inbox is visible in the foreground.
    static let foregroundPollInterval: Duration = .seconds(60)

    /// Running poll loop — cancelled when the inbox leaves the screen or the app backgrounds.
    private var pollingTask: Task<Void, Never>?

    // MARK: Derived counts

    var unreadCount: Int { notifications.filter { $0.unread }.count }

    // MARK: Visibility helpers (respect active filter)

    var showReviewerMRs: Bool {
        (activeFilter == .all || activeFilter == .mergeRequests) && !reviewerMRs.isEmpty
    }
    var showAssignedMRs: Bool {
        (activeFilter == .all || activeFilter == .mergeRequests) && !assignedMRs.isEmpty
    }
    /// Task-type issues the user is involved with:
    ///  • Authored by the user (assigned to self or others)
    ///  • Assigned to the user (even if authored by someone else)
    /// De-duplicated and sorted by most recently updated.
    var taskTypeIssues: [GitLabIssue] {
        let authored = (tasks + createdIssues).filter { $0.issueType == "task" }
        var seen     = Set(authored.map(\.id))
        var result   = authored
        for t in assignedTasks where !seen.contains(t.id) {
            seen.insert(t.id)
            result.append(t)
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }
    var showTasks: Bool {
        (activeFilter == .all || activeFilter == .tasks) && !taskTypeIssues.isEmpty
    }
    var showCreatedIssues: Bool {
        (activeFilter == .all || activeFilter == .issues) &&
        (tasks + createdIssues).filter { $0.issueType != "incident" && $0.issueType != "task" }.count > 0
    }
    var incidentItems: [GitLabIssue] {
        let all = tasks + createdIssues
        return all.filter { $0.issueType == "incident" }
    }
    var showIncidents: Bool {
        (activeFilter == .all || activeFilter == .incidents) && !incidentItems.isEmpty
    }
    var isEmpty: Bool {
        !showReviewerMRs && !showAssignedMRs &&
        !showTasks && !showCreatedIssues && !showIncidents
    }

    // MARK: Foreground polling

    /// Starts a 60-second poll loop. Cancels any previous loop first so it's
    /// safe to call on every `onAppear` or foreground transition.
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            // Sleep first — the initial load is triggered separately via .task { await load() }.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.foregroundPollInterval)
                guard !Task.isCancelled else { break }
                await self?.load()
            }
        }
    }

    /// Stops the poll loop. Call when the inbox leaves the screen or the app backgrounds.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: Load

    func load() async {
        guard let token = auth.accessToken,
              let currentUser = auth.currentUser else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let userID = currentUser.id

        // Kick off all five fetches in parallel.
        // Issues use explicit user IDs rather than scope= params for self-hosted compatibility.
        async let reviewerTask        = api.fetchReviewerMRs(userID: userID,
                                                              baseURL: auth.baseURL, token: token)
        async let assignedMRTask      = api.fetchAssignedMRs(userID: userID,
                                                              baseURL: auth.baseURL, token: token)
        async let createdIssueTask    = api.fetchCreatedIssues(userID: userID,
                                                               baseURL: auth.baseURL, token: token)
        async let assignedTasksTask   = api.fetchAssignedTaskIssues(userID: userID,
                                                                    baseURL: auth.baseURL, token: token)
        async let notifTask           = api.fetchNotifications(baseURL: auth.baseURL, token: token)

        // Await each result independently — a failure in one bucket never wipes the others.
        var rMRs:         [MergeRequest]       = []
        var aMRs:         [MergeRequest]       = []
        var created:      [GitLabIssue]        = []
        var assignedTsks: [GitLabIssue]        = []
        var notifs:       [GitLabNotification] = []

        do { rMRs         = try await reviewerTask }        catch { setFirstError(error) }
        do { aMRs         = try await assignedMRTask }      catch { setFirstError(error) }
        do { created      = try await createdIssueTask }    catch { setFirstError(error) }
        do { assignedTsks = try await assignedTasksTask }   catch { setFirstError(error) }
        do { notifs       = try await notifTask }           catch { setFirstError(error) }

        // MRs — de-duplicate reviewer/assigned overlap
        reviewerMRs = rMRs
        let reviewerIDs = Set(rMRs.map(\.id))
        assignedMRs = aMRs.filter { !reviewerIDs.contains($0.id) }

        // Issues — on-device split using each issue's assignees array.
        // tasks:         I authored it AND I'm one of the assignees.
        // createdIssues: I authored it but am NOT an assignee.
        // assignedTasks: task-type issues assigned to me (may or may not be my authorship).
        tasks         = created.filter { $0.assignees.contains { $0.id == userID } }
        createdIssues = created.filter { !$0.assignees.contains { $0.id == userID } }
        assignedTasks = assignedTsks

        // Notifications (GitLab Todos API)
        notifications = notifs
        notificationService.unreadCount = unreadCount
        notificationService.setBadgeCount(unreadCount)

        // Fire system banners for any notifications we haven't delivered yet.
        // This covers the foreground case — background refresh handles the rest.
        await BackgroundRefreshService.shared.processNewNotifications(notifs)
    }

    // MARK: Helpers

    /// Records the first error encountered during a parallel load; subsequent errors are ignored.
    private func setFirstError(_ err: Error) {
        if error == nil { error = err.localizedDescription }
    }

    // MARK: Close issue

    /// Optimistically removes the issue from whichever inbox list it belongs to,
    /// calls the GitLab API, and restores it at its original position if the
    /// request fails. Works for both Tasks and My Open Issues.
    func closeIssue(_ issue: GitLabIssue) async {
        guard let token = auth.accessToken else { return }

        // Determine which list owns this issue and remove it immediately.
        if let idx = tasks.firstIndex(where: { $0.id == issue.id }) {
            tasks.remove(at: idx)
            if let err = await callClose(issue: issue, token: token) {
                let insertAt = min(idx, tasks.count)
                tasks.insert(issue, at: insertAt)
                error = err.localizedDescription
            }
        } else if let idx = createdIssues.firstIndex(where: { $0.id == issue.id }) {
            createdIssues.remove(at: idx)
            if let err = await callClose(issue: issue, token: token) {
                let insertAt = min(idx, createdIssues.count)
                createdIssues.insert(issue, at: insertAt)
                error = err.localizedDescription
            }
        }
    }

    private func callClose(issue: GitLabIssue, token: String) async -> Error? {
        do {
            _ = try await api.setIssueState(
                projectID: issue.projectID,
                issueIID:  issue.iid,
                open:      false,
                baseURL:   auth.baseURL,
                token:     token
            )
            return nil
        } catch {
            return error
        }
    }

    /// Called when the user navigates back from an issue detail view. Triggers a
    /// lightweight reload so any state change made inside the detail (close/reopen)
    /// is reflected in the inbox list without waiting for the next poll cycle.
    func refreshAfterDetailDismiss() {
        Task { await load() }
    }

    /// Deep-links into the notification with the given ID. If the notification is
    /// already in the loaded list it pushes immediately; otherwise it reloads first
    /// so the fresh data is available before pushing.
    func navigateToNotification(id: Int) {
        if let notification = notifications.first(where: { $0.id == id }) {
            navigationPath.append(notification)
        } else {
            Task {
                await load()
                if let notification = notifications.first(where: { $0.id == id }) {
                    navigationPath.append(notification)
                }
            }
        }
    }

    // MARK: Mark notification read

    func markRead(_ notification: GitLabNotification) async {
        guard let token = auth.accessToken else { return }
        do {
            try await api.markNotificationRead(id: notification.id,
                                                baseURL: auth.baseURL, token: token)
            notifications.removeAll { $0.id == notification.id }
            notificationService.unreadCount = unreadCount
            notificationService.setBadgeCount(unreadCount)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
