import SwiftUI

struct CommitDetailView: View {
    let commit: Commit
    let projectID: Int

    @StateObject private var aiService = AIAssistantService.shared
    @State private var aiExplanation: String?
    @State private var showAISheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        // Title
                        Text(commit.title)
                            .font(.system(size: 17, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        // Full message (if different)
                        if commit.message != commit.title, !commit.message.isEmpty {
                            Text(commit.message)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        // Author / committer
                        VStack(spacing: 10) {
                            infoRow(
                                icon: "person.fill",
                                label: "Author",
                                value: "\(commit.authorName) <\(commit.authorEmail)>"
                            )
                            infoRow(
                                icon: "calendar",
                                label: "Authored",
                                value: commit.authoredDate.formatted(date: .abbreviated, time: .shortened)
                            )
                            if commit.committerName != commit.authorName {
                                infoRow(
                                    icon: "person.badge.key.fill",
                                    label: "Committer",
                                    value: commit.committerName
                                )
                            }
                            infoRow(
                                icon: "clock",
                                label: "Committed",
                                value: commit.committedDate.formatted(date: .abbreviated, time: .shortened)
                            )
                        }

                        Divider()

                        // SHA
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Commit SHA")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(commit.id)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal)

                // Stats
                if let stats = commit.stats {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassSectionHeader(title: "Changes")
                            HStack(spacing: 16) {
                                statPill(label: "Additions", value: "+\(stats.additions)", color: .green)
                                statPill(label: "Deletions", value: "-\(stats.deletions)", color: .red)
                                statPill(label: "Total", value: "\(stats.total)", color: .accentColor)
                            }

                            // Visual diff bar
                            let total = max(stats.total, 1)
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.green)
                                        .frame(width: geo.size.width * CGFloat(stats.additions) / CGFloat(total))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.red)
                                        .frame(maxWidth: .infinity)
                                }
                                .frame(height: 6)
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(.horizontal)
                }

                // AI Explain button
                if aiService.isAvailable {
                    Button {
                        showAISheet = true
                        if aiExplanation == nil {
                            Task { await requestAIExplanation() }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15))
                            Text("Explain with Apple Intelligence")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
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

                // Parent commits
                if let parents = commit.parentIds, !parents.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionHeader(title: "Parent Commits", trailing: "\(parents.count)")
                            ForEach(parents, id: \.self) { sha in
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    Text(String(sha.prefix(12)))
                                        .font(.system(size: 13, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 30)
        }
        .navigationTitle(commit.shortSHA)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAISheet) {
            AIResponseSheet(
                title: "Commit Explanation",
                subtitle: commit.title,
                response: aiExplanation,
                isLoading: aiService.isProcessing
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helpers

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
        }
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func requestAIExplanation() async {
        let statsText: String
        if let stats = commit.stats {
            statsText = "+\(stats.additions) / -\(stats.deletions) lines changed"
        } else {
            statsText = "stats not available"
        }
        aiExplanation = try? await aiService.explainCommit(
            message: commit.message,
            stats: statsText
        )
    }
}
