import Foundation

/// Represents one item from GitLab's Todos API (`GET /todos`).
/// "pending" todos are shown as unread; "done" todos are shown as read.
struct GitLabNotification: Codable, Identifiable, Hashable {
    static func == (lhs: GitLabNotification, rhs: GitLabNotification) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

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
        let id:                Int
        let name:              String
        let nameWithNamespace: String
        let webURL:            String

        enum CodingKeys: String, CodingKey {
            case id, name
            case nameWithNamespace = "name_with_namespace"
            case webURL            = "web_url"
        }

        // Guard inner fields so a null name/nameWithNamespace on personal-namespace
        // projects doesn't kill the whole notifications decode.
        init(from decoder: Decoder) throws {
            let c              = try decoder.container(keyedBy: CodingKeys.self)
            id                 = try c.decode(Int.self, forKey: .id)
            name               = (try? c.decode(String.self, forKey: .name))               ?? ""
            nameWithNamespace  = (try? c.decode(String.self, forKey: .nameWithNamespace))  ?? ""
            webURL             = (try? c.decode(String.self, forKey: .webURL))             ?? ""
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

    // Guard body and state so null/missing fields on certain todo action types
    // (e.g. newly-assigned issues, automated bot todos) don't crash the array decode.
    init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(Int.self,  forKey: .id)
        body        = (try? c.decodeIfPresent(String.self, forKey: .body))  ?? ""
        state       = (try? c.decode(String.self, forKey: .state))          ?? "pending"
        actionName  = try? c.decodeIfPresent(String.self, forKey: .actionName)
        createdAt   = try c.decode(Date.self, forKey: .createdAt)
        updatedAt   = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        project     = try? c.decodeIfPresent(NotificationProject.self, forKey: .project)
        targetType  = try? c.decodeIfPresent(String.self, forKey: .targetType)
        targetURL   = try? c.decodeIfPresent(String.self, forKey: .targetURL)
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
