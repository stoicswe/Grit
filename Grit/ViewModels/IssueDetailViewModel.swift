import Foundation

@MainActor
final class IssueDetailViewModel: ObservableObject {
    @Published var notes:                  [GitLabIssueNote] = []
    @Published var isSubscribed:           Bool = false
    @Published var isLoadingNotes:         Bool = false
    @Published var isPosting:             Bool = false
    @Published var isTogglingSubscription: Bool = false
    @Published var isTogglingState:        Bool = false
    /// Live open/closed state — updated optimistically and confirmed from the API response.
    @Published var isOpen:                 Bool = true
    @Published var error:                  String?
    /// ID of the authenticated user — used to distinguish "my" bubbles from others'.
    @Published var currentUserID:          Int?
    /// Whether the current user is allowed to close/reopen this issue.
    /// True when they are the author, an assignee, or a project member with Reporter (20+) access.
    @Published var canCloseIssue:          Bool = false

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Load

    func load(projectID: Int, issue: GitLabIssue) async {
        guard let token = auth.accessToken else { return }
        // Seed live state from the passed issue immediately so the button renders
        // correctly before the network fetch completes.
        isOpen = issue.isOpen
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
            isOpen        = detail.isOpen
            currentUserID = user.id

            // Determine close permission:
            // Author and assignees can always close their own issues.
            let isAuthor   = detail.author.id == user.id
            let isAssignee = detail.assignees.contains { $0.id == user.id }
            if isAuthor || isAssignee {
                canCloseIssue = true
            } else {
                // Fall back to project membership level (Reporter = 20, Developer = 30, …)
                let member = try? await api.fetchProjectMemberSelf(
                    projectID: projectID, userID: user.id,
                    baseURL: auth.baseURL, token: token
                )
                canCloseIssue = (member?.accessLevel ?? 0) >= 20
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Close / Reopen

    func toggleState(projectID: Int, issueIID: Int) async {
        guard let token = auth.accessToken else { return }
        isTogglingState = true
        defer { isTogglingState = false }
        let previous = isOpen
        isOpen.toggle()  // optimistic
        do {
            let updated = try await api.setIssueState(
                projectID: projectID,
                issueIID:  issueIID,
                open:      !previous,   // !previous because we're toggling away from it
                baseURL:   auth.baseURL,
                token:     token
            )
            isOpen = updated.isOpen  // confirm with server's actual state
        } catch {
            isOpen = previous  // rollback
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
