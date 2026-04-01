import SwiftUI
import UIKit
import NaturalLanguage
import Translation

struct MergeRequestDetailView: View {
    let projectID: Int
    let mr:        MergeRequest

    @StateObject private var viewModel = MergeRequestViewModel()
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var commentText    = ""
    @State private var showReviewSheet = false
    @State private var showAISheet    = false
    @State private var showDiff       = false
    @FocusState private var commentFocused: Bool

    // Profile overlay
    @State private var showProfile      = false
    @State private var profileUserID:   Int    = 0
    @State private var profileUsername  = ""
    @State private var profileAvatarURL: String? = nil

    // Live MR state (updates after merge)
    private var liveMR: MergeRequest { viewModel.selectedMR ?? mr }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                if let err = viewModel.error {
                    ErrorBanner(message: err) { viewModel.error = nil }
                        .padding(.horizontal)
                }

                headerCard
                statsRow

                if AIAssistantService.shared.isUserEnabled {
                    aiReviewButton
                }

                branchCard

                if let desc = liveMR.description,
                   !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    descriptionCard(desc)
                }

                if let reviewers = liveMR.reviewers, !reviewers.isEmpty {
                    reviewersCard(reviewers)
                }

                diffSection
                chatSection

                if liveMR.state == .opened {
                    VStack(spacing: 10) {
                        approveButton
                        mergeButton
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("!\(mr.iid)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showReviewSheet = true } label: {
                    Label("Review", systemImage: "checkmark.seal")
                }
            }
        }
        // Three independent tasks so they run concurrently
        .task { await viewModel.loadMergeRequestDetail(projectID: projectID, mrIID: mr.iid) }
        .task { await viewModel.loadPermissions(projectID: projectID, mrIID: mr.iid) }
        .task { await viewModel.loadDiffs(projectID: projectID, mrIID: mr.iid) }
        .sheet(isPresented: $showReviewSheet) {
            ReviewActionSheet(projectID: projectID, mr: mr, viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAISheet) {
            AIResponseSheet(
                title: "AI Code Review",
                subtitle: mr.title,
                response: viewModel.aiReview,
                isLoading: viewModel.isAILoading
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if showProfile {
                UserProfileOverlay(
                    userID: profileUserID,
                    username: profileUsername,
                    avatarURL: profileAvatarURL,
                    isPresented: $showProfile
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    MRStateBadge(state: liveMR.state)
                    if liveMR.isDraft {
                        Text("Draft")
                            .font(.system(size: 12))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("!\(mr.iid)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(liveMR.title)
                    .font(.system(size: 18, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    AvatarView(urlString: mr.author.avatarURL, name: mr.author.name, size: 24)
                    Text(mr.author.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Updated \(mr.updatedAt.relativeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatBadge(title: "Upvotes",  value: "\(mr.upvotes)",
                      icon: "hand.thumbsup.fill")
            changesBadge
            StatBadge(title: "Comments",
                      value: "\(viewModel.notes.filter { !$0.system }.count)",
                      icon: "bubble.left.fill")
        }
        .padding(.horizontal)
    }

    private var changesBadge: some View {
        let adds   = viewModel.fileDiffs.reduce(0) { $0 + $1.additions }
        let dels   = viewModel.fileDiffs.reduce(0) { $0 + $1.deletions }
        let loaded = !viewModel.fileDiffs.isEmpty

        return VStack(spacing: 4) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            if loaded {
                // ViewThatFits tries the full "+N / -N" first;
                // if it overflows the badge it falls back to compact "+Nk/-Nk"
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        Text("+\(adds)")
                            .foregroundStyle(.green)
                        Text("/")
                            .foregroundStyle(.tertiary)
                        Text("-\(dels)")
                            .foregroundStyle(.red)
                    }
                    .font(.system(size: 13, weight: .bold, design: .monospaced))

                    HStack(spacing: 2) {
                        Text("+\(compactStat(adds))")
                            .foregroundStyle(.green)
                        Text("-\(compactStat(dels))")
                            .foregroundStyle(.red)
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
            } else {
                Text(mr.changesCount ?? "—")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }

            Text("Changes")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func compactStat(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000     { return "\(n / 1_000)k" }
        return "\(n)"
    }

    // MARK: - AI Review

    private var aiReviewButton: some View {
        Button {
            showAISheet = true
            if viewModel.aiReview == nil {
                Task { await viewModel.requestAIReview() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("AI Code Review").font(.system(size: 15, weight: .medium))
                Spacer()
                if viewModel.isAILoading { ProgressView().scaleEffect(0.8) }
                else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal)
    }

    // MARK: - Branch Card

    private var branchCard: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Source").font(.caption2).foregroundStyle(.secondary)
                    Text(mr.sourceBranch)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint).font(.system(size: 18))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Target").font(.caption2).foregroundStyle(.secondary)
                    Text(mr.targetBranch)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Description

    private func descriptionCard(_ desc: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader(title: "Description")
                MarkdownRendererView(source: desc)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Reviewers

    private func reviewersCard(_ reviewers: [MergeRequest.MRAuthor]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader(title: "Reviewers", trailing: "\(reviewers.count)")
                ForEach(reviewers) { reviewer in
                    HStack(spacing: 10) {
                        AvatarView(urlString: reviewer.avatarURL, name: reviewer.name, size: 32)
                            .onTapGesture {
                                profileUserID   = reviewer.id
                                profileUsername = reviewer.username
                                profileAvatarURL = reviewer.avatarURL
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    showProfile = true
                                }
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reviewer.name).font(.system(size: 14, weight: .medium))
                            Text("@\(reviewer.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Diff Section

    private var diffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header button
            Button {
                withAnimation(.spring(duration: 0.3)) { showDiff.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if viewModel.isDiffLoading {
                        Text("Loading changes…")
                            .font(.system(size: 14, weight: .medium))
                        ProgressView().scaleEffect(0.75)
                    } else if let err = viewModel.diffError {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(err).font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        let count = viewModel.fileDiffs.count
                        Text("\(count) changed file\(count == 1 ? "" : "s")")
                            .font(.system(size: 14, weight: .medium))
                        let adds = viewModel.fileDiffs.reduce(0) { $0 + $1.additions }
                        let dels = viewModel.fileDiffs.reduce(0) { $0 + $1.deletions }
                        if adds > 0 {
                            Text("+\(adds)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if dels > 0 {
                            Text("-\(dels)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer()

                    if !viewModel.isDiffLoading && !viewModel.fileDiffs.isEmpty {
                        Image(systemName: showDiff ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.fileDiffs.isEmpty && viewModel.diffError == nil)

            // Expanded diff
            if showDiff && !viewModel.fileDiffs.isEmpty {
                CommitDiffView(fileDiffs: viewModel.fileDiffs)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Chat Section

    @ViewBuilder
    private var chatSection: some View {
        let allNotes = viewModel.notes

        if viewModel.isLoading && allNotes.isEmpty {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Loading discussion…").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

        } else if !allNotes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Discussion")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    let count = allNotes.filter { !$0.system }.count
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
                    ForEach(Array(allNotes.enumerated()), id: \.element.id) { index, note in
                        let prev      = index > 0 ? allNotes[index - 1] : nil
                        let isGrouped = !note.system
                                        && prev?.system == false
                                        && prev?.author.id == note.author.id
                        let isMine    = note.author.id == viewModel.currentUserID

                        if note.system {
                            MRSystemEventPill(text: note.body)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 20)
                        } else {
                            MRChatBubble(
                                note:          note,
                                isCurrentUser: isMine,
                                isGrouped:     isGrouped,
                                onShowProfile: { uid, username, avatarURL in
                                    profileUserID    = uid
                                    profileUsername  = username
                                    profileAvatarURL = avatarURL
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        showProfile = true
                                    }
                                },
                                onFocusInput: { commentFocused = true }
                            )
                            .environmentObject(settingsStore)
                            .padding(.horizontal, 12)
                            .padding(.top, isGrouped ? 2 : 10)
                        }
                    }
                }
                .padding(.bottom, 8)

                // Inline comment input (open MRs only)
                if liveMR.state == .opened {
                    commentInput
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
        } else if !viewModel.isLoading {
            // No comments yet — show input
            if liveMR.state == .opened {
                commentInput.padding(.horizontal)
            }
        }
    }

    // MARK: - Comment Input

    private var commentInput: some View {
        GlassCard(padding: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Leave a comment…", text: $commentText, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .focused($commentFocused)
                    .frame(maxWidth: .infinity)

                if !commentText.isEmpty {
                    Button {
                        Task {
                            await viewModel.addComment(
                                projectID: projectID, mrIID: mr.iid, body: commentText
                            )
                            commentText = ""
                            commentFocused = false
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.tint)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.2), value: commentText.isEmpty)
    }

    // MARK: - Approve Button

    private var approveButton: some View {
        let canAct  = viewModel.userCanApprove && !viewModel.isApproving && !viewModel.isLoadingPerms
        let already = viewModel.userHasApproved

        return Button {
            guard canAct else { return }
            Task { await viewModel.approve(projectID: projectID, mrIID: mr.iid) }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isApproving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: already ? "checkmark.seal.fill" : "checkmark.seal")
                    Text(already ? "Already Approved" : "Approve Merge Request")
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .background(
            LinearGradient(
                colors: [.green, .green.opacity(0.7)],
                startPoint: .leading, endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: .green.opacity(canAct ? 0.35 : 0.1), radius: 10, y: 4)
        .opacity(canAct ? 1.0 : 0.45)
        .overlay(
            Group {
                if !canAct && !already && !viewModel.isLoadingPerms {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                        Text("No approval permission").font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        )
        .disabled(!canAct || already)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.25), value: canAct)
    }

    // MARK: - Merge Button

    private var mergeButton: some View {
        let canAct = viewModel.userCanMerge && !viewModel.isMerging && !viewModel.isLoadingPerms

        return Button {
            guard canAct else { return }
            Task { await viewModel.merge(projectID: projectID, mrIID: mr.iid) }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isMerging {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.merge")
                    Text("Merge Request").fontWeight(.semibold)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                startPoint: .leading, endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: Color.accentColor.opacity(canAct ? 0.35 : 0.1), radius: 10, y: 4)
        .opacity(canAct ? 1.0 : 0.45)
        .overlay(
            Group {
                if !canAct && !viewModel.isMerging && !viewModel.isLoadingPerms {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                        Text("No merge permission").font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        )
        .disabled(!canAct)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.25), value: canAct)
    }
}

// MARK: - MR Chat Bubble

private struct MRChatBubble: View {
    let note:          MRNote
    let isCurrentUser: Bool
    let isGrouped:     Bool
    let onShowProfile: (Int, String, String?) -> Void
    let onFocusInput:  () -> Void

    @EnvironmentObject var settingsStore: SettingsStore

    @State private var dragOffset:        CGFloat = 0
    @State private var replyTriggered:    Bool    = false
    @State private var translatedText:    String? = nil
    @State private var showTranslated:    Bool    = false
    @State private var translationConfig: TranslationSession.Configuration? = nil

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
                bubbleView.offset(x: dragOffset)
            } else {
                Group {
                    if isGrouped {
                        Color.clear.frame(width: 32)
                    } else {
                        AvatarView(urlString: note.author.avatarURL,
                                   name: note.author.name, size: 32)
                            .padding(.bottom, 4)
                            .onTapGesture {
                                onShowProfile(note.author.id,
                                              note.author.username,
                                              note.author.avatarURL)
                            }
                    }
                }

                bubbleView
                    .offset(x: dragOffset)
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
                                if replyTriggered { onFocusInput() }
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                                    dragOffset = 0
                                }
                                replyTriggered = false
                            }
                    )

                Spacer(minLength: 56)
            }
        }
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
                let response  = try await session.translate(note.body)
                translatedText = response.targetText
                showTranslated = true
            } catch {}
        }
    }

    @ViewBuilder
    private var bubbleView: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {

            // Author name on first in a run (non-grouped, other user)
            if !isCurrentUser && !isGrouped {
                Text(note.author.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            // Bubble
            Group {
                if isCurrentUser {
                    MarkdownRendererView(source: note.body)
                        .environment(\.colorScheme, .dark)
                } else {
                    MarkdownRendererView(
                        source: showTranslated && translatedText != nil
                            ? (translatedText ?? note.body) : note.body
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleBackground)
            .clipShape(bubbleShape)
            .overlay(
                bubbleShape.strokeBorder(
                    isCurrentUser ? Color.clear : Color.white.opacity(0.14),
                    lineWidth: 0.5
                )
            )

            // Translate button (independent of AI toggle)
            if settingsStore.translateCommentsEnabled
                && !isCurrentUser
                && needsTranslation(note.body) {
                if translatedText != nil {
                    Button { showTranslated.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "translate").font(.system(size: 11))
                            Text(showTranslated ? "Show original" : "Show translated")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                } else {
                    Button {
                        translationConfig = TranslationSession.Configuration(
                            source: nil, target: Locale.current.language
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.system(size: 11))
                            Text("Translate").font(.system(size: 11))
                        }
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                }
            }

            // Resolved status chip (for inline diff comments)
            if note.resolvable == true {
                HStack(spacing: 4) {
                    Image(systemName: note.resolved == true ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(note.resolved == true ? Color.green : Color.secondary)
                    Text(note.resolved == true ? "Resolved" : "Unresolved")
                        .font(.system(size: 11))
                        .foregroundStyle(note.resolved == true ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 4)
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
            Color.clear.background(.ultraThinMaterial)
        }
    }
}

// MARK: - MR System Event Pill

private struct MRSystemEventPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
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
        let b = text.lowercased()
        if b.contains("approved")   { return "checkmark.seal" }
        if b.contains("merged")     { return "arrow.triangle.merge" }
        if b.contains("closed")     { return "xmark.circle" }
        if b.contains("reopened")   { return "arrow.counterclockwise.circle" }
        if b.contains("assigned")   { return "person.circle" }
        if b.contains("commit")     { return "arrow.triangle.branch" }
        if b.contains("pipeline")   { return "gearshape.2" }
        if b.contains("label")      { return "tag" }
        if b.contains("milestone")  { return "flag" }
        if b.contains("mention")    { return "at" }
        return "info.circle"
    }
}
