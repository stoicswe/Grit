import SwiftUI

struct CommitDetailView: View {
    let commit: Commit
    let projectID: Int

    @ObservedObject private var aiService = AIAssistantService.shared
    @StateObject private var diffVM = CommitDiffViewModel()
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
                if aiService.isUserEnabled {
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

                // Changed files diff section
                diffSection
            }
            .padding(.bottom, 30)
        }
        .navigationTitle(commit.shortSHA)
        .navigationBarTitleDisplayMode(.inline)
        .task { await diffVM.load(projectID: projectID, sha: commit.id) }
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

    // MARK: - Diff Section

    @ViewBuilder
    private var diffSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if diffVM.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading diff…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)

            } else if let errMsg = diffVM.error {
                GlassCard {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(errMsg)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

            } else if !diffVM.fileDiffs.isEmpty {
                CommitDiffView(fileDiffs: diffVM.fileDiffs)
                    .padding(.horizontal)
            }
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
            statsText = "+\(stats.additions) additions, -\(stats.deletions) deletions, \(stats.total) lines total"
        } else {
            statsText = "stats not available"
        }

        // Wait for the diff to finish loading (usually already done by the time
        // the user taps Explain, but guard just in case).
        if diffVM.isLoading {
            // Poll briefly — diffs normally load in < 1 s
            var waited = 0
            while diffVM.isLoading && waited < 20 {
                try? await Task.sleep(for: .milliseconds(150))
                waited += 1
            }
        }

        aiExplanation = try? await aiService.explainCommit(
            message: commit.message,
            stats: statsText,
            diff: buildDiffText(from: diffVM.fileDiffs)
        )
    }

    /// Reconstructs a compact unified diff string from pre-parsed file diffs.
    /// Caps total output to ~6 000 characters so the model prompt stays reasonable.
    private func buildDiffText(from fileDiffs: [ParsedFileDiff]) -> String {
        guard !fileDiffs.isEmpty else { return "" }

        let characterBudget = 6_000
        var output = ""

        for file in fileDiffs {
            guard !file.isBinaryOrEmpty, !file.isTooLarge else { continue }

            let header: String
            if file.meta.renamedFile,
               let old = file.meta.oldPath, let new = file.meta.newPath, old != new {
                header = "--- \(old)\n+++ \(new)\n"
            } else {
                header = "--- \(file.meta.displayPath)\n+++ \(file.meta.displayPath)\n"
            }

            var fileChunk = header
            for line in file.lines {
                let prefix: String
                switch line.kind {
                case .hunkHeader: prefix = ""          // keep the @@ line as-is
                case .added:      prefix = "+"
                case .removed:    prefix = "-"
                case .context:    prefix = " "
                case .meta:       continue             // skip +++ / --- / \ No newline
                }
                fileChunk += "\(prefix)\(line.content)\n"
            }

            // Stop adding files once we would exceed the budget
            if output.count + fileChunk.count > characterBudget {
                let remaining = characterBudget - output.count
                if remaining > header.count {
                    output += String(fileChunk.prefix(remaining))
                    output += "\n… (diff truncated)"
                }
                break
            }

            output += fileChunk
        }

        return output
    }
}
