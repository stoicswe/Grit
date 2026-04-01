import Foundation
import SwiftUI

@MainActor
final class MergeRequestViewModel: ObservableObject {
    @Published var mergeRequests:   [MergeRequest]   = []
    @Published var selectedMR:      MergeRequest?
    @Published var notes:           [MRNote]         = []
    @Published var isLoading        = false
    @Published var isPosting        = false
    @Published var isApproving      = false
    @Published var isMerging        = false
    @Published var error:           String?
    @Published var filterState:     String           = "opened"
    @Published var aiReview:        String?
    @Published var isAILoading      = false

    // Diff
    @Published var fileDiffs:       [ParsedFileDiff] = []
    @Published var isDiffLoading    = false
    @Published var diffError:       String?

    // Permissions
    @Published var userCanApprove   = false
    @Published var userHasApproved  = false
    @Published var userCanMerge     = false
    @Published var isLoadingPerms   = false

    /// ID of the authenticated user — used to colour own bubbles differently.
    @Published var currentUserID:   Int?

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared
    private let ai   = AIAssistantService.shared

    // MARK: - List

    func loadMergeRequests(projectID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            mergeRequests = try await api.fetchMergeRequests(
                projectID: projectID,
                state: filterState,
                baseURL: auth.baseURL,
                token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Detail (notes + current user)

    func loadMergeRequestDetail(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let mrTask    = api.fetchMergeRequest(
                projectID: projectID, mrIID: mrIID,
                baseURL: auth.baseURL, token: token
            )
            async let notesTask = api.fetchMRNotes(
                projectID: projectID, mrIID: mrIID,
                baseURL: auth.baseURL, token: token
            )
            async let userTask  = api.fetchCurrentUser(
                baseURL: auth.baseURL, token: token
            )
            let (mr, fetched, user) = try await (mrTask, notesTask, userTask)
            selectedMR    = mr
            // Keep system notes so we can display them as event pills
            notes         = fetched
            currentUserID = user.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Permissions

    /// Fetches approve capability from the approvals endpoint and merge
    /// capability from the project membership. Silent failure — if either
    /// endpoint is unavailable both flags stay `false` (buttons stay dimmed).
    func loadPermissions(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoadingPerms = true
        defer { isLoadingPerms = false }

        // Approval capability
        if let approvals = try? await api.fetchMRApprovals(
            projectID: projectID, mrIID: mrIID,
            baseURL: auth.baseURL, token: token
        ) {
            userCanApprove  = approvals.userCanApprove
            userHasApproved = approvals.userHasApproved
        }

        // Merge capability — Developer (30) or higher in most projects
        if let user   = try? await api.fetchCurrentUser(
            baseURL: auth.baseURL, token: token
        ),
           let member = try? await api.fetchProjectMemberSelf(
               projectID: projectID,
               userID: user.id,
               baseURL: auth.baseURL,
               token: token
           ) {
            userCanMerge = member.accessLevel >= 30
        }
    }

    // MARK: - Diff

    func loadDiffs(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isDiffLoading = true
        diffError = nil
        defer { isDiffLoading = false }
        do {
            let raw = try await api.fetchMRDiffs(
                projectID: projectID, mrIID: mrIID,
                baseURL: auth.baseURL, token: token
            )
            fileDiffs = await Task.detached(priority: .userInitiated) {
                DiffParser.build(raw)
            }.value
        } catch {
            diffError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func approve(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isApproving = true
        defer { isApproving = false }
        do {
            try await api.approveMergeRequest(
                projectID: projectID, mrIID: mrIID,
                baseURL: auth.baseURL, token: token
            )
            userHasApproved = true
            userCanApprove  = false   // can't approve twice
        } catch {
            self.error = error.localizedDescription
        }
    }

    func merge(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isMerging = true
        defer { isMerging = false }
        do {
            try await api.mergeMergeRequest(
                projectID: projectID, mrIID: mrIID,
                baseURL: auth.baseURL, token: token
            )
            // Reflect merged state locally without a full reload
            if let current = selectedMR {
                selectedMR = MergeRequest(
                    id: current.id, iid: current.iid,
                    title: current.title, description: current.description,
                    state: .merged,
                    author: current.author, assignee: current.assignee,
                    reviewers: current.reviewers,
                    sourceBranch: current.sourceBranch,
                    targetBranch: current.targetBranch,
                    createdAt: current.createdAt, updatedAt: current.updatedAt,
                    mergedAt: Date(), webURL: current.webURL,
                    upvotes: current.upvotes, downvotes: current.downvotes,
                    changesCount: current.changesCount,
                    diffRefs: current.diffRefs, labels: current.labels,
                    draft: current.draft, hasConflicts: current.hasConflicts,
                    mergeStatus: "merged",
                    projectID: current.projectID,
                    references: current.references
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addComment(projectID: Int, mrIID: Int, body: String) async {
        guard let token = auth.accessToken, !body.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            let note = try await api.addMRComment(
                projectID: projectID, mrIID: mrIID,
                body: body, baseURL: auth.baseURL, token: token
            )
            notes.append(note)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - AI

    func requestAIReview() async {
        guard let mr = selectedMR else { return }
        isAILoading = true
        defer { isAILoading = false }
        do {
            aiReview = try await ai.reviewMergeRequest(
                title: mr.title,
                description: mr.description ?? "",
                diff: "See merge request \(mr.iid)"
            )
        } catch {
            aiReview = "AI review unavailable: \(error.localizedDescription)"
        }
    }
}
