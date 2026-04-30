import AppIntents
import CoreSpotlight

// MARK: - Issue Entity

/// Exposes GitLab issues to Siri, Shortcuts, and Spotlight.
struct IssueEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Issue"

    static var defaultQuery = IssueQuery()

    // MARK: Stored properties

    let id: Int
    let iid: Int
    let title: String
    let state: String
    let projectID: Int
    let projectPath: String?
    let webURL: String
    let authorName: String

    // MARK: Display

    var displayRepresentation: DisplayRepresentation {
        let subtitle: String
        if let path = projectPath {
            subtitle = "\(path)#\(iid) \u{00B7} \(state)"
        } else {
            subtitle = "#\(iid) \u{00B7} \(state)"
        }
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)"
        )
    }

    // MARK: Spotlight

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.displayName = title
        attributes.contentDescription = projectPath.map { "\($0)#\(iid)" } ?? "#\(iid)"
        return attributes
    }

    // MARK: Conversion

    init(id: Int, iid: Int, title: String, state: String,
         projectID: Int, projectPath: String?, webURL: String,
         authorName: String) {
        self.id = id
        self.iid = iid
        self.title = title
        self.state = state
        self.projectID = projectID
        self.projectPath = projectPath
        self.webURL = webURL
        self.authorName = authorName
    }

    init(from issue: GitLabIssue) {
        self.id = issue.id
        self.iid = issue.iid
        self.title = issue.title
        self.state = issue.state
        self.projectID = issue.projectID
        self.projectPath = issue.projectPath
        self.webURL = issue.webURL
        self.authorName = issue.author.name
    }
}

// MARK: - Issue Query

struct IssueQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [IssueEntity] {
        // GitLab does not support fetching issues by global ID without project
        // context.  Return matches from the user's assigned/created issues instead.
        let all = try await fetchUserIssues()
        return all.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [IssueEntity] {
        guard let token = await AuthenticationService.shared.accessToken else { return [] }
        let baseURL = await AuthenticationService.shared.baseURL
        guard let user = await AuthenticationService.shared.currentUser else { return [] }

        // Search across the user's created issues by title match.
        let issues = try await GitLabAPIService.shared.fetchCreatedIssues(
            userID: user.id, baseURL: baseURL, token: token
        )
        let query = string.lowercased()
        return issues
            .filter { $0.title.lowercased().contains(query) }
            .map { IssueEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [IssueEntity] {
        try await fetchUserIssues()
    }

    // MARK: Helpers

    private func fetchUserIssues() async throws -> [IssueEntity] {
        guard let token = await AuthenticationService.shared.accessToken else { return [] }
        let baseURL = await AuthenticationService.shared.baseURL
        guard let user = await AuthenticationService.shared.currentUser else { return [] }

        let issues = try await GitLabAPIService.shared.fetchCreatedIssues(
            userID: user.id, baseURL: baseURL, token: token
        )
        return issues.map { IssueEntity(from: $0) }
    }
}
