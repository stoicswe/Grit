import Foundation

struct GitLabGroup: Codable, Identifiable, Hashable {
    let id:          Int
    let name:        String
    let path:        String
    let fullPath:    String
    let description: String?
    let avatarURL:   String?
    let webURL:       String
    let visibility:   String
    let membersCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, path, description, visibility
        case fullPath    = "full_path"
        case avatarURL   = "avatar_url"
        case webURL      = "web_url"
        case membersCount = "members_count"
    }

    static func == (lhs: GitLabGroup, rhs: GitLabGroup) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
