import Foundation
import SwiftUI

// MARK: - Result chunk types (used by withTaskGroup for progressive delivery)

private enum GlobalChunk: Sendable {
    case publicRepos([Repository])
    case memberRepos([Repository])
    case topics([Repository])
    case groups([GitLabGroup])
    case users([GitLabUser])
    case files([SearchBlob])
    case commits([Commit])
    case mrs([MergeRequest])
}

private enum RepoChunk: Sendable {
    case blobs([SearchBlob])
    case commits([Commit])
    case mrs([MergeRequest])
}

private enum UserRepoChunk: Sendable {
    case files([SearchBlob])
    case commits([Commit])
    case mrs([MergeRequest])
}

// MARK: - ViewModel

@MainActor
final class SearchViewModel: ObservableObject {

    // MARK: - Global / repo-list search results

    @Published var projectResults:    [Repository]   = []  // repos by name
    @Published var taggedRepoResults: [Repository]   = []  // repos by topic
    @Published var groupResults:      [GitLabGroup]  = []
    @Published var userResults:       [GitLabUser]   = []
    @Published var fileResults:       [SearchBlob]   = []  // blobs across all projects
    @Published var commitResults:     [Commit]       = []  // commits across all projects
    @Published var mrResults:         [MergeRequest] = []  // MRs across all projects

    // MARK: - In-repo search results

    @Published var repoBlobResults:   [SearchBlob]   = []
    @Published var repoCommitResults: [Commit]       = []
    @Published var repoMRResults:     [MergeRequest] = []

    // MARK: - State

    @Published var isSearching = false
    @Published var error: String?

    /// True when every global result set is empty (used to decide between "loading" and "no results").
    var globalIsEmpty: Bool {
        projectResults.isEmpty    &&
        taggedRepoResults.isEmpty &&
        groupResults.isEmpty      &&
        userResults.isEmpty       &&
        fileResults.isEmpty       &&
        commitResults.isEmpty     &&
        mrResults.isEmpty
    }

    /// True when every in-repo result set is empty.
    var repoIsEmpty: Bool {
        repoBlobResults.isEmpty && repoCommitResults.isEmpty && repoMRResults.isEmpty
    }

    private var searchTask: Task<Void, Never>?
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Animation spring

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.85)

    // MARK: - User-repos search (Repositories tab)

    /// Searches within the provided list of user-owned repositories.
    ///
    /// **Repo name/description/topics**: matched locally — zero network, perfectly scoped.
    /// Result is published immediately so the Repositories section appears before
    /// the API calls for blobs/commits/MRs return.
    ///
    /// **Blobs, commits, MRs**: global endpoint filtered client-side to user's project IDs.
    /// Each section updates independently as its call completes.
    func searchWithinUserRepos(query: String, userRepos: [Repository]) {
        guard !query.isEmpty else { resetGlobal(); return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }

            let q = query.lowercased()
            let userProjectIDs = Set(userRepos.map(\.id))

            // ── Local repo match — instant, no network ────────────────────────
            let matched = userRepos.filter {
                $0.name.lowercased().contains(q) ||
                $0.nameWithNamespace.lowercased().contains(q) ||
                ($0.description?.lowercased().contains(q) ?? false) ||
                ($0.topics?.contains(where: { $0.lowercased().contains(q) }) ?? false)
            }
            withAnimation(spring) {
                projectResults    = matched
                taggedRepoResults = []
                groupResults      = []
                userResults       = []
            }

            isSearching = true

            let base = auth.baseURL

            // ── API: blobs / commits / MRs — each section updates on arrival ──
            await withTaskGroup(of: UserRepoChunk.self) { group in
                group.addTask {
                    .files((try? await self.api.searchBlobsGlobal(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .commits((try? await self.api.searchCommitsGlobal(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .mrs((try? await self.api.searchMergeRequestsGlobal(
                        query: query, baseURL: base, token: token)) ?? [])
                }

                for await chunk in group {
                    if Task.isCancelled { break }
                    withAnimation(spring) {
                        switch chunk {
                        case .files(let r):
                            fileResults   = r.filter { userProjectIDs.contains($0.projectID) }
                        case .commits(let r):
                            commitResults = r.filter { userProjectIDs.contains($0.projectID ?? -1) }
                        case .mrs(let r):
                            mrResults     = r.filter { userProjectIDs.contains($0.projectID) }
                        }
                    }
                }
            }

            isSearching = false
        }
    }

    // MARK: - Global search (Explore / SearchView without a repo context)

    /// Fires eight concurrent searches. Each section is published the moment its
    /// call completes — users see groups, users, files etc. appearing one by one
    /// rather than waiting for the slowest endpoint to return.
    ///
    /// Project results (public + member) are accumulated across two tasks and
    /// re-merged each time either one lands, so member repos appear immediately
    /// even if the public search is still in-flight.
    func searchGlobal(query: String) {
        guard !query.isEmpty else { resetGlobal(); return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true

            let base = auth.baseURL

            // Accumulators for the two project queries — merged on each arrival.
            var landedPublic: [Repository] = []
            var landedMember: [Repository] = []
            var landedTopics: [Repository] = []

            await withTaskGroup(of: GlobalChunk.self) { group in
                group.addTask {
                    .publicRepos((try? await self.api.searchProjects(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .memberRepos((try? await self.api.searchMemberProjects(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .topics((try? await self.api.searchRepositoriesByTopic(
                        topic: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .groups((try? await self.api.searchGroups(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .users((try? await self.api.searchUsers(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .files((try? await self.api.searchBlobsGlobal(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .commits((try? await self.api.searchCommitsGlobal(
                        query: query, baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .mrs((try? await self.api.searchMergeRequestsGlobal(
                        query: query, baseURL: base, token: token)) ?? [])
                }

                // Process each result the moment it arrives.
                for await chunk in group {
                    if Task.isCancelled { break }
                    withAnimation(spring) {
                        switch chunk {
                        case .publicRepos(let r):
                            landedPublic = r
                            applyProjectMerge(
                                public: landedPublic,
                                member: landedMember,
                                topics: landedTopics)

                        case .memberRepos(let r):
                            landedMember = r
                            applyProjectMerge(
                                public: landedPublic,
                                member: landedMember,
                                topics: landedTopics)

                        case .topics(let r):
                            landedTopics = r
                            applyProjectMerge(
                                public: landedPublic,
                                member: landedMember,
                                topics: landedTopics)

                        case .groups(let r):  groupResults  = r
                        case .users(let r):   userResults   = r
                        case .files(let r):   fileResults   = r
                        case .commits(let r): commitResults = r
                        case .mrs(let r):     mrResults     = r
                        }
                    }
                }
            }

            isSearching = false
        }
    }

    // MARK: - In-repo search

    /// Runs blob, commit, and MR searches concurrently within one project.
    /// Each section is published as soon as its own call completes.
    func searchRepo(query: String, projectID: Int) {
        guard !query.isEmpty else { resetRepo(); return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let token = auth.accessToken else { return }
            isSearching = true

            let base = auth.baseURL

            await withTaskGroup(of: RepoChunk.self) { group in
                group.addTask {
                    .blobs((try? await self.api.searchRepository(
                        projectID: projectID, query: query,
                        scope: "blobs", baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .commits((try? await self.api.searchRepoCommits(
                        projectID: projectID, query: query,
                        baseURL: base, token: token)) ?? [])
                }
                group.addTask {
                    .mrs((try? await self.api.searchRepoMergeRequests(
                        projectID: projectID, query: query,
                        baseURL: base, token: token)) ?? [])
                }

                for await chunk in group {
                    if Task.isCancelled { break }
                    withAnimation(spring) {
                        switch chunk {
                        case .blobs(let r):   repoBlobResults   = r
                        case .commits(let r): repoCommitResults = r
                        case .mrs(let r):     repoMRResults     = r
                        }
                    }
                }
            }

            isSearching = false
        }
    }

    // MARK: - Reset

    func reset() {
        searchTask?.cancel()
        resetGlobal()
        resetRepo()
        isSearching = false
        error = nil
    }

    private func resetGlobal() {
        projectResults    = []
        taggedRepoResults = []
        groupResults      = []
        userResults       = []
        fileResults       = []
        commitResults     = []
        mrResults         = []
    }

    private func resetRepo() {
        repoBlobResults   = []
        repoCommitResults = []
        repoMRResults     = []
    }

    // MARK: - Helpers

    /// Merges public + member repos (member first) and de-dupes topics against the combined set.
    /// Called every time any of the three project-related chunks lands so the UI reflects
    /// partial results immediately.
    private func applyProjectMerge(public publicRepos: [Repository],
                                   member memberRepos: [Repository],
                                   topics topicRepos: [Repository]) {
        var merged = memberRepos
        let mergedIDs = Set(merged.map(\.id))
        merged.append(contentsOf: publicRepos.filter { !mergedIDs.contains($0.id) })
        let allIDs = Set(merged.map(\.id))
        projectResults    = merged
        taggedRepoResults = topicRepos.filter { !allIDs.contains($0.id) }
    }
}
