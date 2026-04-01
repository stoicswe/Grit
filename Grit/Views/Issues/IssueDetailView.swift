import SwiftUI
import UIKit
import NaturalLanguage
import Translation

struct IssueDetailView: View {
    let issue:     GitLabIssue
    let projectID: Int

    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var viewModel = IssueDetailViewModel()
    @State private var showComposer  = false
    @State private var replyToNote:  GitLabIssueNote? = nil
    @State private var profileForUserID: Int? = nil
    @State private var profileUsername: String = ""
    @State private var profileAvatarURL: String? = nil
    @State private var showProfile = false

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
                chatSection
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("#\(issue.iid)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { followButton }
        }
        .task { await viewModel.load(projectID: projectID, issue: issue) }
        // Floating compose button inset so it doesn't obscure content
        .safeAreaInset(edge: .bottom, spacing: 0) { composerFAB }
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

    // MARK: - Floating Compose Button

    private var composerFAB: some View {
        HStack {
            Spacer()
            Button { showComposer = true } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.tint, in: Circle())
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 14, y: 6)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 12)
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
        let isOpen = issue.isOpen
        return HStack(spacing: 5) {
            Circle()
                .fill(isOpen ? Color.green : Color.purple)
                .frame(width: 8, height: 8)
            Text(isOpen ? "Open" : "Closed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOpen ? .green : .purple)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isOpen ? Color.green : Color.purple).opacity(0.12), in: Capsule())
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatBadge(title: "Upvotes",   value: "\(issue.upvotes)",   icon: "hand.thumbsup.fill")
            StatBadge(title: "Downvotes", value: "\(issue.downvotes)", icon: "hand.thumbsdown")
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
        if !issue.labels.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    GlassSectionHeader(title: "Labels", trailing: "\(issue.labels.count)")
                    FlowLayout(spacing: 6) {
                        ForEach(issue.labels, id: \.self) { label in
                            Text(label)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .padding(.horizontal)
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
        if let desc = issue.description,
           !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    GlassSectionHeader(title: "Description")
                    MarkdownRendererView(source: desc)
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
    @State private var translationConfig: TranslationSession.Configuration? = nil

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
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(note.body)
                translatedText = response.targetText
                showTranslated = true
            } catch {
                // Translation failed silently
            }
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
            // Own messages sit on a solid accent background: force the dark-mode
            // semantic colours (.primary → white, .secondary → light-gray) so all
            // heading / paragraph / list text stays legible regardless of accent hue.
            Group {
                if isCurrentUser {
                    MarkdownRendererView(source: note.body)
                        .environment(\.colorScheme, .dark)
                } else {
                    MarkdownRendererView(source: showTranslated && translatedText != nil ? (translatedText ?? note.body) : note.body)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleBackground)
            .clipShape(bubbleShape)
            .overlay(
                bubbleShape
                    .strokeBorder(
                        isCurrentUser ? Color.clear : Color.white.opacity(0.14),
                        lineWidth: 0.5
                    )
            )

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
                        translationConfig = TranslationSession.Configuration(source: nil, target: Locale.current.language)
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
        if isCurrentUser {
            Color.accentColor
        } else {
            Color.clear
                .background(.ultraThinMaterial)
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
