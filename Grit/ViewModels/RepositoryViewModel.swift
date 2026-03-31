import Foundation
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var searchResults: [Repository] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var error: String?
    @Published var currentPage = 1
    @Published var hasMore = true

    private var searchTask: Task<Void, Never>?
    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func loadRepositories(refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }
        if refresh { currentPage = 1; hasMore = true }
        guard hasMore else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let results = try await api.fetchUserRepositories(
                baseURL: auth.baseURL, token: token, page: currentPage
            )
            if refresh {
                repositories = results
            } else {
                repositories.append(contentsOf: results)
            }
            hasMore = results.count == 20
            currentPage += 1
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

    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(projectID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let repoTask = api.fetchRepository(projectID: projectID, baseURL: auth.baseURL, token: token)
            async let branchesTask = api.fetchBranches(projectID: projectID, baseURL: auth.baseURL, token: token)
            async let mrsTask = api.fetchMergeRequests(projectID: projectID, baseURL: auth.baseURL, token: token)

            let (repo, fetchedBranches, mrs) = try await (repoTask, branchesTask, mrsTask)
            repository = repo
            branches = fetchedBranches
            mergeRequests = mrs
            selectedBranch = repo.defaultBranch ?? fetchedBranches.first(where: { $0.isDefault })?.name

            if let branch = selectedBranch {
                commits = try await api.fetchCommits(
                    projectID: projectID, branch: branch, baseURL: auth.baseURL, token: token
                )
            }
        } catch {
            self.error = error.localizedDescription
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
}
