import Foundation
import SwiftUI

enum RepoSortOrder: String, CaseIterable, Identifiable {
    case recentlyEdited = "Recently Edited"
    case alphabetical   = "Alphabetical"
    case newestFirst    = "Newest First"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recentlyEdited: return "clock"
        case .alphabetical:   return "textformat.abc"
        case .newestFirst:    return "calendar.badge.plus"
        }
    }
}

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var searchResults: [Repository] = []
    @Published var sortOrder: RepoSortOrder = .recentlyEdited
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var error: String?
    @Published var currentPage = 1
    @Published var hasMore = true

    var sortedRepositories: [Repository] {
        switch sortOrder {
        case .recentlyEdited:
            return repositories.sorted {
                ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
            }
        case .alphabetical:
            return repositories.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .newestFirst:
            return repositories.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
        }
    }

    /// Guards against concurrent pagination calls triggered by SwiftUI
    /// re-firing the load-more `onAppear` when the list re-renders.
    private var isPaginating = false
    private var searchTask: Task<Void, Never>?
    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func loadRepositories(refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }

        if refresh {
            // Reset state for a full reload; also cancels any in-flight pagination
            currentPage  = 1
            hasMore      = true
            isPaginating = false
        } else {
            // Pagination path — bail if already loading or nothing left
            guard !isPaginating, hasMore else { return }
            isPaginating = true
        }

        isLoading = true
        error     = nil
        defer {
            isLoading    = false
            isPaginating = false
        }

        // Snapshot the page we're about to fetch so we can detect if a
        // concurrent refresh reset currentPage underneath us while awaiting.
        let page = currentPage

        do {
            let results = try await api.fetchUserRepositories(
                baseURL: auth.baseURL, token: token, page: page
            )

            if refresh {
                repositories = results
            } else if currentPage == page {
                // Only append if currentPage hasn't been reset by a concurrent
                // refresh — prevents the stale page from duplicating entries.
                let existingIDs = Set(repositories.map(\.id))
                let fresh = results.filter { !existingIDs.contains($0.id) }
                repositories.append(contentsOf: fresh)
            }

            hasMore     = results.count == 20
            currentPage = page + 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    func search(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                searchResults = try await api.searchRepositories(
                    query: query, baseURL: auth.baseURL, token: token
                )
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

@MainActor
final class RepositoryDetailViewModel: ObservableObject {
    @Published var repository: Repository?
    @Published var branches: [Branch] = []
    @Published var commits: [Commit] = []
    @Published var mergeRequests: [MergeRequest] = []
    @Published var selectedBranch: String?
    @Published var isLoading = false
    @Published var error: String?

    /// The user's current notification level for this project as returned by the GitLab API.
    /// Possible values: "disabled", "mention", "participating", "watch", "global", "custom"
    @Published var notificationLevel: String? = nil
    @Published var isTogglingWatch = false
    /// Latest pipeline for the default branch; nil when the project has no CI.
    @Published var defaultBranchPipeline: Pipeline?
    @Published var isPipelineLoading: Bool = false

    /// True when the current level is "watch".
    var isWatching: Bool { notificationLevel == "watch" }

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(projectID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let repoTask     = api.fetchRepository(projectID: projectID, baseURL: auth.baseURL, token: token)
            async let branchesTask = api.fetchBranches(projectID: projectID, baseURL: auth.baseURL, token: token)
            async let mrsTask      = api.fetchMergeRequests(projectID: projectID, baseURL: auth.baseURL, token: token)

            let (repo, fetchedBranches, mrs) = try await (repoTask, branchesTask, mrsTask)
            repository     = repo
            branches       = fetchedBranches
            mergeRequests  = mrs
            selectedBranch = repo.defaultBranch ?? fetchedBranches.first(where: { $0.isDefault })?.name

            if let branch = selectedBranch {
                commits = try await api.fetchCommits(
                    projectID: projectID, branch: branch, baseURL: auth.baseURL, token: token
                )
            }
        } catch {
            self.error = error.localizedDescription
        }

        // Fetch watch level independently — a failure here shouldn't break the rest of the view.
        notificationLevel = (try? await api.fetchProjectNotificationLevel(
            projectID: projectID, baseURL: auth.baseURL, token: token
        ))?.level

        // Fetch the default-branch pipeline status independently; hidden if absent.
        if let branch = selectedBranch {
            isPipelineLoading = true
            defaultBranchPipeline = try? await api.fetchLatestPipeline(
                projectID: projectID, ref: branch,
                baseURL: auth.baseURL, token: token
            )
            isPipelineLoading = false
        }
    }

    func loadCommits(projectID: Int, branch: String) async {
        guard let token = auth.accessToken else { return }
        do {
            commits = try await api.fetchCommits(
                projectID: projectID, branch: branch, baseURL: auth.baseURL, token: token
            )
            selectedBranch = branch
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Toggles the watch state between "watch" and "global" (the user's default).
    func toggleWatch(projectID: Int) async {
        guard let token = auth.accessToken else { return }
        isTogglingWatch = true
        defer { isTogglingWatch = false }

        let targetLevel = isWatching ? "global" : "watch"
        do {
            let result = try await api.setProjectNotificationLevel(
                projectID: projectID,
                level: targetLevel,
                baseURL: auth.baseURL,
                token: token
            )
            notificationLevel = result.level
        } catch {
            self.error = "Could not update watch status: \(error.localizedDescription)"
        }
    }
}
