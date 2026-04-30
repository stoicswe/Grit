import Foundation

struct GitLabUser: Codable, Identifiable, Equatable, Hashable {
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

    // Social / contact links
    let websiteUrl: String?
    let twitter: String?
    let linkedin: String?
    let skype: String?
    let discord: String?
    let bluesky: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    enum CodingKeys: String, CodingKey {
        case id, username, name, email, bio, location, state, followers, following
        case avatarURL   = "avatar_url"
        case publicEmail = "public_email"
        case webURL      = "web_url"
        case createdAt   = "created_at"
        case publicRepos = "public_repos"
        case isFollowing = "is_following"
        case websiteUrl  = "website_url"
        case twitter, linkedin, skype, discord, bluesky
    }

    // MARK: - Social links

    struct SocialLink: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let url: URL
    }

    var socialLinks: [SocialLink] {
        var links: [SocialLink] = []
        if let raw = websiteUrl, !raw.isEmpty, let url = URL(string: raw) {
            links.append(.init(icon: "globe", label: "Website", url: url))
        }
        if let handle = twitter, !handle.isEmpty,
           let url = URL(string: "https://twitter.com/\(handle)") {
            links.append(.init(icon: "at", label: handle, url: url))
        }
        if let handle = linkedin, !handle.isEmpty,
           let url = URL(string: "https://www.linkedin.com/in/\(handle)") {
            links.append(.init(icon: "briefcase.fill", label: handle, url: url))
        }
        if let handle = skype, !handle.isEmpty,
           let url = URL(string: "skype:\(handle)?chat") {
            links.append(.init(icon: "phone.circle.fill", label: handle, url: url))
        }
        if let handle = discord, !handle.isEmpty,
           let url = URL(string: "https://discord.com") {
            links.append(.init(icon: "bubble.left.and.bubble.right.fill", label: handle, url: url))
        }
        if let handle = bluesky, !handle.isEmpty,
           let url = URL(string: "https://bsky.app/profile/\(handle)") {
            links.append(.init(icon: "cloud.fill", label: handle, url: url))
        }
        return links
    }
}
