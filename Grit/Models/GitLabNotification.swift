import Foundation

/// Represents one item from GitLab's Todos API (`GET /todos`).
/// "pending" todos are shown as unread; "done" todos are shown as read.
struct GitLabNotification: Codable, Identifiable {
    let id:         Int
    let body:       String
    /// "pending" or "done" — GitLab's Todos API state field.
    let state:      String
    /// e.g. "assigned", "mentioned", "review_requested", "build_failed"
    let actionName: String?
    let createdAt:  Date
    let updatedAt:  Date
    let project:    NotificationProject?
    /// e.g. "MergeRequest", "Issue"
    let targetType: String?
    let targetURL:  String?

    /// Convenience — true while the todo is still pending.
    var unread: Bool { state == "pending" }

    struct NotificationProject: Codable {
        let id:               Int
        let name:             String
        let nameWithNamespace: String
        let webURL:           String

        enum CodingKeys: String, CodingKey {
            case id, name
            case nameWithNamespace = "name_with_namespace"
            case webURL            = "web_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, body, state
        case actionName = "action_name"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
        case project
        case targetType = "target_type"
        case targetURL  = "target_url"
    }
}

// MARK: - Project notification level (from /projects/:id/notification_settings)

/// Represents GitLab's per-project notification level for the authenticated user.
/// Possible levels: "disabled", "mention", "participating", "watch", "global", "custom"
struct ProjectNotificationLevel: Codable {
    let level: String
}

// MARK: -

struct NotificationSettings: Codable {
    var mergeRequestEvents: Bool
    var pushEvents: Bool
    var issueEvents: Bool
    var pipelineEvents: Bool
    var noteEvents: Bool

    init() {
        mergeRequestEvents = true
        pushEvents = false
        issueEvents = true
        pipelineEvents = true
        noteEvents = true
    }
}
