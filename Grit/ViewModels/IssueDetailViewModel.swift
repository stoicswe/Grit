import Foundation

@MainActor
final class IssueDetailViewModel: ObservableObject {
    @Published var notes:                 [GitLabIssueNote] = []
    @Published var isSubscribed:          Bool = false
    @Published var isLoadingNotes:        Bool = false
    @Published var isPosting:             Bool = false
    @Published var isTogglingSubscription: Bool = false
    @Published var error:                 String?
    /// ID of the authenticated user — used to distinguish "my" bubbles from others'.
    @Published var currentUserID:         Int?

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Load

    func load(projectID: Int, issue: GitLabIssue) async {
        guard let token = auth.accessToken else { return }
        isLoadingNotes = true
        error = nil
        defer { isLoadingNotes = false }

        // Fetch notes, subscription status, and current user all in parallel
        async let notesTask  = api.fetchIssueNotes(
            projectID: projectID, issueIID: issue.iid,
            baseURL: auth.baseURL, token: token
        )
        async let detailTask = api.fetchIssue(
            projectID: projectID, issueIID: issue.iid,
            baseURL: auth.baseURL, token: token
        )
        async let userTask   = api.fetchCurrentUser(baseURL: auth.baseURL, token: token)

        do {
            let (fetched, detail, user) = try await (notesTask, detailTask, userTask)
            notes         = fetched
            isSubscribed  = detail.subscribed ?? false
            currentUserID = user.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Comment

    func addComment(projectID: Int, issueIID: Int, body: String) async {
        guard let token = auth.accessToken, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            let note = try await api.addIssueNote(
                projectID: projectID, issueIID: issueIID,
                body: body, baseURL: auth.baseURL, token: token
            )
            notes.append(note)
            // Auto-follow the issue when the user posts a comment
            if !isSubscribed {
                await silentSubscribe(projectID: projectID, issueIID: issueIID, token: token)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Subscribe / Unsubscribe

    func toggleSubscription(projectID: Int, issueIID: Int) async {
        guard let token = auth.accessToken else { return }
        isTogglingSubscription = true
        defer { isTogglingSubscription = false }
        let previous = isSubscribed
        isSubscribed.toggle() // optimistic
        do {
            if previous {
                try await api.unsubscribeFromIssue(
                    projectID: projectID, issueIID: issueIID,
                    baseURL: auth.baseURL, token: token
                )
            } else {
                try await api.subscribeToIssue(
                    projectID: projectID, issueIID: issueIID,
                    baseURL: auth.baseURL, token: token
                )
            }
        } catch {
            isSubscribed = previous  // rollback on failure
            self.error = error.localizedDescription
        }
    }

    // MARK: - Private helpers

    private func silentSubscribe(projectID: Int, issueIID: Int, token: String) async {
        do {
            try await api.subscribeToIssue(
                projectID: projectID, issueIID: issueIID,
                baseURL: auth.baseURL, token: token
            )
            isSubscribed = true
        } catch {
            // Non-fatal — commenting succeeded; just don't update subscription state
        }
    }
}
