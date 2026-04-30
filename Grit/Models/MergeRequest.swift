import Foundation

struct MergeRequest: Codable, Identifiable, Hashable {
    let id: Int
    let iid: Int
    let title: String
    let description: String?
    let state: MRState
    let author: MRAuthor
    let assignee: MRAuthor?
    let reviewers: [MRAuthor]?
    let sourceBranch: String
    let targetBranch: String
    let createdAt: Date
    let updatedAt: Date
    let mergedAt: Date?
    let webURL: String
    let upvotes: Int
    let downvotes: Int
    let changesCount: String?
    let diffRefs: DiffRefs?
    let labelDetails: [IssueLabelDetail]?
    var labels: [String]? { labelDetails?.map(\.name) }
    let draft: Bool?
    let hasConflicts: Bool?
    let mergeStatus: String?
    /// Project this MR belongs to — always present in API responses.
    let projectID: Int
    /// Full reference string, e.g. "group/project!42". Used in Inbox for project context.
    let references: MRReferences?
    /// The most recent pipeline run against the MR's head commit. Only present on
    /// single-MR fetches (GET /projects/:id/merge_requests/:iid); nil from list endpoints.
    let headPipeline: Pipeline?

    var isDraft: Bool { draft ?? false }

    struct MRReferences: Codable, Hashable {
        let full: String?
    }

    /// Extracts just the project path from references.full (strips the "!iid" suffix).
    var projectPath: String? {
        guard let full = references?.full else { return nil }
        if let range = full.range(of: "!", options: .backwards) {
            return String(full[full.startIndex..<range.lowerBound])
        }
        return full
    }

    enum MRState: String, Codable {
        case opened, closed, merged, locked

        var displayName: String {
            switch self {
            case .opened: return String(localized: "Open",   comment: "Merge request or issue state: currently open and active")
            case .closed: return String(localized: "Closed", comment: "Merge request or issue state: closed without merging")
            case .merged: return String(localized: "Merged", comment: "Merge request state: successfully merged into the target branch")
            case .locked: return String(localized: "Locked", comment: "Merge request state: locked and cannot be modified")
            }
        }

        var color: String {
            switch self {
            case .opened: return "mrOpen"
            case .merged: return "mrMerged"
            case .closed: return "mrClosed"
            case .locked: return "mrLocked"
            }
        }
    }

    struct MRAuthor: Codable, Identifiable, Hashable {
        let id: Int
        let name: String
        let username: String
        let avatarURL: String?
        let webURL: String

        enum CodingKeys: String, CodingKey {
            case id, name, username
            case avatarURL = "avatar_url"
            case webURL = "web_url"
        }
    }

    struct DiffRefs: Codable, Hashable {
        let baseSha: String
        let headSha: String
        let startSha: String

        enum CodingKeys: String, CodingKey {
            case baseSha = "base_sha"
            case headSha = "head_sha"
            case startSha = "start_sha"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, iid, title, description, state, author, assignee, reviewers
        case upvotes, downvotes, draft
        case labelDetails = "labels"
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
        case webURL = "web_url"
        case changesCount = "changes_count"
        case diffRefs = "diff_refs"
        case hasConflicts = "has_conflicts"
        case mergeStatus = "merge_status"
        case projectID = "project_id"
        case references
        case headPipeline = "head_pipeline"
    }
}

struct MRNote: Codable, Identifiable {
    let id: Int
    let body: String
    let author: MergeRequest.MRAuthor
    let createdAt: Date
    let updatedAt: Date
    let resolvable: Bool?
    let resolved: Bool?
    let system: Bool

    enum CodingKeys: String, CodingKey {
        case id, body, author, resolvable, resolved, system
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Approval state (from /merge_requests/:iid/approvals)

struct MRApprovalState: Codable {
    let userHasApproved: Bool
    let userCanApprove:  Bool

    enum CodingKeys: String, CodingKey {
        case userHasApproved = "user_has_approved"
        case userCanApprove  = "user_can_approve"
    }
}

// MARK: - Project member (from /members/all/:user_id)

struct ProjectMember: Codable {
    let id:          Int
    let accessLevel: Int

    enum CodingKeys: String, CodingKey {
        case id
        case accessLevel = "access_level"
    }
}
