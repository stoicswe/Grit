import Foundation

struct Commit: Codable, Identifiable {
    let id: String
    let shortId: String
    let title: String
    let message: String
    let authorName: String
    let authorEmail: String
    let authoredDate: Date
    let committedDate: Date
    let committerName: String
    let committerEmail: String
    let webURL: String
    let stats: CommitStats?
    let parentIds: [String]?

    var shortSHA: String { String(id.prefix(8)) }

    struct CommitStats: Codable {
        let additions: Int
        let deletions: Int
        let total: Int
    }

    enum CodingKeys: String, CodingKey {
        case id, title, message, stats
        case shortId = "short_id"
        case authorName = "author_name"
        case authorEmail = "author_email"
        case authoredDate = "authored_date"
        case committedDate = "committed_date"
        case committerName = "committer_name"
        case committerEmail = "committer_email"
        case webURL = "web_url"
        case parentIds = "parent_ids"
    }
}
