import Foundation

// MARK: - Filter

enum InboxFilter: String, CaseIterable, Identifiable {
    case all           = "All"
    case mergeRequests = "MRs"
    case issues        = "Issues"
    case workItems     = "Work Items"
    case notifications = "Notifications"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:           return "tray"
        case .mergeRequests: return "arrow.triangle.merge"
        case .issues:        return "exclamationmark.circle"
        case .workItems:     return "checkmark.square"
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
    @Published var reviewerMRs:    [MergeRequest]       = []
    @Published var assignedMRs:    [MergeRequest]       = []
    @Published var assignedIssues: [GitLabIssue]        = []
    @Published var createdIssues:  [GitLabIssue]        = []
    @Published var workItems:      [GitLabIssue]        = []
    @Published var notifications:  [GitLabNotification] = []

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
    var showAssignedIssues: Bool {
        (activeFilter == .all || activeFilter == .issues) && !assignedIssues.isEmpty
    }
    var showCreatedIssues: Bool {
        (activeFilter == .all || activeFilter == .issues) && !createdIssues.isEmpty
    }
    var showWorkItems: Bool {
        (activeFilter == .all || activeFilter == .workItems) && !workItems.isEmpty
    }
    var showNotifications: Bool {
        (activeFilter == .all || activeFilter == .notifications) && !notifications.isEmpty
    }

    var isEmpty: Bool {
        !showReviewerMRs && !showAssignedMRs && !showAssignedIssues &&
        !showCreatedIssues && !showWorkItems && !showNotifications
    }

    // MARK: Load

    func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let reviewerTask      = api.fetchInboxMRs(scope: "reviewer_of_me",
                                                             baseURL: auth.baseURL, token: token)
            async let assignedMRTask    = api.fetchInboxMRs(scope: "assigned_to_me",
                                                             baseURL: auth.baseURL, token: token)
            async let assignedIssueTask = api.fetchInboxIssues(baseURL: auth.baseURL, token: token)
            async let createdIssueTask  = api.fetchCreatedIssues(baseURL: auth.baseURL, token: token)
            async let notifTask         = api.fetchNotifications(baseURL: auth.baseURL, token: token)

            let (rMRs, aMRs, allAssigned, created, notifs) = try await (
                reviewerTask, assignedMRTask, assignedIssueTask, createdIssueTask, notifTask
            )

            // MRs — de-duplicate reviewer/assigned overlap
            reviewerMRs = rMRs
            let reviewerIDs = Set(rMRs.map(\.id))
            assignedMRs = aMRs.filter { !reviewerIDs.contains($0.id) }

            // Issues — split standard issues from work items
            let standardIssues = allAssigned.filter { !$0.isWorkItem }
            workItems      = allAssigned.filter { $0.isWorkItem }
            assignedIssues = standardIssues

            // Created issues — exclude any already showing as assigned/work item
            let assignedIDs = Set(allAssigned.map(\.id))
            createdIssues = created.filter { !assignedIDs.contains($0.id) }

            // Notifications
            notifications = notifs
            notificationService.unreadCount = unreadCount
            notificationService.setBadgeCount(unreadCount)

        } catch {
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
