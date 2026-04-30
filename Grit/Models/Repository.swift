import Foundation

struct Repository: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let nameWithNamespace: String
    let description: String?
    let defaultBranch: String?
    let visibility: String
    let httpURLToRepo: String
    let webURL: String
    let starCount: Int
    let forksCount: Int
    let openIssuesCount: Int?
    let createdAt: Date?
    let lastActivityAt: Date?
    let namespace: Namespace?
    let statistics: Statistics?
    let archived: Bool?
    /// Project topics / tags (e.g. ["swift", "ios"]).  Nil when the API
    /// response doesn't include the field (older endpoints, caches, etc.).
    let topics: [String]?
    /// ISO 8601 date string (e.g. "2024-05-15") set when the project is queued for deletion.
    /// Stored as a raw String because GitLab returns a date-only value that the shared
    /// ISO 8601 datetime decoder would reject.
    let markedForDeletionAt: String?

    var isScheduledForDeletion: Bool { markedForDeletionAt != nil }

    /// Parsed deletion date for display purposes.
    var markedForDeletionDate: Date? {
        guard let s = markedForDeletionAt else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    var displayName: String { name }

    var languageColor: String {
        // Fallback color key for display
        "default"
    }

    struct Namespace: Codable, Hashable {
        let id: Int
        let name: String
        let path: String
        let kind: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case id, name, path, kind
            case avatarURL = "avatar_url"
        }
    }

    struct Statistics: Codable, Hashable {
        let commitCount: Int?
        let storageSize: Int?
        let repositorySize: Int?

        enum CodingKeys: String, CodingKey {
            case commitCount = "commit_count"
            case storageSize = "storage_size"
            case repositorySize = "repository_size"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, visibility, namespace, statistics, archived
        case nameWithNamespace = "name_with_namespace"
        case defaultBranch = "default_branch"
        case httpURLToRepo = "http_url_to_repo"
        case webURL = "web_url"
        case starCount = "star_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case createdAt      = "created_at"
        case lastActivityAt = "last_activity_at"
        case markedForDeletionAt = "marked_for_deletion_at"
        case topics
    }

    static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
