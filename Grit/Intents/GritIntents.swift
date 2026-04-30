import AppIntents
import SwiftUI

// MARK: - Open Project

/// Opens a specific GitLab project in the app.
struct OpenProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Project"
    static var description = IntentDescription("Opens a GitLab project in Grit.")

    @Parameter(title: "Project")
    var project: ProjectEntity

    static var openAppWhenRun: Bool = true

    init() {}
    init(project: ProjectEntity) { self.project = project }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let token = AuthenticationService.shared.accessToken else {
            throw IntentError.notAuthenticated
        }
        let baseURL = AuthenticationService.shared.baseURL

        let repo = try await GitLabAPIService.shared.fetchRepository(
            projectID: project.id, baseURL: baseURL, token: token
        )

        let navState = AppNavigationState.shared
        navState.repoNavigationPath = NavigationPath()
        navState.repoNavigationPath.append(repo)
        navState.pendingDeepLinkTab = .repositories
        return .result()
    }
}

// MARK: - Search Projects

/// Searches for GitLab projects by name.
struct SearchProjectsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Projects"
    static var description = IntentDescription(
        "Searches for GitLab projects matching a query."
    )

    @Parameter(title: "Query")
    var query: String

    init() {}
    init(query: String) { self.query = query }

    func perform() async throws -> some IntentResult & ReturnsValue<[ProjectEntity]> & ProvidesDialog {
        guard let token = await AuthenticationService.shared.accessToken else {
            throw IntentError.notAuthenticated
        }
        let baseURL = await AuthenticationService.shared.baseURL

        let repos = try await GitLabAPIService.shared.searchRepositories(
            query: query, baseURL: baseURL, token: token
        )
        let entities = repos.map { ProjectEntity(from: $0) }

        let dialog: IntentDialog
        switch entities.count {
        case 0:
            dialog = "No projects found matching \"\(query)\"."
        case 1:
            dialog = "Found 1 project: \(entities[0].name)."
        default:
            let names = entities.prefix(3).map(\.name).joined(separator: ", ")
            dialog = "Found \(entities.count) projects: \(names)\(entities.count > 3 ? ", and more" : "")."
        }
        return .result(value: entities, dialog: dialog)
    }
}

// MARK: - Show My Merge Requests

/// Shows the user's open merge requests.
struct ShowMyMergeRequestsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show My Merge Requests"
    static var description = IntentDescription(
        "Shows your open GitLab merge requests, including ones assigned to you and ones awaiting your review."
    )

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let token = await AuthenticationService.shared.accessToken else {
            throw IntentError.notAuthenticated
        }
        let baseURL = await AuthenticationService.shared.baseURL
        guard let user = await AuthenticationService.shared.currentUser else {
            throw IntentError.notAuthenticated
        }

        async let assigned = GitLabAPIService.shared.fetchAssignedMRs(
            userID: user.id, baseURL: baseURL, token: token
        )
        async let reviewing = GitLabAPIService.shared.fetchReviewerMRs(
            userID: user.id, baseURL: baseURL, token: token
        )

        let assignedMRs = try await assigned
        let reviewMRs   = try await reviewing

        // Deduplicate (a user can be both assignee and reviewer).
        var seen = Set<Int>()
        let all = (assignedMRs + reviewMRs).filter { seen.insert($0.id).inserted }

        // Navigate to the Inbox tab where MRs are shown.
        await MainActor.run {
            AppNavigationState.shared.pendingDeepLinkTab = .inbox
        }

        let dialog: IntentDialog
        switch all.count {
        case 0:
            dialog = "You have no open merge requests right now."
        case 1:
            dialog = "You have 1 open merge request: \(all[0].title)."
        default:
            let drafts = all.filter { $0.isDraft }.count
            var parts = ["You have \(all.count) open merge requests"]
            if assignedMRs.count > 0 { parts.append("\(assignedMRs.count) assigned") }
            if reviewMRs.count > 0 { parts.append("\(reviewMRs.count) awaiting review") }
            if drafts > 0 { parts.append("\(drafts) drafts") }
            dialog = IntentDialog(stringLiteral: parts.joined(separator: ", ") + ".")
        }
        return .result(dialog: dialog)
    }
}

// MARK: - Show My Issues

/// Shows the user's open issues.
struct ShowMyIssuesIntent: AppIntent {
    static var title: LocalizedStringResource = "Show My Issues"
    static var description = IntentDescription(
        "Shows your open GitLab issues."
    )

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let token = await AuthenticationService.shared.accessToken else {
            throw IntentError.notAuthenticated
        }
        let baseURL = await AuthenticationService.shared.baseURL
        guard let user = await AuthenticationService.shared.currentUser else {
            throw IntentError.notAuthenticated
        }

        let issues = try await GitLabAPIService.shared.fetchCreatedIssues(
            userID: user.id, baseURL: baseURL, token: token
        )

        // Navigate to the Inbox tab.
        await MainActor.run {
            AppNavigationState.shared.pendingDeepLinkTab = .inbox
        }

        let dialog: IntentDialog
        switch issues.count {
        case 0:
            dialog = "You have no open issues right now."
        case 1:
            dialog = "You have 1 open issue: \(issues[0].title)."
        default:
            dialog = IntentDialog(stringLiteral: "You have \(issues.count) open issues.")
        }
        return .result(dialog: dialog)
    }
}

// MARK: - Get Contributions

/// Returns the user's GitLab contribution statistics.
struct GetContributionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Contributions"
    static var description = IntentDescription(
        "Shows your GitLab contribution statistics, including total contributions and current streak."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Try the shared widget data store first for instant results.
        if let snapshot = WidgetDataStore.load() {
            var parts: [String] = []
            parts.append("\(snapshot.totalContributions) total contributions this year")
            if snapshot.currentStreak > 0 {
                parts.append("current streak of \(snapshot.currentStreak) days")
            }
            if snapshot.longestStreak > 0 {
                parts.append("longest streak of \(snapshot.longestStreak) days")
            }
            let dialog = IntentDialog(stringLiteral: parts.joined(separator: ", ") + ".")
            return .result(dialog: dialog)
        }

        // Fall back to a generic message when no cached data is available.
        return .result(dialog: "Open Grit and visit your profile to load contribution data.")
    }
}

// MARK: - Intent Errors

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notAuthenticated
    case projectNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAuthenticated:
            return "You need to sign in to Grit first."
        case .projectNotFound:
            return "The project could not be found."
        }
    }
}
