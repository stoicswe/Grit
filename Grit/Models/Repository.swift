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
    let lastActivityAt: Date?
    let namespace: Namespace?
    let statistics: Statistics?
    let archived: Bool?

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
        case lastActivityAt = "last_activity_at"
    }

    static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
