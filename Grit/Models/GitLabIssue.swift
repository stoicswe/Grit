import Foundation

struct GitLabIssue: Codable, Identifiable, Hashable {
    let id:             Int
    let iid:            Int          // per-project number shown as #123
    let title:          String
    let description:    String?
    let state:          String       // "opened" | "closed"
    let createdAt:      Date
    let updatedAt:      Date
    let closedAt:       Date?
    let labels:         [String]
    let author:         IssueAuthor
    let assignees:      [IssueAuthor]
    let webURL:         String
    let userNotesCount: Int
    let upvotes:        Int
    let downvotes:      Int
    /// Only populated on single-issue fetches for the authenticated user.
    let subscribed:     Bool?
    /// Project this issue belongs to — always present in API responses.
    let projectID:      Int
    /// Full reference string, e.g. "group/project#42". Used in Inbox for project context.
    let references:     IssueReferences?
    /// Work item type returned by the API: "issue", "task", "incident", "test_case", etc.
    let issueType:      String?

    var isOpen: Bool { state == "opened" }

    /// True for any non-standard issue type (tasks, incidents, etc.).
    var isWorkItem: Bool {
        guard let type = issueType else { return false }
        return type != "issue"
    }

    /// SF Symbol name matching the work item type.
    var workItemTypeIcon: String {
        switch issueType {
        case "task":      return "checkmark.square"
        case "incident":  return "exclamationmark.triangle"
        case "test_case": return "testtube.2"
        default:          return "exclamationmark.circle"
        }
    }

    /// Human-readable type label.
    var workItemTypeLabel: String {
        switch issueType {
        case "task":      return "Task"
        case "incident":  return "Incident"
        case "test_case": return "Test Case"
        case "issue":     return "Issue"
        default:          return issueType?.capitalized ?? "Issue"
        }
    }

    struct IssueReferences: Codable, Hashable {
        let full: String?
    }

    /// Extracts just the project path from references.full (strips the "#iid" suffix).
    var projectPath: String? {
        guard let full = references?.full else { return nil }
        if let range = full.range(of: "#", options: .backwards) {
            return String(full[full.startIndex..<range.lowerBound])
        }
        return full
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    struct IssueAuthor: Codable, Hashable {
        let id:        Int
        let name:      String
        let username:  String
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case id, name, username
            case avatarURL = "avatar_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, iid, title, description, state, labels, author, assignees, subscribed
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
        case closedAt       = "closed_at"
        case webURL         = "web_url"
        case userNotesCount = "user_notes_count"
        case upvotes, downvotes
        case projectID  = "project_id"
        case references
        case issueType  = "issue_type"
    }
}

// MARK: - Issue Note

struct GitLabIssueNote: Codable, Identifiable {
    let id:        Int
    let body:      String
    let author:    GitLabIssue.IssueAuthor
    let createdAt: Date
    let updatedAt: Date
    /// `true` for system-generated activity events (closed, labelled, assigned…)
    let system:    Bool

    enum CodingKeys: String, CodingKey {
        case id, body, author, system
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
