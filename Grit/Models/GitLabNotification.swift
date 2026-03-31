import Foundation

struct GitLabNotification: Codable, Identifiable {
    let id: Int
    let body: String
    let unread: Bool
    let createdAt: Date
    let updatedAt: Date
    let project: NotificationProject?
    let notificationReason: String?
    let targetType: String?
    let targetURL: String?

    struct NotificationProject: Codable {
        let id: Int
        let name: String
        let nameWithNamespace: String
        let webURL: String

        enum CodingKeys: String, CodingKey {
            case id, name
            case nameWithNamespace = "name_with_namespace"
            case webURL = "web_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, body, unread
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case project
        case notificationReason = "notification_reason"
        case targetType = "target_type"
        case targetURL = "target_url"
    }
}

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
