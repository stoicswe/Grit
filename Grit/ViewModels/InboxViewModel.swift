import Foundation

// MARK: - Filter

enum InboxFilter: String, CaseIterable, Identifiable {
    case all           = "All"
    case mergeRequests = "MRs"
    case tasks         = "Tasks"
    case issues        = "My Issues"
    case notifications = "Notifications"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:           return "tray"
        case .mergeRequests: return "arrow.triangle.merge"
        case .tasks:         return "checkmark.square"
        case .issues:        return "exclamationmark.circle"
        case .notifications: return "bell"
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
    @Published var notifications: [GitLabNotification] = []

    @Published var isLoading = false
    @Published var error: String?

    private let api                 = GitLabAPIService.shared
    private let auth                = AuthenticationService.shared
    private let notificationService = NotificationService.shared

    // MARK: Derived counts

    var unreadCount: Int { notifications.filter { $0.unread }.count }

    // MARK: Visibility helpers (respect active filter)

    var showReviewerMRs: Bool {
        (activeFilter == .all || activeFilter == .mergeRequests) && !reviewerMRs.isEmpty
    }
    var showAssignedMRs: Bool {
        (activeFilter == .all || activeFilter == .mergeRequests) && !assignedMRs.isEmpty
    }
    var showTasks: Bool {
        (activeFilter == .all || activeFilter == .tasks) && !tasks.isEmpty
    }
    var showCreatedIssues: Bool {
        (activeFilter == .all || activeFilter == .issues) && !createdIssues.isEmpty
    }
    var showNotifications: Bool {
        (activeFilter == .all || activeFilter == .notifications) && !notifications.isEmpty
    }

    var isEmpty: Bool {
        !showReviewerMRs && !showAssignedMRs &&
        !showTasks && !showCreatedIssues && !showNotifications
    }

    // MARK: Load

    func load() async {
        guard let token = auth.accessToken,
              let currentUser = auth.currentUser else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let userID = currentUser.id

        // Kick off all four fetches in parallel.
        // Issues use only author_id (created_by_me); assignee filtering is done on-device
        // from the assignees array so we avoid the unreliable global scope parameters.
        async let reviewerTask     = api.fetchReviewerMRs(userID: userID,
                                                           baseURL: auth.baseURL, token: token)
        async let assignedMRTask   = api.fetchAssignedMRs(userID: userID,
                                                           baseURL: auth.baseURL, token: token)
        async let createdIssueTask = api.fetchCreatedIssues(userID: userID,
                                                             baseURL: auth.baseURL, token: token)
        async let notifTask        = api.fetchNotifications(baseURL: auth.baseURL, token: token)

        // Await each result independently — a failure in one bucket never wipes the others.
        var rMRs:    [MergeRequest]       = []
        var aMRs:    [MergeRequest]       = []
        var created: [GitLabIssue]        = []
        var notifs:  [GitLabNotification] = []

        do { rMRs    = try await reviewerTask }     catch { setFirstError(error) }
        do { aMRs    = try await assignedMRTask }   catch { setFirstError(error) }
        do { created = try await createdIssueTask } catch { setFirstError(error) }
        do { notifs  = try await notifTask }        catch { setFirstError(error) }

        // MRs — de-duplicate reviewer/assigned overlap
        reviewerMRs = rMRs
        let reviewerIDs = Set(rMRs.map(\.id))
        assignedMRs = aMRs.filter { !reviewerIDs.contains($0.id) }

        // Issues — on-device split using each issue's assignees array.
        // Tasks: I authored it AND I'm one of the assignees.
        // My Open Issues: I authored it but am NOT an assignee.
        tasks         = created.filter { $0.assignees.contains { $0.id == userID } }
        createdIssues = created.filter { !$0.assignees.contains { $0.id == userID } }

        // Notifications (GitLab Todos API)
        notifications = notifs
        notificationService.unreadCount = unreadCount
        notificationService.setBadgeCount(unreadCount)
    }

    // MARK: Helpers

    /// Records the first error encountered during a parallel load; subsequent errors are ignored.
    private func setFirstError(_ err: Error) {
        if error == nil { error = err.localizedDescription }
    }

    // MARK: Close / reopen task

    /// Optimistically removes the task from the list, calls the GitLab API, and
    /// restores it at its original position if the request fails.
    func closeTask(_ issue: GitLabIssue) async {
        guard let token = auth.accessToken else { return }

        // Optimistic remove — instant feedback with no spinner needed.
        guard let idx = tasks.firstIndex(where: { $0.id == issue.id }) else { return }
        tasks.remove(at: idx)

        do {
            _ = try await api.setIssueState(
                projectID: issue.projectID,
                issueIID:  issue.iid,
                open:      false,
                baseURL:   auth.baseURL,
                token:     token
            )
        } catch {
            // Restore at the original index so the list doesn't jump around.
            let insertAt = min(idx, tasks.count)
            tasks.insert(issue, at: insertAt)
            self.error = error.localizedDescription
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
