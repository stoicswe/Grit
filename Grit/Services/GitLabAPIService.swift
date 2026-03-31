import Foundation

actor GitLabAPIService {
    static let shared = GitLabAPIService()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
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
        method: String = "POST"
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/v4/\(endpoint)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
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

    // MARK: - Notifications

    func fetchNotifications(baseURL: String, token: String) async throws -> [GitLabNotification] {
        return try await request("notifications", baseURL: baseURL, token: token, queryItems: [
            URLQueryItem(name: "per_page", value: "50")
        ])
    }

    func markNotificationRead(id: Int, baseURL: String, token: String) async throws {
        try await voidPost(
            "notifications/\(id)/mark_as_read",
            baseURL: baseURL,
            token: token,
            method: "DELETE"
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
