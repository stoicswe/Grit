import Foundation
import SwiftUI

struct ActivityEvent: Codable, Identifiable {
    let id:             Int
    let projectID:      Int?
    let actionName:     String
    let targetType:     String?
    let targetTitle:    String?
    let targetID:       Int?
    let targetIID:      Int?
    let createdAt:      Date
    let author:         EventAuthor?
    let pushData:       PushData?
    let note:           EventNote?
    let resourceParent: ResourceParent?

    // MARK: - Display helpers

    /// Short human-readable summary line shown in the row.
    var summaryLine: String {
        let action = actionName
        switch targetType?.lowercased() {
        case "issue":
            return "\(action) issue: \(targetTitle ?? "#\(targetIID ?? targetID ?? 0)")"
        case "mergerequest":
            return "\(action) MR: \(targetTitle ?? "!\(targetIID ?? targetID ?? 0)")"
        case "note", "discussionnote":
            let snippet = note?.body.map { String($0.prefix(80)) }
            return "\(action): \(snippet ?? targetTitle ?? "")"
        case "milestone":
            return "\(action) milestone: \(targetTitle ?? "")"
        case "wiki":
            return "\(action) wiki page: \(targetTitle ?? "")"
        default:
            if actionName.lowercased().contains("push") {
                let branch = pushData?.ref ?? pushData?.branch ?? "unknown"
                let count  = pushData?.commitCount ?? 0
                return "pushed \(count) commit\(count == 1 ? "" : "s") to \(branch)"
            }
            return targetTitle.map { "\(action): \($0)" } ?? action
        }
    }

    /// SF Symbol for this event type.
    var typeIcon: String {
        let lower = actionName.lowercased()
        if lower.contains("push")                           { return "arrow.up.circle.fill" }
        if lower.contains("comment") || lower.contains("note") { return "bubble.left.fill" }
        if lower.contains("open")                           { return "plus.circle.fill" }
        if lower.contains("close")                          { return "xmark.circle.fill" }
        if lower.contains("merge")                          { return "arrow.triangle.merge" }
        if lower.contains("approv")                         { return "checkmark.seal.fill" }
        if lower.contains("create")                         { return "sparkles" }
        if lower.contains("join")                           { return "person.badge.plus" }
        if lower.contains("accept")                         { return "hand.thumbsup.fill" }
        return "circle.fill"
    }

    /// Accent colour for the icon.
    var typeColor: Color {
        let lower = actionName.lowercased()
        if lower.contains("push")                               { return .blue }
        if lower.contains("comment") || lower.contains("note") { return .teal }
        if lower.contains("open")                               { return .green }
        if lower.contains("close")                              { return .red }
        if lower.contains("merge")                              { return .purple }
        if lower.contains("approv")                             { return .green }
        if lower.contains("create")                             { return .orange }
        return .accentColor
    }

    // MARK: - Nested types

    struct EventAuthor: Codable, Hashable {
        let id:        Int
        let name:      String
        let username:  String
        let avatarURL: String?
        let webURL:    String?

        enum CodingKeys: String, CodingKey {
            case id, name, username
            case avatarURL = "avatar_url"
            case webURL    = "web_url"
        }
    }

    struct PushData: Codable {
        let commitCount:  Int?
        let branch:       String?
        let ref:          String?
        let refType:      String?
        let commitTitle:  String?

        enum CodingKeys: String, CodingKey {
            case branch, ref
            case commitCount = "commit_count"
            case refType     = "ref_type"
            case commitTitle = "commit_title"
        }
    }

    struct EventNote: Codable {
        let body:         String?
        let url:          String?
        let noteableType: String?
        /// IID of the parent issue or MR (use this for in-app navigation).
        let noteableIID:  Int?
        /// DB id of the parent issue or MR (fallback only — prefer noteableIID).
        let noteableID:   Int?

        enum CodingKeys: String, CodingKey {
            case body, url
            case noteableType = "noteable_type"
            case noteableIID  = "noteable_iid"
            case noteableID   = "noteable_id"
        }
    }

    struct ResourceParent: Codable {
        let type:     String?
        let name:     String?
        let fullName: String?
        let url:      String?

        enum CodingKeys: String, CodingKey {
            case type, name, url
            case fullName = "full_name"
        }
    }

    // MARK: - Custom init — resilient against null / missing fields

    init(from decoder: Decoder) throws {
        let c            = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(Int.self,    forKey: .id)
        projectID      = try c.decodeIfPresent(Int.self,    forKey: .projectID)
        actionName     = (try? c.decode(String.self, forKey: .actionName)) ?? ""
        targetType     = try c.decodeIfPresent(String.self, forKey: .targetType)
        targetTitle    = try c.decodeIfPresent(String.self, forKey: .targetTitle)
        targetID       = try c.decodeIfPresent(Int.self,    forKey: .targetID)
        targetIID      = try c.decodeIfPresent(Int.self,    forKey: .targetIID)
        createdAt      = try c.decode(Date.self,   forKey: .createdAt)
        author         = try c.decodeIfPresent(EventAuthor.self,     forKey: .author)
        pushData       = try c.decodeIfPresent(PushData.self,        forKey: .pushData)
        note           = try c.decodeIfPresent(EventNote.self,       forKey: .note)
        resourceParent = try c.decodeIfPresent(ResourceParent.self,  forKey: .resourceParent)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectID      = "project_id"
        case actionName     = "action_name"
        case targetType     = "target_type"
        case targetTitle    = "target_title"
        case targetID       = "target_id"
        case targetIID      = "target_iid"
        case createdAt      = "created_at"
        case author
        case pushData       = "push_data"
        case note
        case resourceParent = "resource_parent"
    }
}
