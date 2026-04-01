import Foundation

struct GitLabUser: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let name: String
    let email: String?
    let avatarURL: String?
    let bio: String?
    let location: String?
    let publicEmail: String?
    let webURL: String
    let createdAt: Date?
    let state: String?
    let followers: Int?
    let following: Int?
    let publicRepos: Int?
    let isFollowing: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, name, email, bio, location, state, followers, following
        case avatarURL = "avatar_url"
        case publicEmail = "public_email"
        case webURL = "web_url"
        case createdAt = "created_at"
        case publicRepos = "public_repos"
        case isFollowing = "is_following"
    }
}
