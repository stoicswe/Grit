import Foundation

actor GitLabAPIService {
    static let shared = GitLabAPIService()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        // Prevent URLSession from intercepting 304 Not Modified responses and
        // substituting a stale cached body. GitLab uses 304 as a semantic signal
        // (e.g. "already starred / already unstarred") — we need to see the real
        // status code, not a cache-promoted 200 with old data.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]

            if let date = withFractional.date(from: string) { return date }
            if let date = withoutFractional.date(from: string) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(string)"
            )
        }
    }

    // MARK: - Generic Request

    private func request<T: Decodable>(
        _ endpoint: String,
        baseURL: String,
        token: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(string: "\(baseURL)/api/v4/\(endpoint)")!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(
        _ endpoint: String,
        baseURL: String,
        token: String,
        body: B,
        method: String = "POST"
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)/api/v4/\(endpoint)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(T.self, from: data)
    }

    private func voidPost(
        _ endpoint: String,
        baseURL: String,
        token: String,
        method: String = "POST",
        extraSuccessCodes: Set<Int> = []
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/v4/\(endpoint)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let code = httpResponse.statusCode
        guard (200...299).contains(code) || extraSuccessCodes.contains(code) else {
            throw APIError.httpError(code)
        }
    }

    // MARK: - User

    func fetchCurrentUser(baseURL: String, token: String) async throws -> GitLabUser {
        return try await request("user", baseURL: baseURL, token: token)
    }

    func fetchUser(id: Int, baseURL: String, token: String) async throws -> GitLabUser {
        return try await request("users/\(id)", baseURL: baseURL, token: token)
    }

    // MARK: - Repositories

    func fetchUserRepositories(
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [Repository] {
        return try await request("projects", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "membership", value: "true"),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "statistics", value: "true")
        ])
    }

    func searchRepositories(
        query: String,
        baseURL: String,
        token: String
    ) async throws -> [Repository] {
        return try await request("projects", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "per_page", value: "25"),
            URLQueryItem(name: "statistics", value: "true")
        ])
    }

    /// Browse all accessible GitLab projects sorted by the given field.
    /// Valid order_by values: "star_count", "last_activity_at", "created_at", "name", "id"
    func fetchExploreProjects(
        orderBy: String = "star_count",
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [Repository] {
        return try await request("projects", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "order_by", value: orderBy),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "25"),
            URLQueryItem(name: "page", value: "\(page)")
        ])
    }

    // MARK: - Starring

    func fetchStarredProjects(baseURL: String, token: String) async throws -> [Repository] {
        return try await request("projects", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "starred", value: "true"),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "per_page", value: "50")
        ])
    }

    func starProject(projectID: Int, baseURL: String, token: String) async throws {
        // GitLab returns 201 on first star, 304 if already starred — both are success
        try await voidPost("projects/\(projectID)/star", baseURL: baseURL, token: token,
                           extraSuccessCodes: [304])
    }

    func unstarProject(projectID: Int, baseURL: String, token: String) async throws {
        // GitLab v4 API: POST /projects/:id/unstar
        // Returns 200 OK (successfully unstarred) or 304 Not Modified (wasn't starred).
        // The old DELETE /projects/:id/star was a v3 endpoint and returns 404 on modern instances.
        try await voidPost("projects/\(projectID)/unstar", baseURL: baseURL, token: token,
                           extraSuccessCodes: [304])
    }

    func fetchRepository(projectID: Int, baseURL: String, token: String) async throws -> Repository {
        return try await request("projects/\(projectID)", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "statistics", value: "true")
        ])
    }

    // MARK: - Branches

    func fetchBranches(
        projectID: Int,
        baseURL: String,
        token: String,
        search: String? = nil
    ) async throws -> [Branch] {
        var items = [
            URLQueryItem(name: "per_page", value: "50")
        ]
        if let search { items.append(URLQueryItem(name: "search", value: search)) }
        return try await request(
            "projects/\(projectID)/repository/branches",
            baseURL: baseURL,
            token: token,
            queryItems: items
        )
    }

    // MARK: - Commits

    func fetchCommits(
        projectID: Int,
        branch: String? = nil,
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [Commit] {
        var items = [
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "with_stats", value: "true")
        ]
        if let branch { items.append(URLQueryItem(name: "ref_name", value: branch)) }
        return try await request(
            "projects/\(projectID)/repository/commits",
            baseURL: baseURL,
            token: token,
            queryItems: items
        )
    }

    func fetchCommitDiff(projectID: Int, sha: String, baseURL: String, token: String) async throws -> [CommitDiff] {
        return try await request(
            "projects/\(projectID)/repository/commits/\(sha)/diff",
            baseURL: baseURL,
            token: token,
            queryItems: [URLQueryItem(name: "per_page", value: "50")]
        )
    }

    // MARK: - Issues

    func fetchIssue(
        projectID: Int,
        issueIID: Int,
        baseURL: String,
        token: String
    ) async throws -> GitLabIssue {
        return try await request(
            "projects/\(projectID)/issues/\(issueIID)",
            baseURL: baseURL,
            token: token
        )
    }

    /// Search a project for an issue by title (all states). Used when target_iid is
    /// absent from an activity event — returns the exact-title match, or the first result.
    func fetchIssueByTitle(
        projectID: Int,
        title: String,
        baseURL: String,
        token: String
    ) async throws -> GitLabIssue? {
        let results: [GitLabIssue] = try await request(
            "projects/\(projectID)/issues",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "search",   value: title),
                URLQueryItem(name: "state",    value: "all"),
                URLQueryItem(name: "per_page", value: "5")
            ]
        )
        return results.first { $0.title == title } ?? results.first
    }

    func fetchIssues(
        projectID: Int,
        state: String = "opened",
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [GitLabIssue] {
        return try await request(
            "projects/\(projectID)/issues",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "state",    value: state),
                URLQueryItem(name: "per_page", value: "20"),
                URLQueryItem(name: "page",     value: "\(page)"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort",     value: "desc")
            ]
        )
    }

    func fetchIssueNotes(
        projectID: Int,
        issueIID: Int,
        baseURL: String,
        token: String
    ) async throws -> [GitLabIssueNote] {
        return try await request(
            "projects/\(projectID)/issues/\(issueIID)/notes",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "order_by", value: "created_at"),
                URLQueryItem(name: "sort",     value: "asc")
            ]
        )
    }

    func addIssueNote(
        projectID: Int,
        issueIID: Int,
        body: String,
        baseURL: String,
        token: String
    ) async throws -> GitLabIssueNote {
        return try await post(
            "projects/\(projectID)/issues/\(issueIID)/notes",
            baseURL: baseURL,
            token: token,
            body: NoteBody(body: body)
        )
    }

    func subscribeToIssue(
        projectID: Int,
        issueIID: Int,
        baseURL: String,
        token: String
    ) async throws {
        try await voidPost(
            "projects/\(projectID)/issues/\(issueIID)/subscribe",
            baseURL: baseURL,
            token: token
        )
    }

    func unsubscribeFromIssue(
        projectID: Int,
        issueIID: Int,
        baseURL: String,
        token: String
    ) async throws {
        try await voidPost(
            "projects/\(projectID)/issues/\(issueIID)/unsubscribe",
            baseURL: baseURL,
            token: token
        )
    }

    // MARK: - Follow

    private struct EmptyBody: Encodable {}

    func fetchUserProjects(userID: Int, baseURL: String, token: String) async throws -> [Repository] {
        return try await request("users/\(userID)/projects", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "per_page", value: "10")
        ])
    }

    @discardableResult
    func followUser(userID: Int, baseURL: String, token: String) async throws -> GitLabUser {
        return try await post("users/\(userID)/follow", baseURL: baseURL, token: token, body: EmptyBody())
    }

    @discardableResult
    func unfollowUser(userID: Int, baseURL: String, token: String) async throws -> GitLabUser {
        return try await post("users/\(userID)/unfollow", baseURL: baseURL, token: token, body: EmptyBody(), method: "DELETE")
    }

    func searchUsers(query: String, baseURL: String, token: String) async throws -> [GitLabUser] {
        return try await request("users", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per_page", value: "5")
        ])
    }

    func fetchUserFollowers(userID: Int, baseURL: String, token: String) async throws -> [GitLabUser] {
        return try await request("users/\(userID)/followers", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "per_page", value: "30")
        ])
    }

    // MARK: - Contributors

    /// Returns contributors sorted by commit count (descending).
    func fetchContributors(
        projectID: Int,
        baseURL: String,
        token: String
    ) async throws -> [GitLabContributor] {
        return try await request(
            "projects/\(projectID)/repository/contributors",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "sort",     value: "desc"),
                URLQueryItem(name: "per_page", value: "50")
            ]
        )
    }

    /// Fetches and base64-decodes the repository README.
    /// Tries the most common README filenames in order; returns `nil` if none exist.
    /// Never throws — a missing README is not an error.
    func fetchReadme(
        projectID: Int,
        ref: String,
        baseURL: String,
        token: String
    ) async -> String? {
        let candidates = ["README.md", "readme.md", "README", "README.rst", "README.txt"]
        for candidate in candidates {
            if let file = try? await fetchFileContent(
                projectID: projectID,
                filePath: candidate,
                ref: ref,
                baseURL: baseURL,
                token: token
            ), let text = file.decodedContent {
                return text
            }
        }
        return nil
    }

    // MARK: - Forks

    func fetchForks(
        projectID: Int,
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [Repository] {
        return try await request(
            "projects/\(projectID)/forks",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page",   value: "20"),
                URLQueryItem(name: "page",       value: "\(page)"),
                URLQueryItem(name: "order_by",   value: "last_activity_at"),
                URLQueryItem(name: "sort",       value: "desc"),
                URLQueryItem(name: "statistics", value: "true")
            ]
        )
    }

    func fetchCommit(projectID: Int, sha: String, baseURL: String, token: String) async throws -> Commit {
        return try await request(
            "projects/\(projectID)/repository/commits/\(sha)",
            baseURL: baseURL,
            token: token,
            queryItems: [URLQueryItem(name: "stats", value: "true")]
        )
    }

    // MARK: - Merge Requests

    func fetchMergeRequests(
        projectID: Int,
        state: String = "opened",
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [MergeRequest] {
        return try await request(
            "projects/\(projectID)/merge_requests",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "per_page", value: "20"),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "with_labels_details", value: "false")
            ]
        )
    }

    func fetchMergeRequest(
        projectID: Int,
        mrIID: Int,
        baseURL: String,
        token: String
    ) async throws -> MergeRequest {
        return try await request(
            "projects/\(projectID)/merge_requests/\(mrIID)",
            baseURL: baseURL,
            token: token
        )
    }

    /// Search a project for an MR by title (all states). Used when target_iid is
    /// absent from an activity event — returns the exact-title match, or the first result.
    func fetchMRByTitle(
        projectID: Int,
        title: String,
        baseURL: String,
        token: String
    ) async throws -> MergeRequest? {
        let results: [MergeRequest] = try await request(
            "projects/\(projectID)/merge_requests",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "search",   value: title),
                URLQueryItem(name: "state",    value: "all"),
                URLQueryItem(name: "per_page", value: "5")
            ]
        )
        return results.first { $0.title == title } ?? results.first
    }

    func fetchMRNotes(
        projectID: Int,
        mrIID: Int,
        baseURL: String,
        token: String
    ) async throws -> [MRNote] {
        return try await request(
            "projects/\(projectID)/merge_requests/\(mrIID)/notes",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "order_by", value: "created_at")
            ]
        )
    }

    func approveMergeRequest(projectID: Int, mrIID: Int, baseURL: String, token: String) async throws {
        try await voidPost(
            "projects/\(projectID)/merge_requests/\(mrIID)/approve",
            baseURL: baseURL,
            token: token
        )
    }

    func unapproveMergeRequest(projectID: Int, mrIID: Int, baseURL: String, token: String) async throws {
        try await voidPost(
            "projects/\(projectID)/merge_requests/\(mrIID)/unapprove",
            baseURL: baseURL,
            token: token
        )
    }

    struct NoteBody: Encodable { let body: String }

    func addMRComment(
        projectID: Int,
        mrIID: Int,
        body: String,
        baseURL: String,
        token: String
    ) async throws -> MRNote {
        return try await post(
            "projects/\(projectID)/merge_requests/\(mrIID)/notes",
            baseURL: baseURL,
            token: token,
            body: NoteBody(body: body)
        )
    }

    func fetchMRDiffs(
        projectID: Int,
        mrIID: Int,
        baseURL: String,
        token: String
    ) async throws -> [CommitDiff] {
        return try await request(
            "projects/\(projectID)/merge_requests/\(mrIID)/diffs",
            baseURL: baseURL,
            token: token,
            queryItems: [URLQueryItem(name: "per_page", value: "50")]
        )
    }

    func fetchMRApprovals(
        projectID: Int,
        mrIID: Int,
        baseURL: String,
        token: String
    ) async throws -> MRApprovalState {
        return try await request(
            "projects/\(projectID)/merge_requests/\(mrIID)/approvals",
            baseURL: baseURL,
            token: token
        )
    }

    func fetchProjectMemberSelf(
        projectID: Int,
        userID: Int,
        baseURL: String,
        token: String
    ) async throws -> ProjectMember {
        return try await request(
            "projects/\(projectID)/members/all/\(userID)",
            baseURL: baseURL,
            token: token
        )
    }

    func mergeMergeRequest(
        projectID: Int,
        mrIID: Int,
        baseURL: String,
        token: String
    ) async throws {
        try await voidPost(
            "projects/\(projectID)/merge_requests/\(mrIID)/merge",
            baseURL: baseURL,
            token: token
        )
    }

    // MARK: - Project Notification Level (Watch)

    /// Returns the authenticated user's notification level for the given project.
    func fetchProjectNotificationLevel(
        projectID: Int,
        baseURL: String,
        token: String
    ) async throws -> ProjectNotificationLevel {
        return try await request(
            "projects/\(projectID)/notification_settings",
            baseURL: baseURL,
            token: token
        )
    }

    private struct NotificationLevelBody: Encodable { let level: String }

    /// Sets the authenticated user's notification level for the given project.
    /// Use level "watch" to watch, "global" to restore the user's global default.
    @discardableResult
    func setProjectNotificationLevel(
        projectID: Int,
        level: String,
        baseURL: String,
        token: String
    ) async throws -> ProjectNotificationLevel {
        return try await post(
            "projects/\(projectID)/notification_settings",
            baseURL: baseURL,
            token: token,
            body: NotificationLevelBody(level: level),
            method: "PUT"
        )
    }

    // MARK: - Inbox

    /// Fetches open MRs where the given user is the assignee.
    /// Uses explicit `assignee_id` instead of `scope=assigned_to_me` for compatibility
    /// with self-hosted GitLab instances where the global scope filter may return HTTP 400.
    func fetchAssignedMRs(
        userID: Int,
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [MergeRequest] {
        return try await request(
            "merge_requests",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "assignee_id", value: "\(userID)"),
                URLQueryItem(name: "state",       value: "opened"),
                URLQueryItem(name: "per_page",    value: "50"),
                URLQueryItem(name: "page",        value: "\(page)"),
                URLQueryItem(name: "order_by",    value: "updated_at"),
                URLQueryItem(name: "sort",        value: "desc")
            ]
        )
    }

    /// Fetches open MRs where the given user is a requested reviewer.
    /// Uses explicit `reviewer_id` instead of `scope=reviewer_of_me` for compatibility
    /// with self-hosted GitLab instances where the global scope filter may return HTTP 400.
    func fetchReviewerMRs(
        userID: Int,
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [MergeRequest] {
        return try await request(
            "merge_requests",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "reviewer_id", value: "\(userID)"),
                URLQueryItem(name: "state",       value: "opened"),
                URLQueryItem(name: "per_page",    value: "50"),
                URLQueryItem(name: "page",        value: "\(page)"),
                URLQueryItem(name: "order_by",    value: "updated_at"),
                URLQueryItem(name: "sort",        value: "desc")
            ]
        )
    }

    /// Fetches open issues authored by the specified user.
    /// Uses `author_id` rather than `scope=created_by_me` for compatibility with
    /// self-hosted GitLab instances where the global scope filter may return HTTP 400.
    func fetchCreatedIssues(
        userID: Int,
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [GitLabIssue] {
        return try await request(
            "issues",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "author_id", value: "\(userID)"),
                URLQueryItem(name: "state",     value: "opened"),
                URLQueryItem(name: "per_page",  value: "50"),
                URLQueryItem(name: "page",      value: "\(page)"),
                URLQueryItem(name: "order_by",  value: "updated_at"),
                URLQueryItem(name: "sort",      value: "desc")
            ]
        )
    }

    // MARK: - User Events (Contribution Graph)

    func fetchUserEvents(
        username: String,
        baseURL: String,
        token: String,
        after: Date? = nil
    ) async throws -> [ContributionEvent] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: "100")
        ]
        if let after {
            let formatter = ISO8601DateFormatter()
            items.append(URLQueryItem(name: "after", value: formatter.string(from: after)))
        }
        return try await request(
            "users/\(username)/events",
            baseURL: baseURL,
            token: token,
            queryItems: items
        )
    }

    // MARK: - Activity Feed

    /// Fetches recent events for a specific project (`GET /projects/:id/events`).
    /// Used for starred-project activity, where the user may not be a member.
    func fetchProjectEvents(
        projectID: Int,
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [ActivityEvent] {
        return try await request(
            "projects/\(projectID)/events",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "page",     value: "\(page)"),
                URLQueryItem(name: "sort",     value: "desc")
            ]
        )
    }

    /// Fetches the authenticated user's global activity news feed (`GET /events`).
    /// Includes events from projects the user is a member of and users they follow.
    func fetchActivityFeed(
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [ActivityEvent] {
        return try await request(
            "events",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page",     value: "\(page)"),
                URLQueryItem(name: "sort",     value: "desc")
            ]
        )
    }

    /// Fetches events authored by the specified user (`GET /users/:id/events`).
    func fetchUserActivityEvents(
        userID: Int,
        baseURL: String,
        token: String,
        page: Int = 1
    ) async throws -> [ActivityEvent] {
        return try await request(
            "users/\(userID)/events",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page",     value: "\(page)"),
                URLQueryItem(name: "sort",     value: "desc")
            ]
        )
    }

    /// Fetches the list of users that the specified user is following.
    func fetchFollowing(
        userID: Int,
        baseURL: String,
        token: String
    ) async throws -> [GitLabUser] {
        return try await request(
            "users/\(userID)/following",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
    }

    /// Fetches projects the authenticated user is a member of.
    /// Used in ActivityViewModel to identify "Your Projects" events.
    func fetchMemberProjects(
        baseURL: String,
        token: String
    ) async throws -> [Repository] {
        return try await request(
            "projects",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "membership", value: "true"),
                URLQueryItem(name: "per_page",   value: "100"),
                URLQueryItem(name: "order_by",   value: "last_activity_at"),
                URLQueryItem(name: "sort",        value: "desc")
            ]
        )
    }

    // MARK: - Notifications

    /// Fetches the user's pending todos via GitLab's Todos API (`GET /todos`).
    /// GitLab does not have a `GET /notifications` endpoint — todos are the equivalent.
    func fetchNotifications(baseURL: String, token: String) async throws -> [GitLabNotification] {
        return try await request("todos", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "state",    value: "pending"),
            URLQueryItem(name: "per_page", value: "50")
        ])
    }

    /// Marks a GitLab todo as done (`POST /todos/:id/mark_as_done`).
    func markNotificationRead(id: Int, baseURL: String, token: String) async throws {
        try await voidPost(
            "todos/\(id)/mark_as_done",
            baseURL: baseURL,
            token: token,
            method: "POST"
        )
    }

    // MARK: - Repository File Tree

    func fetchRepositoryTree(
        projectID: Int,
        path: String = "",
        ref: String,
        baseURL: String,
        token: String
    ) async throws -> [RepositoryFile] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "ref", value: ref),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "recursive", value: "false")
        ]
        if !path.isEmpty {
            items.append(URLQueryItem(name: "path", value: path))
        }
        return try await request(
            "projects/\(projectID)/repository/tree",
            baseURL: baseURL,
            token: token,
            queryItems: items
        )
    }

    func fetchFileContent(
        projectID: Int,
        filePath: String,
        ref: String,
        baseURL: String,
        token: String
    ) async throws -> FileContent {
        // GitLab requires slashes in the file path to be encoded as %2F.
        // .urlPathAllowed leaves "/" unencoded, so we remove it from the set.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: allowed) ?? filePath

        // Also percent-encode the ref for the query string
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ref

        // Build URL directly — URLComponents would re-decode %2F back to /
        let urlString = "\(baseURL)/api/v4/projects/\(projectID)/repository/files/\(encodedPath)?ref=\(encodedRef)"
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        return try decoder.decode(FileContent.self, from: data)
    }

    // MARK: - Search

    func searchGlobal(
        query: String,
        scope: String = "projects",
        baseURL: String,
        token: String
    ) async throws -> [SearchProject] {
        return try await request(
            "search",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "scope", value: scope),
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "per_page", value: "25")
            ]
        )
    }

    func searchRepository(
        projectID: Int,
        query: String,
        scope: String = "blobs",
        baseURL: String,
        token: String
    ) async throws -> [SearchBlob] {
        return try await request(
            "projects/\(projectID)/search",
            baseURL: baseURL,
            token: token,
            queryItems: [
                URLQueryItem(name: "scope", value: scope),
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "per_page", value: "25")
            ]
        )
    }

    // MARK: - Error

    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .invalidResponse: return "Invalid response from server"
            case .httpError(let code): return "Server returned HTTP \(code)"
            }
        }
    }
}
