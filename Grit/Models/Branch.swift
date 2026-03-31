import Foundation

struct Branch: Codable, Identifiable {
    var id: String { name }
    let name: String
    let merged: Bool
    let protected: Bool
    let isDefault: Bool
    let commit: BranchCommit?
    let webURL: String?
    let canPush: Bool?

    struct BranchCommit: Codable {
        let id: String
        let shortId: String
        let title: String
        let authorName: String
        let authoredDate: Date?
        let committedDate: Date?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case id, title, message
            case shortId = "short_id"
            case authorName = "author_name"
            case authoredDate = "authored_date"
            case committedDate = "committed_date"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, merged, protected, commit
        case isDefault = "default"
        case webURL = "web_url"
        case canPush = "can_push"
    }
}
