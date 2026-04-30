import Foundation
import SwiftUI

// MARK: - Color helpers (shared across the module)

extension Color {
    /// Creates a Color from a CSS-style hex string (e.g. "#d9534f" or "d9534f").
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }

    /// Converts this color to an uppercase hex string suitable for the GitLab API (e.g. "#D9534F").
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}

// MARK: - Issue / MR Label Detail

/// A GitLab label, decoded from either a plain-string array (default API response)
/// or a rich-object array (when `with_labels_details=true`).
struct IssueLabelDetail: Codable, Identifiable, Hashable {
    let name:      String
    /// Hex color string (e.g. "#d9534f"). Only present when `with_labels_details=true`.
    let color:     String?
    let textColor: String?

    var id: String { name }

    /// Returns the label's API color, falling back to `fallback` when absent.
    func swiftUIColor(fallback: Color = Color.accentColor) -> Color {
        guard let hex = color else { return fallback }
        return Color(hex: hex) ?? fallback
    }

    // Custom decoder: handles both "bug" (plain string) and
    // {"name":"bug","color":"#d9534f",...} (object) elements in the same array.
    init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.name = name; self.color = nil; self.textColor = nil; return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name      = try  c.decode(String.self,          forKey: .name)
        color     = try? c.decodeIfPresent(String.self, forKey: .color)
        textColor = try? c.decodeIfPresent(String.self, forKey: .textColor)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(color,     forKey: .color)
        try c.encodeIfPresent(textColor, forKey: .textColor)
    }

    enum CodingKeys: String, CodingKey {
        case name, color
        case textColor = "text_color"
    }
}

// MARK: - Issue Type

enum GitLabIssueType: String, CaseIterable, Codable, Identifiable {
    case issue       = "issue"
    case task        = "task"
    case incident    = "incident"
    case testCase    = "test_case"
    case requirement = "requirement"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .issue:       return "Issue"
        case .task:        return "Task"
        case .incident:    return "Incident"
        case .testCase:    return "Test Case"
        case .requirement: return "Requirement"
        }
    }

    var icon: String {
        switch self {
        case .issue:       return "exclamationmark.circle"
        case .task:        return "checkmark.square"
        case .incident:    return "flame"
        case .testCase:    return "testtube.2"
        case .requirement: return "list.bullet.clipboard"
        }
    }

    /// Whether this type requires GitLab Premium or Ultimate.
    var requiresPremium: Bool {
        self == .requirement || self == .testCase
    }
}

// MARK: - GitLab Plan

enum GitLabPlan: String {
    case free     = "free"
    case premium  = "premium"
    case ultimate = "ultimate"
    // GitLab.com trial variants
    case premiumTrial  = "premium_trial"
    case ultimateTrial = "ultimate_trial"

    var isPremiumOrHigher: Bool { self != .free }

    init(rawString: String) {
        let lower = rawString.lowercased()
        if lower.contains("ultimate") { self = lower.contains("trial") ? .ultimateTrial : .ultimate }
        else if lower.contains("premium") || lower.contains("silver") || lower.contains("gold") {
            self = lower.contains("trial") ? .premiumTrial : .premium
        } else { self = .free }
    }
}

// MARK: - Task Completion Status

/// Summary of markdown task-list completion (from `task_completion_status` in the API).
struct TaskCompletionStatus: Codable, Hashable {
    let count:          Int
    let completedCount: Int
    enum CodingKeys: String, CodingKey {
        case count
        case completedCount = "completed_count"
    }
}

// MARK: - GitLabIssue

struct GitLabIssue: Codable, Identifiable, Hashable {
    let id:             Int
    let iid:            Int          // per-project number shown as #123
    let title:          String
    let description:    String?
    let state:          String       // "opened" | "closed"
    let createdAt:      Date
    let updatedAt:      Date
    let closedAt:       Date?
    /// Full label details (name + color) when `with_labels_details=true`; name-only otherwise.
    let labelDetails:   [IssueLabelDetail]
    /// Convenience: just the label name strings (backwards-compatible accessor).
    var labels: [String] { labelDetails.map(\.name) }
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
    /// Markdown task-list summary — present when the description contains `- [ ]` items.
    let taskCompletionStatus: TaskCompletionStatus?

    var isOpen: Bool { state == "opened" }

    /// Strongly-typed issue type; defaults to `.issue` when absent or unrecognised.
    var typedIssueType: GitLabIssueType {
        guard let t = issueType else { return .issue }
        return GitLabIssueType(rawValue: t) ?? .issue
    }

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
        case id, iid, title, description, state, author, assignees, subscribed
        case labelDetails   = "labels"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
        case closedAt       = "closed_at"
        case webURL         = "web_url"
        case userNotesCount = "user_notes_count"
        case upvotes, downvotes
        case projectID            = "project_id"
        case references
        case issueType            = "issue_type"
        case taskCompletionStatus = "task_completion_status"
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
        labelDetails   = (try? c.decode([IssueLabelDetail].self, forKey: .labelDetails)) ?? []
        author         = (try? c.decode(IssueAuthor.self,     forKey: .author))
                         ?? IssueAuthor(id: 0, name: "Unknown", username: "unknown", avatarURL: nil)
        assignees      = (try? c.decode([IssueAuthor].self, forKey: .assignees))  ?? []
        webURL         = (try? c.decode(String.self,        forKey: .webURL))     ?? ""
        userNotesCount = (try? c.decode(Int.self,           forKey: .userNotesCount)) ?? 0
        upvotes        = (try? c.decode(Int.self,           forKey: .upvotes))    ?? 0
        downvotes      = (try? c.decode(Int.self,           forKey: .downvotes))  ?? 0
        subscribed     = try c.decodeIfPresent(Bool.self,   forKey: .subscribed)
        projectID      = (try? c.decode(Int.self,           forKey: .projectID))  ?? 0
        references            = try c.decodeIfPresent(IssueReferences.self,        forKey: .references)
        issueType             = try c.decodeIfPresent(String.self,                forKey: .issueType)
        taskCompletionStatus  = try? c.decodeIfPresent(TaskCompletionStatus.self, forKey: .taskCompletionStatus)
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
