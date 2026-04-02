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

    // Custom decoder so that nullable arrays from GitLab (labels, assignees) and
    // occasionally-missing numeric fields never crash the entire list decode.
    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(Int.self,         forKey: .id)
        iid            = try c.decode(Int.self,         forKey: .iid)
        title          = try c.decode(String.self,      forKey: .title)
        description    = try c.decodeIfPresent(String.self, forKey: .description)
        state          = try c.decode(String.self,      forKey: .state)
        createdAt      = try c.decode(Date.self,        forKey: .createdAt)
        updatedAt      = try c.decode(Date.self,        forKey: .updatedAt)
        closedAt       = try c.decodeIfPresent(Date.self,   forKey: .closedAt)
        // GitLab may return null for labels/assignees on some instances; fall back to [].
        labels         = (try? c.decode([String].self,      forKey: .labels))     ?? []
        author         = (try? c.decode(IssueAuthor.self,     forKey: .author))
                         ?? IssueAuthor(id: 0, name: "Unknown", username: "unknown", avatarURL: nil)
        assignees      = (try? c.decode([IssueAuthor].self, forKey: .assignees))  ?? []
        webURL         = (try? c.decode(String.self,        forKey: .webURL))     ?? ""
        userNotesCount = (try? c.decode(Int.self,           forKey: .userNotesCount)) ?? 0
        upvotes        = (try? c.decode(Int.self,           forKey: .upvotes))    ?? 0
        downvotes      = (try? c.decode(Int.self,           forKey: .downvotes))  ?? 0
        subscribed     = try c.decodeIfPresent(Bool.self,   forKey: .subscribed)
        projectID      = (try? c.decode(Int.self,           forKey: .projectID))  ?? 0
        references     = try c.decodeIfPresent(IssueReferences.self, forKey: .references)
        issueType      = try c.decodeIfPresent(String.self, forKey: .issueType)
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

    // Custom decoder so that nullable/missing fields (e.g. body on system events,
    // author on bot-generated notes, updated_at on very old notes) never crash
    // the entire notes array decode.
    init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(Int.self, forKey: .id)
        body      = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        author    = (try? c.decode(GitLabIssue.IssueAuthor.self, forKey: .author))
                    ?? GitLabIssue.IssueAuthor(id: 0, name: "GitLab", username: "gitlab", avatarURL: nil)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        system    = (try? c.decode(Bool.self, forKey: .system)) ?? false
    }
}
