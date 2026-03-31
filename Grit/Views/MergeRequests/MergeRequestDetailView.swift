import SwiftUI

struct MergeRequestDetailView: View {
    let projectID: Int
    let mr: MergeRequest

    @StateObject private var viewModel = MergeRequestViewModel()
    @State private var commentText = ""
    @State private var showReviewSheet = false
    @State private var showAISheet = false
    @FocusState private var commentFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status + Title
                headerCard

                // Stats row
                statsRow

                // AI Review button
                if AIAssistantService.shared.isAvailable {
                    aiReviewButton
                }

                // Branches
                branchCard

                // Description
                if let desc = mr.description, !desc.isEmpty {
                    descriptionCard(desc)
                }

                // Reviewers
                if let reviewers = mr.reviewers, !reviewers.isEmpty {
                    reviewersCard(reviewers)
                }

                // Comments
                commentsSection

                // Approve button (shown for open MRs)
                if mr.state == .opened {
                    approveButton
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("!\(mr.iid)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showReviewSheet = true
                } label: {
                    Label("Review", systemImage: "checkmark.seal")
                }
            }
        }
        .task { await viewModel.loadMergeRequestDetail(projectID: projectID, mrIID: mr.iid) }
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
    }

    // MARK: - Cards

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    MRStateBadge(state: mr.state)
                    if mr.isDraft {
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

                Text(mr.title)
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

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatBadge(
                title: "Upvotes",
                value: "\(mr.upvotes)",
                icon: "hand.thumbsup.fill"
            )
            StatBadge(
                title: "Changes",
                value: mr.changesCount ?? "—",
                icon: "doc.badge.plus"
            )
            StatBadge(
                title: "Comments",
                value: "\(viewModel.notes.count)",
                icon: "bubble.left.fill"
            )
        }
        .padding(.horizontal)
    }

    private var aiReviewButton: some View {
        Button {
            showAISheet = true
            if viewModel.aiReview == nil {
                Task { await viewModel.requestAIReview() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("AI Code Review")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                if viewModel.isAILoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
            )
        }
        .foregroundStyle(.primary)
        .padding(.horizontal)
    }

    private var branchCard: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Source")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(mr.sourceBranch)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.tint)
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(mr.targetBranch)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    private func descriptionCard(_ desc: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader(title: "Description")
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal)
    }

    private func reviewersCard(_ reviewers: [MergeRequest.MRAuthor]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader(title: "Reviewers", trailing: "\(reviewers.count)")
                ForEach(reviewers) { reviewer in
                    HStack(spacing: 10) {
                        AvatarView(urlString: reviewer.avatarURL, name: reviewer.name, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reviewer.name)
                                .font(.system(size: 14, weight: .medium))
                            Text("@\(reviewer.username)")
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

    private var commentsSection: some View {
        VStack(spacing: 10) {
            if !viewModel.notes.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        GlassSectionHeader(title: "Comments", trailing: "\(viewModel.notes.count)")
                        ForEach(viewModel.notes) { note in
                            CommentRowView(note: note)
                            if note.id != viewModel.notes.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Comment input (open MRs only)
            if mr.state == .opened {
                commentInput
            }
        }
    }

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
                                projectID: projectID,
                                mrIID: mr.iid,
                                body: commentText
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
        .padding(.horizontal)
        .animation(.spring(duration: 0.2), value: commentText.isEmpty)
    }

    private var approveButton: some View {
        Button {
            Task { await viewModel.approve(projectID: projectID, mrIID: mr.iid) }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isApproving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Approve Merge Request")
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
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: .green.opacity(0.3), radius: 10, y: 4)
        .padding(.horizontal)
        .disabled(viewModel.isApproving)
    }
}

// MARK: - Comment Row

struct CommentRowView: View {
    let note: MRNote

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(urlString: note.author.avatarURL, name: note.author.name, size: 32)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(note.author.name)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(note.createdAt.relativeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(note.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if note.resolvable == true {
                    HStack(spacing: 4) {
                        Image(systemName: note.resolved == true ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(note.resolved == true ? .green : .secondary)
                        Text(note.resolved == true ? "Resolved" : "Unresolved")
                            .font(.caption2)
                            .foregroundStyle(note.resolved == true ? .green : .secondary)
                    }
                }
            }
        }
    }
}
