import AppIntents
import CoreSpotlight

// MARK: - Project Entity

/// Exposes GitLab projects (repositories) to Siri, Shortcuts, and Spotlight.
struct ProjectEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"

    static var defaultQuery = ProjectQuery()

    // MARK: Stored properties

    let id: Int
    let name: String
    let fullPath: String
    let visibility: String
    let description: String?
    let starCount: Int
    let webURL: String

    // MARK: Display

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(fullPath)"
        )
    }

    // MARK: Spotlight

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.displayName = name
        attributes.contentDescription = description ?? fullPath
        return attributes
    }

    // MARK: Conversion

    init(id: Int, name: String, fullPath: String, visibility: String,
         description: String?, starCount: Int, webURL: String) {
        self.id = id
        self.name = name
        self.fullPath = fullPath
        self.visibility = visibility
        self.description = description
        self.starCount = starCount
        self.webURL = webURL
    }

    init(from repository: Repository) {
        self.id = repository.id
        self.name = repository.name
        self.fullPath = repository.nameWithNamespace
        self.visibility = repository.visibility
        self.description = repository.description
        self.starCount = repository.starCount
        self.webURL = repository.webURL
    }
}

// MARK: - Project Query

struct ProjectQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [ProjectEntity] {
        guard let token = await AuthenticationService.shared.accessToken else { return [] }
        let baseURL = await AuthenticationService.shared.baseURL

        var results: [ProjectEntity] = []
        for id in identifiers {
            if let repo = try? await GitLabAPIService.shared.fetchRepository(
                projectID: id, baseURL: baseURL, token: token
            ) {
                results.append(ProjectEntity(from: repo))
            }
        }
        return results
    }

    func entities(matching string: String) async throws -> [ProjectEntity] {
        guard let token = await AuthenticationService.shared.accessToken else { return [] }
        let baseURL = await AuthenticationService.shared.baseURL

        let repos = try await GitLabAPIService.shared.searchRepositories(
            query: string, baseURL: baseURL, token: token
        )
        return repos.map { ProjectEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        guard let token = await AuthenticationService.shared.accessToken else { return [] }
        let baseURL = await AuthenticationService.shared.baseURL

        let repos = try await GitLabAPIService.shared.fetchUserRepositories(
            baseURL: baseURL, token: token, page: 1
        )
        return repos.map { ProjectEntity(from: $0) }
    }
}
