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

    var isOpen: Bool { state == "opened" }

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
