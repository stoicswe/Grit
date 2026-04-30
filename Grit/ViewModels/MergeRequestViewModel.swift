import Foundation
import SwiftUI

// MARK: - Retry / error utilities (file-private)

/// Returns `true` for errors worth retrying: transient network conditions and
/// server-side 5xx responses.  Auth (401/403), client (4xx), and structural
/// errors are not retryable — they need a different recovery path.
private func isMRRetryable(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .timedOut, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .dataNotAllowed:
            return true
        default:
            return false
        }
    }
    if let apiError = error as? GitLabAPIService.APIError,
       case .httpError(let code) = apiError {
        return (500...599).contains(code)
    }
    return false
}

/// Returns `true` when the error is specifically an HTTP 404.
private func isMRNotFound(_ error: Error) -> Bool {
    guard let apiError = error as? GitLabAPIService.APIError,
          case .httpError(404) = apiError else { return false }
    return true
}

/// Returns `true` when the error is specifically an HTTP 405.
private func isMRMethodNotAllowed(_ error: Error) -> Bool {
    guard let apiError = error as? GitLabAPIService.APIError,
          case .httpError(405) = apiError else { return false }
    return true
}

/// Retries `operation` up to `maxAttempts` times on transient errors only,
/// with exponential back-off starting at `initialDelay` seconds (capped at 8 s).
/// Non-retryable errors are re-thrown immediately on first failure.
private func withMRRetry<T: Sendable>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 0.4,
    _ operation: @Sendable () async throws -> T
) async throws -> T {
    var delay = initialDelay
    for attempt in 1...max(1, maxAttempts) {
        do {
            return try await operation()
        } catch {
            // Re-throw immediately if the error is not retryable or we've
            // exhausted all allowed attempts.
            guard attempt < maxAttempts, isMRRetryable(error) else { throw error }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 8)
        }
    }
    // Unreachable — the loop always returns or throws before reaching here.
    preconditionFailure("withMRRetry exhausted without returning or throwing")
}

/// Maps a low-level error to a user-friendly message for the given resource context.
private func mrFriendlyError(_ error: Error, context: String) -> String {
    if let apiError = error as? GitLabAPIService.APIError {
        switch apiError {
        case .httpError(404):
            return "This \(context) could not be found — it may have been deleted or the project moved."
        case .httpError(403):
            return "You don't have permission to access this \(context)."
        case .httpError(405):
            return "This action isn't available for the \(context) in its current state."
        case .httpError(409):
            return "A conflict occurred — the \(context) state may have changed. Try refreshing."
        case .httpError(422):
            return "The \(context) cannot be processed right now. Check for conflicts or unresolved threads."
        case .httpError(let code) where (500...599).contains(code):
            return "GitLab returned a server error (HTTP \(code)). Please try again shortly."
        default:
            break
        }
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return "No internet connection. Please check your network and try again."
        case .timedOut:
            return "The request timed out. Please try again."
        default:
            break
        }
    }
    return error.localizedDescription
}

// MARK: - View Model

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

    // Pipelines
    @Published var mrPipelines:       [Pipeline] = []
    @Published var isPipelinesLoading = false

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
            mergeRequests = try await withMRRetry(maxAttempts: 3) {
                try await self.api.fetchMergeRequests(
                    projectID: projectID,
                    state:     self.filterState,
                    baseURL:   self.auth.baseURL,
                    token:     token
                )
            }
        } catch {
            self.error = mrFriendlyError(error, context: "merge request list")
        }
    }

    // MARK: - Detail

    func loadMergeRequestDetail(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let baseURL = auth.baseURL

        // ── All three fetches run in parallel ────────────────────────────
        // The MR itself is mandatory; notes and current-user are non-fatal.
        async let mrFetch: MergeRequest = withMRRetry(maxAttempts: 3) {
            try await self.api.fetchMergeRequest(
                projectID: projectID, mrIID: mrIID,
                baseURL: baseURL, token: token
            )
        }
        async let notesFetch: [MRNote] = withMRRetry(maxAttempts: 3) {
            try await self.api.fetchMRNotes(
                projectID: projectID, mrIID: mrIID,
                baseURL: baseURL, token: token
            )
        }
        async let userFetch = self.api.fetchCurrentUser(baseURL: baseURL, token: token)

        do {
            // Await the MR — if this fails the whole load fails with a clear message.
            let mr = try await mrFetch
            selectedMR = mr

            // Notes and user are best-effort; failures degrade gracefully.
            notes         = (try? await notesFetch) ?? []
            currentUserID = (try? await userFetch)?.id
        } catch {
            self.error = mrFriendlyError(error, context: "merge request")
        }
    }

    // MARK: - Permissions

    /// Fetches approve capability and merge capability.
    /// Fully silent — both flags stay `false` on any failure so buttons dim
    /// rather than surfacing an error in an unrelated part of the UI.
    func loadPermissions(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoadingPerms = true
        defer { isLoadingPerms = false }

        let baseURL = auth.baseURL

        // Approval capability — retry transient, silent on everything else
        let approvals = try? await withMRRetry(maxAttempts: 2) {
            try await self.api.fetchMRApprovals(
                projectID: projectID, mrIID: mrIID,
                baseURL: baseURL, token: token
            )
        }
        if let approvals {
            userCanApprove  = approvals.userCanApprove
            userHasApproved = approvals.userHasApproved
        }

        // Merge capability — Developer (30+) access level required
        if let user = try? await api.fetchCurrentUser(baseURL: baseURL, token: token) {
            let member = try? await withMRRetry(maxAttempts: 2) {
                try await self.api.fetchProjectMemberSelf(
                    projectID: projectID, userID: user.id,
                    baseURL: baseURL, token: token
                )
            }
            if let member {
                userCanMerge = member.accessLevel >= 30
            }
        }
    }

    // MARK: - Diff

    func loadDiffs(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isDiffLoading = true
        diffError = nil
        defer { isDiffLoading = false }

        let baseURL = auth.baseURL

        do {
            let raw = try await withMRRetry(maxAttempts: 3) {
                try await self.api.fetchMRDiffs(
                    projectID: projectID, mrIID: mrIID,
                    baseURL: baseURL, token: token
                )
            }
            fileDiffs = await Task.detached(priority: .userInitiated) {
                DiffParser.build(raw)
            }.value
        } catch {
            // A 404 here is a well-known GitLab behaviour: diffs are purged
            // for old or oversized MRs.  Surface a specific inline message
            // inside the diff section rather than a full-screen error banner.
            if isMRNotFound(error) {
                diffError = "Diff data is unavailable — GitLab may have purged it for this merge request."
            } else {
                diffError = mrFriendlyError(error, context: "diff")
            }
        }
    }

    // MARK: - Pipelines

    /// Fetches all pipelines that have been triggered for this merge request,
    /// newest first.  Silently swallows errors — the section just stays hidden
    /// when the project has no CI or the user lacks pipeline read access.
    func loadMRPipelines(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isPipelinesLoading = true
        defer { isPipelinesLoading = false }
        mrPipelines = (try? await api.fetchMRPipelines(
            projectID: projectID, mrIID: mrIID,
            baseURL: auth.baseURL, token: token
        )) ?? []
    }

    // MARK: - Actions

    func approve(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isApproving = true
        defer { isApproving = false }

        let baseURL = auth.baseURL

        do {
            // Approve is safe to retry — GitLab is idempotent for repeated approvals
            // on the same MR by the same user.
            try await withMRRetry(maxAttempts: 2) {
                try await self.api.approveMergeRequest(
                    projectID: projectID, mrIID: mrIID,
                    baseURL: baseURL, token: token
                )
            }
            userHasApproved = true
            userCanApprove  = false
        } catch {
            self.error = mrFriendlyError(error, context: "merge request")
        }
    }

    func merge(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isMerging = true
        defer { isMerging = false }

        let baseURL = auth.baseURL

        do {
            // Merge is destructive — one attempt only to avoid double-merge.
            try await api.mergeMergeRequest(
                projectID: projectID, mrIID: mrIID,
                baseURL: baseURL, token: token
            )
            updateLocalMergeState()
        } catch {
            if isMRMethodNotAllowed(error) {
                // HTTP 405 most likely means the MR was merged concurrently —
                // reflect the merged state locally rather than showing an error.
                updateLocalMergeState()
            } else {
                self.error = mrFriendlyError(error, context: "merge request")
            }
        }
    }

    func addComment(projectID: Int, mrIID: Int, body: String) async {
        guard let token = auth.accessToken, !body.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }

        let baseURL = auth.baseURL

        do {
            // Retry once on transient — comment POST is safe to retry if the
            // first attempt failed before reaching the server.
            let note = try await withMRRetry(maxAttempts: 2) {
                try await self.api.addMRComment(
                    projectID: projectID, mrIID: mrIID,
                    body: body, baseURL: baseURL, token: token
                )
            }
            notes.append(note)
        } catch {
            self.error = mrFriendlyError(error, context: "merge request")
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

    // MARK: - Private helpers

    /// Updates the local MR state to `.merged` without a full network reload.
    private func updateLocalMergeState() {
        guard let current = selectedMR else { return }
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
            diffRefs: current.diffRefs, labelDetails: current.labelDetails,
            draft: current.draft, hasConflicts: current.hasConflicts,
            mergeStatus: "merged",
            projectID: current.projectID,
            references: current.references,
            headPipeline: current.headPipeline
        )
    }
}
