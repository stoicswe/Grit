import AppIntents
import NaturalLanguage
import SwiftUI
import Translation
import UIKit

/// Wrapper used as a NavigationLink value for child task issues inside IssueDetailView.
/// Using a distinct type avoids clashing with InboxView's `navigationDestination(for: GitLabIssue.self)`.
struct ChildTaskNavigation: Hashable {
    let issue: GitLabIssue
}

struct IssueDetailView: View {
    let issue:     GitLabIssue
    let projectID: Int

    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var composerState: TabBarComposerState
    @StateObject private var viewModel = IssueDetailViewModel()
    @ObservedObject private var aiService = AIAssistantService.shared
    @State private var showComposer  = false
    @State private var replyToNote:  GitLabIssueNote? = nil
    @State private var profileForUserID: Int? = nil
    @State private var profileUsername: String = ""
    @State private var profileAvatarURL: String? = nil
    @State private var showProfile = false
    @State private var newTaskText = ""

    // Description editing
    @State private var isEditingDescription = false
    @State private var editDescriptionText  = ""

    // Label picker
    @State private var showLabelPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let err = viewModel.error {
                    ErrorBanner(message: err) { viewModel.error = nil }
                        .padding(.horizontal)
                }

                headerCard
                statsRow
                labelsCard
                assigneesCard
                descriptionCard
                tasksCard
                chatSection
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .navigationTitle("#\(issue.iid)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    if viewModel.canCloseIssue {
                        stateToggleButton
                    }
                    followButton
                }
            }
        }
        .navigationDestination(for: ChildTaskNavigation.self) { nav in
            IssueDetailView(issue: nav.issue, projectID: nav.issue.projectID)
                .environmentObject(settingsStore)
                .environmentObject(composerState)
        }
        .task { await viewModel.load(projectID: projectID, issue: issue) }
        .onAppear  { composerState.register  { showComposer = true } }
        .onDisappear { composerState.unregister() }
        // On-screen awareness: lets Siri / Apple Intelligence know which
        // issue the user is currently viewing so it can act on it contextually.
        .userActivity("com.stoicswe.grit.viewingIssue") { activity in
            activity.title = issue.title
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.targetContentIdentifier = "issue-\(issue.id)"
            let entity = IssueEntity(from: issue)
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
        .overlay {
            if showProfile, let uid = profileForUserID {
                UserProfileOverlay(
                    userID: uid,
                    username: profileUsername,
                    avatarURL: profileAvatarURL,
                    isPresented: $showProfile
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showComposer, onDismiss: { replyToNote = nil }) {
            CommentComposerSheet(
                replyTo: replyToNote,
                isPosting: viewModel.isPosting
            ) { body in
                Task {
                    await viewModel.addComment(
                        projectID: projectID,
                        issueIID: issue.iid,
                        body: body
                    )
                    showComposer = false
                }
            }
        }
    }

    // MARK: - State Toggle Button (Close / Reopen)

    private var stateToggleButton: some View {
        Button {
            Task { await viewModel.toggleState(projectID: projectID, issueIID: issue.iid) }
        } label: {
            if viewModel.isTogglingState {
                ProgressView().scaleEffect(0.8)
            } else if viewModel.isOpen {
                Label("Close Issue", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            } else {
                Label("Reopen Issue", systemImage: "arrow.counterclockwise.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            }
        }
        .disabled(viewModel.isTogglingState)
    }

    // MARK: - Follow Button

    private var followButton: some View {
        Button {
            Task { await viewModel.toggleSubscription(projectID: projectID, issueIID: issue.iid) }
        } label: {
            if viewModel.isTogglingSubscription {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: viewModel.isSubscribed ? "bell.fill" : "bell")
                    .symbolEffect(.bounce, value: viewModel.isSubscribed)
            }
        }
        .foregroundStyle(.tint)
        .disabled(viewModel.isTogglingSubscription)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    issueStateBadge
                    Spacer()
                    Text("#\(issue.iid)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(issue.title)
                    .font(.system(size: 18, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(spacing: 8) {
                    AvatarView(urlString: issue.author.avatarURL,
                               name: issue.author.name, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.author.name)
                            .font(.system(size: 13, weight: .medium))
                        Text("@\(issue.author.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Opened")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.3)
                        Text(issue.createdAt.relativeFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let closed = issue.closedAt {
                            Text("Closed \(closed.relativeFormatted)")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var issueStateBadge: some View {
        // Use viewModel.isOpen (live) rather than issue.isOpen (immutable snapshot) so
        // the badge updates immediately when the user closes or reopens from this view.
        let open = viewModel.isOpen
        return HStack(spacing: 5) {
            Circle()
                .fill(open ? Color.green : Color.purple)
                .frame(width: 8, height: 8)
            Text(open ? "Open" : "Closed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(open ? .green : .purple)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((open ? Color.green : Color.purple).opacity(0.12), in: Capsule())
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            // ── Upvote ────────────────────────────────────────────────────
            Button {
                Task { await viewModel.toggleUpvote(projectID: projectID, issueIID: issue.iid) }
            } label: {
                VStack(spacing: 4) {
                    if viewModel.isVoting {
                        ProgressView().scaleEffect(0.7).frame(height: 18)
                    } else {
                        Image(systemName: viewModel.myUpvoteID != nil
                              ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(viewModel.myUpvoteID != nil ? Color.green : .secondary)
                    }
                    Text("\(viewModel.upvotes)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Upvotes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            viewModel.myUpvoteID != nil ? Color.green.opacity(0.4) : Color.white.opacity(0.12),
                            lineWidth: viewModel.myUpvoteID != nil ? 1 : 0.5
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isVoting)

            // ── Downvote ──────────────────────────────────────────────────
            Button {
                Task { await viewModel.toggleDownvote(projectID: projectID, issueIID: issue.iid) }
            } label: {
                VStack(spacing: 4) {
                    if viewModel.isVoting {
                        ProgressView().scaleEffect(0.7).frame(height: 18)
                    } else {
                        Image(systemName: viewModel.myDownvoteID != nil
                              ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(viewModel.myDownvoteID != nil ? Color.red : .secondary)
                    }
                    Text("\(viewModel.downvotes)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Downvotes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            viewModel.myDownvoteID != nil ? Color.red.opacity(0.4) : Color.white.opacity(0.12),
                            lineWidth: viewModel.myDownvoteID != nil ? 1 : 0.5
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isVoting)

            // ── Comments (non-interactive) ────────────────────────────────
            StatBadge(
                title: "Comments",
                value: "\(viewModel.notes.filter { !$0.system }.count)",
                icon: "bubble.left.fill"
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Labels

    @ViewBuilder
    private var labelsCard: some View {
        let labels = viewModel.liveLabelDetails
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GlassSectionHeader(
                        title: "Labels",
                        trailing: labels.isEmpty ? nil : "\(labels.count)"
                    )
                    if viewModel.isSavingLabels {
                        ProgressView().scaleEffect(0.7).padding(.leading, 4)
                    } else if viewModel.canCloseIssue {
                        Button { showLabelPicker = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if labels.isEmpty {
                    Button { showLabelPicker = true } label: {
                        Label("Add labels", systemImage: "tag")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canCloseIssue)
                } else {
                    let fallback = SettingsStore.shared.accentColor ?? Color.accentColor
                    FlowLayout(spacing: 6) {
                        ForEach(labels) { detail in
                            let c = detail.swiftUIColor(fallback: fallback)
                            Text(detail.name)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(c.opacity(0.15), in: Capsule())
                                .foregroundStyle(c)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showLabelPicker) {
            IssueEditLabelSheet(
                selectedNames: Set(labels.map(\.name)),
                available:     viewModel.availableLabels
            ) { chosen in
                Task {
                    await viewModel.saveLabels(
                        projectID: projectID,
                        issueIID:  issue.iid,
                        labelNames: Array(chosen)
                    )
                }
            }
        }
    }

    // MARK: - Assignees

    @ViewBuilder
    private var assigneesCard: some View {
        if !issue.assignees.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    GlassSectionHeader(title: "Assignees", trailing: "\(issue.assignees.count)")
                    ForEach(issue.assignees, id: \.id) { assignee in
                        HStack(spacing: 10) {
                            AvatarView(urlString: assignee.avatarURL,
                                       name: assignee.name, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assignee.name)
                                    .font(.system(size: 14, weight: .medium))
                                Text("@\(assignee.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Description

    @ViewBuilder
    private var descriptionCard: some View {
        let liveDesc = viewModel.liveDescription ?? issue.description ?? ""
        let hasDesc  = !liveDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasDesc || viewModel.canCloseIssue {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        GlassSectionHeader(title: "Description")
                        if viewModel.isUpdatingDescription {
                            ProgressView().scaleEffect(0.7).padding(.leading, 4)
                        } else if viewModel.canCloseIssue && !isEditingDescription {
                            Button {
                                editDescriptionText = liveDesc
                                isEditingDescription = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isEditingDescription {
                        TextEditor(text: $editDescriptionText)
                            .font(.system(size: 14))
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.ultraThinMaterial,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )

                        HStack(spacing: 10) {
                            Button("Cancel") {
                                isEditingDescription = false
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                let text = editDescriptionText
                                isEditingDescription = false
                                Task {
                                    await viewModel.saveDescription(
                                        text, projectID: projectID, issueIID: issue.iid)
                                }
                            } label: {
                                Text("Save")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if hasDesc {
                        MarkdownRendererView(source: liveDesc)
                    } else {
                        Button {
                            editDescriptionText = ""
                            isEditingDescription = true
                        } label: {
                            Text("Add a description…")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Tasks Card

    @ViewBuilder
    private var tasksCard: some View {
        let markdownTasks = viewModel.parsedTasks()
        let linkedTasks   = viewModel.childTasks
        let hasContent    = !markdownTasks.isEmpty || !linkedTasks.isEmpty || viewModel.canCloseIssue

        if hasContent {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        GlassSectionHeader(
                            title: "Tasks",
                            trailing: linkedTasks.isEmpty && markdownTasks.isEmpty ? nil :
                                "\(linkedTasks.filter { !$0.isOpen }.count + markdownTasks.filter(\.isDone).count)/\(linkedTasks.count + markdownTasks.count)"
                        )
                        if viewModel.isUpdatingDescription {
                            ProgressView().scaleEffect(0.7).padding(.leading, 4)
                        }
                    }

                    // ── Linked task-type child issues (navigable) ──────────
                    if !linkedTasks.isEmpty {
                        ForEach(linkedTasks) { task in
                            let isToggling = viewModel.togglingTaskIDs.contains(task.id)
                            HStack(spacing: 10) {
                                // Checkbox — closes / reopens the task issue
                                Button {
                                    Task { await viewModel.toggleChildTaskState(task: task) }
                                } label: {
                                    Group {
                                        if isToggling {
                                            ProgressView()
                                                .frame(width: 19, height: 19)
                                        } else {
                                            Image(systemName: task.isOpen
                                                  ? "square" : "checkmark.square.fill")
                                                .foregroundStyle(task.isOpen ? Color.secondary : Color.green)
                                                .font(.system(size: 19))
                                        }
                                    }
                                    .contentShape(Rectangle().inset(by: -6))
                                }
                                .buttonStyle(.plain)
                                .disabled(isToggling)

                                // Title + project path + chevron — navigates to task detail
                                NavigationLink(value: ChildTaskNavigation(issue: task)) {
                                    HStack(spacing: 0) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(.system(size: 14))
                                                .foregroundStyle(task.isOpen ? .primary : .secondary)
                                                .strikethrough(!task.isOpen, color: .secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if let path = task.projectPath {
                                                Text(path)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }

                        if !markdownTasks.isEmpty {
                            Divider().opacity(0.3)
                        }
                    }

                    // ── Markdown checklist items (toggleable, not separate issues) ──
                    if !markdownTasks.isEmpty {
                        let progress = Double(markdownTasks.filter(\.isDone).count) / Double(markdownTasks.count)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 4)
                                Capsule().fill(Color.green)
                                    .frame(width: geo.size.width * progress, height: 4)
                                    .animation(.easeInOut(duration: 0.3), value: progress)
                            }
                        }
                        .frame(height: 4)

                        ForEach(Array(markdownTasks.enumerated()), id: \.element.id) { idx, task in
                            HStack(spacing: 10) {
                                Button {
                                    Task {
                                        await viewModel.toggleTask(
                                            at: idx, projectID: projectID, issueIID: issue.iid)
                                    }
                                } label: {
                                    Image(systemName: task.isDone
                                          ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(task.isDone ? .green : .secondary)
                                        .font(.system(size: 19))
                                        .contentShape(Rectangle().inset(by: -6))
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.canCloseIssue)

                                Text(task.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(task.isDone ? .secondary : .primary)
                                    .strikethrough(task.isDone, color: .secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if linkedTasks.isEmpty && markdownTasks.isEmpty {
                        Label("No tasks yet", systemImage: "checkmark.square")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // ── Add markdown task (users who can edit) ─────────────
                    if viewModel.canCloseIssue {
                        Divider().opacity(0.4)
                        HStack(spacing: 8) {
                            Image(systemName: "plus.square")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 15))
                            TextField("Add a task…", text: $newTaskText)
                                .font(.system(size: 14))
                                .onSubmit {
                                    let text = newTaskText
                                    newTaskText = ""
                                    Task {
                                        await viewModel.createChildTask(
                                            text, projectID: projectID, issueIID: issue.iid)
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Chat Section

    @ViewBuilder
    private var chatSection: some View {
        let notes = viewModel.notes

        if viewModel.isLoadingNotes && notes.isEmpty {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Loading discussion…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

        } else if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Section header
                HStack {
                    Text("Discussion")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    let count = notes.filter { !$0.system }.count
                    if count > 0 {
                        Text("\(count) comment\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Notes
                VStack(spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        let prev      = index > 0 ? notes[index - 1] : nil
                        let isGrouped = !note.system
                                        && prev?.system == false
                                        && prev?.author.id == note.author.id
                        let isMine    = note.author.id == viewModel.currentUserID

                        if note.system {
                            SystemEventPill(note: note)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 20)
                        } else {
                            IssueChatBubble(
                                note:          note,
                                isCurrentUser: isMine,
                                isGrouped:     isGrouped,
                                onReply: {
                                    replyToNote = note
                                    showComposer = true
                                },
                                onShowProfile: { userID, username, avatarURL in
                                    profileForUserID = userID
                                    profileUsername  = username
                                    profileAvatarURL = avatarURL
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        showProfile = true
                                    }
                                }
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, isGrouped ? 2 : 10)
                            .id(note.id)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Chat Bubble

private struct IssueChatBubble: View {
    let note:          GitLabIssueNote
    let isCurrentUser: Bool
    let isGrouped:     Bool
    let onReply:       () -> Void
    let onShowProfile: (Int, String, String?) -> Void

    @EnvironmentObject var settingsStore: SettingsStore

    @State private var dragOffset:       CGFloat = 0
    @State private var replyTriggered:   Bool    = false
    @State private var showProfile:      Bool    = false
    @State private var translatedText:   String? = nil
    @State private var showTranslated:   Bool    = false
    @State private var translationConfig: Any? = nil  // holds TranslationSession.Configuration on iOS 18+

    /// Tip corner radius: flat for the first in a sequence, rounded when grouped
    private var tipRadius: CGFloat { isGrouped ? 18 : 4 }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius:     18,
            bottomLeadingRadius:  isCurrentUser ? 18 : tipRadius,
            bottomTrailingRadius: isCurrentUser ? tipRadius : 18,
            topTrailingRadius:    18,
            style: .continuous
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {

            if isCurrentUser {
                Spacer(minLength: 56)
                bubbleView
                    .offset(x: dragOffset)
            } else {
                // Avatar column — hidden for grouped messages (same author run)
                Group {
                    if isGrouped {
                        Color.clear.frame(width: 32)
                    } else {
                        AvatarView(urlString: note.author.avatarURL,
                                   name: note.author.name, size: 32)
                            .padding(.bottom, 4)
                            .onTapGesture {
                                onShowProfile(note.author.id, note.author.username, note.author.avatarURL)
                            }
                    }
                }

                bubbleView
                    .offset(x: dragOffset)
                    // Swipe right to reply (only other users' messages)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                let h = value.translation.width
                                let v = value.translation.height
                                guard h > 0, abs(h) > abs(v) * 1.4 else { return }
                                dragOffset = min(h * 0.38, 52)
                                if dragOffset >= 48 && !replyTriggered {
                                    replyTriggered = true
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                            .onEnded { _ in
                                if replyTriggered { onReply() }
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                                    dragOffset = 0
                                }
                                replyTriggered = false
                            }
                    )

                Spacer(minLength: 56)
            }
        }
        // Reply icon that emerges from behind the bubble as you drag
        .overlay(alignment: .leading) {
            if !isCurrentUser && dragOffset > 6 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                    .opacity(Double(dragOffset) / 48.0)
                    .scaleEffect(0.5 + Double(dragOffset) / 96.0)
                    .padding(.leading, 4)
            }
        }
        .translationTaskIfAvailable(config: $translationConfig, text: note.body) { translated in
            translatedText = translated
            showTranslated = true
        }
    }

    @ViewBuilder
    private var bubbleView: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {

            // Author name — shown on first message of a run (non-grouped, other user)
            if !isCurrentUser && !isGrouped {
                Text(note.author.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            // Bubble
            // Own messages: force dark-mode semantic colours so all heading /
            // paragraph / list text stays legible against the tinted glass surface.
            Group {
                if isCurrentUser {
                    MarkdownRendererView(source: note.body, highContrast: true)
                        .environment(\.colorScheme, .dark)
                        .tint(.white)
                } else {
                    MarkdownRendererView(source: showTranslated && translatedText != nil ? (translatedText ?? note.body) : note.body)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .clipShape(bubbleShape)
            .background { bubbleBackground }
            .overlay(
                bubbleShape
                    .strokeBorder(
                        LinearGradient(
                            colors: isCurrentUser
                                ? [.white.opacity(0.38), .white.opacity(0.08)]
                                : [.white.opacity(0.28), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)

            // Translate button / toggle — independent of the AI toggle
            if settingsStore.translateCommentsEnabled
                && !isCurrentUser
                && needsTranslation(note.body) {
                if translatedText != nil {
                    Button {
                        showTranslated.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "translate")
                                .font(.system(size: 11))
                            Text(showTranslated ? "Show original" : "Show translated")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                } else {
                    Button {
                        if #available(iOS 18, *) {
                            translationConfig = TranslationSession.Configuration(source: nil, target: Locale.current.language)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Translate")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                }
            }

            // Timestamp
            Text(note.createdAt.relativeFormatted)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 4)
        }
    }

    private func needsTranslation(_ text: String) -> Bool {
        guard text.count > 10 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let detected = recognizer.dominantLanguage else { return false }
        let deviceLang = Locale.current.language.languageCode?.identifier ?? "en"
        return !detected.rawValue.hasPrefix(deviceLang)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if #available(iOS 26, *) {
            ZStack {
                bubbleShape.fill(.clear)
                    .glassEffect(.regular, in: bubbleShape)
                if isCurrentUser {
                    bubbleShape.fill(Color.accentColor.opacity(0.35))
                }
            }
        } else {
            ZStack {
                bubbleShape.fill(.ultraThinMaterial)
                if isCurrentUser {
                    bubbleShape.fill(Color.accentColor.opacity(0.45))
                }
                LinearGradient(
                    colors: [.white.opacity(isCurrentUser ? 0.32 : 0.22), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.20)
                )
                .clipShape(bubbleShape)
                LinearGradient(
                    colors: [.clear, .white.opacity(isCurrentUser ? 0.10 : 0.06)],
                    startPoint: UnitPoint(x: 0.5, y: 0.78),
                    endPoint: .bottom
                )
                .clipShape(bubbleShape)
            }
        }
    }
}

// MARK: - System Event Pill

private struct SystemEventPill: View {
    let note: GitLabIssueNote

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(note.body)
                .font(.system(size: 11))
                .italic()
                .lineLimit(2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var icon: String {
        let b = note.body.lowercased()
        if b.contains("closed")     { return "xmark.circle" }
        if b.contains("reopened")   { return "arrow.counterclockwise.circle" }
        if b.contains("assigned")   { return "person.circle" }
        if b.contains("unassigned") { return "person.slash" }
        if b.contains("label")      { return "tag" }
        if b.contains("milestone")  { return "flag" }
        if b.contains("mention")    { return "at" }
        if b.contains("commit")     { return "arrow.triangle.branch" }
        return "info.circle"
    }
}

// MARK: - Comment Composer Sheet

private struct CommentComposerSheet: View {
    let replyTo:  GitLabIssueNote?
    let isPosting: Bool
    let onPost:   (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(replyTo: GitLabIssueNote?, isPosting: Bool, onPost: @escaping (String) -> Void) {
        self.replyTo   = replyTo
        self.isPosting = isPosting
        self.onPost    = onPost
        // Pre-fill with a quoted reply if replying to another comment
        if let note = replyTo {
            let quoted = note.body
                .components(separatedBy: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")
            _text = State(initialValue: "> **@\(note.author.username)** wrote:\n\(quoted)\n\n")
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Reply context banner
                if let note = replyTo {
                    replyBanner(note)
                    Divider()
                }

                // Subscription hint
                HStack(spacing: 5) {
                    Image(systemName: "bell")
                        .font(.system(size: 11))
                    Text("Posting will follow this issue for notifications")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Divider()

                // Text input
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(replyTo != nil ? "Reply" : "New Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isPosting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Post") { onPost(text) }
                            .fontWeight(.semibold)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func replyBanner(_ note: GitLabIssueNote) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3, height: 36)
            AvatarView(urlString: note.author.avatarURL, name: note.author.name, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(note.author.name)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(note.body.prefix(80))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.07))
    }
}

// MARK: - Flow Layout (wrapping label chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Issue Edit Label Sheet

private struct IssueEditLabelSheet: View {
    /// Pre-selected label names when the sheet opens.
    let available:  [ProjectLabel]
    let onSave:     (Set<String>) -> Void

    @State private var selected: Set<String>
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var userColor: Color { settingsStore.accentColor ?? .accentColor }

    init(selectedNames: Set<String>, available: [ProjectLabel], onSave: @escaping (Set<String>) -> Void) {
        self.available = available
        self.onSave    = onSave
        _selected      = State(initialValue: selectedNames)
    }

    private var filtered: [ProjectLabel] {
        query.isEmpty ? available : available.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { label in
                    Button {
                        if selected.contains(label.name) {
                            selected.remove(label.name)
                        } else {
                            selected.insert(label.name)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(label.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(label.name)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(label.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(userColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
            .searchable(text: $query, prompt: "Filter labels")
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Translation compatibility shim

private extension View {
    /// Applies `.translationTask` on iOS 18+ using an `Any?` config storage.
    /// On iOS 17, this is a no-op — the Translate button is hidden by the
    /// `#available` guard in the bubble view.
    @ViewBuilder
    func translationTaskIfAvailable(
        config: Binding<Any?>,
        text: String,
        onTranslated: @escaping (String) -> Void
    ) -> some View {
        if #available(iOS 18, *) {
            self.translationTask(
                config.wrappedValue as? TranslationSession.Configuration
            ) { session in
                do {
                    let response = try await session.translate(text)
                    onTranslated(response.targetText)
                } catch {}
            }
        } else {
            self
        }
    }
}
