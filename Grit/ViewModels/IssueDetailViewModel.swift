import Foundation

@MainActor
final class IssueDetailViewModel: ObservableObject {
    @Published var notes:                  [GitLabIssueNote] = []
    /// Linked task-type child issues — fetched from the issue links endpoint.
    @Published var childTasks:             [GitLabIssue]     = []
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
    /// Live copy of the issue description — updated when the user toggles tasks.
    @Published var liveDescription: String?
    @Published var isUpdatingDescription: Bool = false
    /// IDs of child tasks currently being opened/closed — drives per-row busy state.
    @Published var togglingTaskIDs: Set<Int> = []

    // MARK: Votes
    @Published var upvotes:        Int  = 0
    @Published var downvotes:      Int  = 0
    /// Award emoji ID for the current user's 👍 (nil if not voted).
    @Published var myUpvoteID:     Int? = nil
    /// Award emoji ID for the current user's 👎 (nil if not voted).
    @Published var myDownvoteID:   Int? = nil
    @Published var isVoting:       Bool = false

    // MARK: Labels
    /// Live label details shown in the card — updated after a successful save.
    @Published var liveLabelDetails:  [IssueLabelDetail] = []
    /// All labels available in the project — loaded once for the picker.
    @Published var availableLabels:   [ProjectLabel]     = []
    @Published var isSavingLabels:    Bool = false

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

        // Fetch notes, detail, current user, child tasks, emojis, and project labels all in parallel
        async let notesTask       = api.fetchIssueNotes(
            projectID: projectID, issueIID: issue.iid,
            baseURL: auth.baseURL, token: token
        )
        async let detailTask      = api.fetchIssue(
            projectID: projectID, issueIID: issue.iid,
            baseURL: auth.baseURL, token: token
        )
        async let userTask        = api.fetchCurrentUser(baseURL: auth.baseURL, token: token)
        async let childTasksTask  = api.fetchIssueLinkedTasks(
            projectID: projectID, issueIID: issue.iid,
            baseURL: auth.baseURL, token: token
        )
        async let emojisTask      = api.fetchAwardEmojis(
            projectID: projectID, issueIID: issue.iid,
            baseURL: auth.baseURL, token: token
        )
        async let labelsTask      = api.fetchProjectLabels(
            projectID: projectID,
            baseURL:   auth.baseURL,
            token:     token
        )

        do {
            let (fetched, detail, user) = try await (notesTask, detailTask, userTask)
            notes            = fetched
            isSubscribed     = detail.subscribed ?? false
            isOpen           = detail.isOpen
            liveDescription  = detail.description
            liveLabelDetails = detail.labelDetails
            currentUserID    = user.id
            childTasks       = (try? await childTasksTask) ?? []

            // Seed vote counts and current-user emoji IDs
            upvotes   = detail.upvotes
            downvotes = detail.downvotes
            let emojis = (try? await emojisTask) ?? []
            myUpvoteID   = emojis.first(where: { $0.name == "thumbsup"   && $0.user.id == user.id })?.id
            myDownvoteID = emojis.first(where: { $0.name == "thumbsdown" && $0.user.id == user.id })?.id

            availableLabels = (try? await labelsTask) ?? []

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

    // MARK: - Task Checklist

    /// Parses Markdown task list items from the live description.
    func parsedTasks() -> [IssueTask] {
        guard let desc = liveDescription else { return [] }
        return IssueTask.parse(from: desc)
    }

    func toggleTask(at index: Int, projectID: Int, issueIID: Int) async {
        guard var desc = liveDescription else { return }
        desc = IssueTask.toggle(in: desc, at: index)
        liveDescription = desc   // optimistic
        await updateDescription(desc, projectID: projectID, issueIID: issueIID)
    }

    /// Creates a real GitLab task-type issue, links it to the parent issue,
    /// auto-assigns it to the current user, and appends it to `childTasks`.
    func createChildTask(_ title: String, projectID: Int, issueIID: Int) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let token = auth.accessToken else { return }
        isUpdatingDescription = true   // reuse the progress indicator
        defer { isUpdatingDescription = false }
        do {
            let assigneeIDs: [Int] = currentUserID.map { [$0] } ?? []
            let task = try await api.createIssue(
                projectID:   projectID,
                title:       trimmed,
                description: nil,
                assigneeIDs: assigneeIDs,
                labels:      [],
                issueType:   "task",
                baseURL:     auth.baseURL,
                token:       token
            )
            try await api.createIssueLink(
                projectID:       projectID,
                issueIID:        issueIID,
                targetProjectID: task.projectID,
                targetIssueIID:  task.iid,
                baseURL:         auth.baseURL,
                token:           token
            )
            childTasks.append(task)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Closes or reopens a child task issue by tapping its checkbox.
    /// Updates `childTasks` in-place with the confirmed server state.
    func toggleChildTaskState(task: GitLabIssue) async {
        guard let token = auth.accessToken else { return }
        togglingTaskIDs.insert(task.id)
        defer { togglingTaskIDs.remove(task.id) }
        do {
            let updated = try await api.setIssueState(
                projectID: task.projectID,
                issueIID:  task.iid,
                open:      !task.isOpen,   // !isOpen → close; isOpen → reopen
                baseURL:   auth.baseURL,
                token:     token
            )
            if let idx = childTasks.firstIndex(of: task) {
                childTasks[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Votes

    /// Toggles the thumbsup award emoji. If already voted, removes it; otherwise adds it.
    /// Mutually exclusive with downvote — adding an upvote also removes any existing downvote.
    func toggleUpvote(projectID: Int, issueIID: Int) async {
        guard let token = auth.accessToken else { return }
        isVoting = true
        defer { isVoting = false }
        do {
            if let id = myUpvoteID {
                // Remove existing upvote
                try await api.deleteAwardEmoji(projectID: projectID, issueIID: issueIID,
                                               awardID: id, baseURL: auth.baseURL, token: token)
                myUpvoteID = nil
                upvotes = max(0, upvotes - 1)
            } else {
                // Remove any opposing downvote first
                if let did = myDownvoteID {
                    try await api.deleteAwardEmoji(projectID: projectID, issueIID: issueIID,
                                                   awardID: did, baseURL: auth.baseURL, token: token)
                    myDownvoteID = nil
                    downvotes = max(0, downvotes - 1)
                }
                let emoji = try await api.addAwardEmoji(projectID: projectID, issueIID: issueIID,
                                                        name: "thumbsup", baseURL: auth.baseURL, token: token)
                myUpvoteID = emoji.id
                upvotes += 1
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Toggles the thumbsdown award emoji. Mutually exclusive with upvote.
    func toggleDownvote(projectID: Int, issueIID: Int) async {
        guard let token = auth.accessToken else { return }
        isVoting = true
        defer { isVoting = false }
        do {
            if let id = myDownvoteID {
                try await api.deleteAwardEmoji(projectID: projectID, issueIID: issueIID,
                                               awardID: id, baseURL: auth.baseURL, token: token)
                myDownvoteID = nil
                downvotes = max(0, downvotes - 1)
            } else {
                if let uid = myUpvoteID {
                    try await api.deleteAwardEmoji(projectID: projectID, issueIID: issueIID,
                                                   awardID: uid, baseURL: auth.baseURL, token: token)
                    myUpvoteID = nil
                    upvotes = max(0, upvotes - 1)
                }
                let emoji = try await api.addAwardEmoji(projectID: projectID, issueIID: issueIID,
                                                        name: "thumbsdown", baseURL: auth.baseURL, token: token)
                myDownvoteID = emoji.id
                downvotes += 1
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Save Labels

    func saveLabels(projectID: Int, issueIID: Int, labelNames: [String]) async {
        guard let token = auth.accessToken else { return }
        isSavingLabels = true
        defer { isSavingLabels = false }
        do {
            let updated = try await api.updateIssueLabels(
                projectID: projectID,
                issueIID:  issueIID,
                labels:    labelNames,
                baseURL:   auth.baseURL,
                token:     token
            )
            liveLabelDetails = updated.labelDetails
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Save Description (public surface)

    func saveDescription(_ text: String, projectID: Int, issueIID: Int) async {
        await updateDescription(text, projectID: projectID, issueIID: issueIID)
    }

    private func updateDescription(_ desc: String, projectID: Int, issueIID: Int) async {
        guard let token = auth.accessToken else { return }
        isUpdatingDescription = true
        defer { isUpdatingDescription = false }
        do {
            let updated = try await api.updateIssueDescription(
                projectID:   projectID,
                issueIID:    issueIID,
                description: desc,
                baseURL:     auth.baseURL,
                token:       token
            )
            liveDescription = updated.description
        } catch {
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
