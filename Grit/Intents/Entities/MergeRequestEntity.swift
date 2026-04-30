import AppIntents
import CoreSpotlight

// MARK: - Merge Request Entity

/// Exposes GitLab merge requests to Siri, Shortcuts, and Spotlight.
struct MergeRequestEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Merge Request"

    static var defaultQuery = MergeRequestQuery()

    // MARK: Stored properties

    let id: Int
    let iid: Int
    let title: String
    let state: String
    let projectID: Int
    let projectPath: String?
    let sourceBranch: String
    let targetBranch: String
    let isDraft: Bool
    let webURL: String
    let authorName: String

    // MARK: Display

    var displayRepresentation: DisplayRepresentation {
        let prefix = isDraft ? "Draft: " : ""
        let subtitle: String
        if let path = projectPath {
            subtitle = "\(path)!\(iid) \u{00B7} \(sourceBranch) \u{2192} \(targetBranch)"
        } else {
            subtitle = "!\(iid) \u{00B7} \(sourceBranch) \u{2192} \(targetBranch)"
        }
        return DisplayRepresentation(
            title: "\(prefix)\(title)",
            subtitle: "\(subtitle)"
        )
    }

    // MARK: Spotlight

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.displayName = title
        attributes.contentDescription = projectPath.map { "\($0)!\(iid)" } ?? "!\(iid)"
        return attributes
    }

    // MARK: Conversion

    init(id: Int, iid: Int, title: String, state: String,
         projectID: Int, projectPath: String?, sourceBranch: String,
         targetBranch: String, isDraft: Bool, webURL: String,
         authorName: String) {
        self.id = id
        self.iid = iid
        self.title = title
        self.state = state
        self.projectID = projectID
        self.projectPath = projectPath
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.isDraft = isDraft
        self.webURL = webURL
        self.authorName = authorName
    }

    init(from mr: MergeRequest) {
        self.id = mr.id
        self.iid = mr.iid
        self.title = mr.title
        self.state = mr.state.rawValue
        self.projectID = mr.projectID
        self.projectPath = mr.projectPath
        self.sourceBranch = mr.sourceBranch
        self.targetBranch = mr.targetBranch
        self.isDraft = mr.isDraft
        self.webURL = mr.webURL
        self.authorName = mr.author.name
    }
}

// MARK: - Merge Request Query

struct MergeRequestQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [MergeRequestEntity] {
        // GitLab does not support fetching MRs by global ID without project
        // context.  Return matches from the user's assigned/review MRs instead.
        let all = try await fetchUserMRs()
        return all.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [MergeRequestEntity] {
        let all = try await fetchUserMRs()
        let query = string.lowercased()
        return all.filter { $0.title.lowercased().contains(query) }
    }

    func suggestedEntities() async throws -> [MergeRequestEntity] {
        try await fetchUserMRs()
    }

    // MARK: Helpers

    private func fetchUserMRs() async throws -> [MergeRequestEntity] {
        guard let token = await AuthenticationService.shared.accessToken else { return [] }
        let baseURL = await AuthenticationService.shared.baseURL
        guard let user = await AuthenticationService.shared.currentUser else { return [] }

        // Combine assigned + reviewer MRs, deduplicating by ID.
        async let assigned = GitLabAPIService.shared.fetchAssignedMRs(
            userID: user.id, baseURL: baseURL, token: token
        )
        async let reviewing = GitLabAPIService.shared.fetchReviewerMRs(
            userID: user.id, baseURL: baseURL, token: token
        )

        let all = try await assigned + reviewing
        var seen = Set<Int>()
        return all.compactMap { mr -> MergeRequestEntity? in
            guard seen.insert(mr.id).inserted else { return nil }
            return MergeRequestEntity(from: mr)
        }
    }
}
