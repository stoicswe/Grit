import SwiftUI

// MARK: - Navigation wrapper

struct BranchNavigation: Hashable {
    let projectID: Int
    let branch: Branch

    func hash(into hasher: inout Hasher) {
        hasher.combine(projectID)
        hasher.combine(branch.name)
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.projectID == rhs.projectID && lhs.branch.name == rhs.branch.name
    }
}

// MARK: - Branch Detail View

struct BranchDetailView: View {
    let projectID: Int
    let branch: Branch

    @StateObject private var viewModel = BranchDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                branchHeader
                    .padding(.horizontal)
                    .padding(.bottom, 20)

                if let error = viewModel.error {
                    ErrorBanner(message: error) { viewModel.error = nil }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }

                commitTimeline
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(branch.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(projectID: projectID, branch: branch.name, refresh: true) }
        .refreshable { await viewModel.load(projectID: projectID, branch: branch.name, refresh: true) }
        // Forward commit taps up to the parent NavigationStack
        .navigationDestination(for: CommitNavigation.self) { nav in
            CommitDetailView(commit: nav.commit, projectID: nav.projectID)
        }
    }

    // MARK: - Branch Header

    private var branchHeader: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {

                // Name + badges row
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 18))
                        .foregroundStyle(.tint)

                    Text(branch.name)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        if branch.isDefault {
                            badge("default", color: .blue)
                        }
                        if branch.protected {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                Text("protected")
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                        }
                        if branch.merged {
                            badge("merged", color: .green)
                        }
                    }
                }

                // Latest commit preview
                if let commit = branch.commit {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Latest commit")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .tracking(0.4)
                            Text(commit.title)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(commit.shortId)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                                if let date = commit.committedDate {
                                    Text("·").foregroundStyle(.quaternary)
                                    Text(date.relativeFormatted)
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Commit Timeline

    private var commitTimeline: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.commits.isEmpty {
                skeletonTimeline
            } else if viewModel.commits.isEmpty {
                ContentUnavailableView(
                    "No commits",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("This branch has no commit history.")
                )
                .padding(.top, 40)
            } else {
                timelineRows
            }
        }
    }

    private var timelineRows: some View {
        LazyVStack(spacing: 0) {
            // Section header
            HStack {
                Text("\(viewModel.commits.count)\(viewModel.hasMore ? "+" : "") commits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            ForEach(Array(viewModel.commits.enumerated()), id: \.element.id) { index, commit in
                timelineRow(commit: commit, isLast: index == viewModel.commits.count - 1 && !viewModel.hasMore)
            }

            // Pagination trigger
            if viewModel.hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
                .onAppear {
                    Task { await viewModel.load(projectID: projectID, branch: branch.name) }
                }
            }
        }
    }

    private func timelineRow(commit: Commit, isLast: Bool) -> some View {
        NavigationLink(value: CommitNavigation(projectID: projectID, commit: commit)) {
            HStack(alignment: .top, spacing: 0) {

                // ── Timeline gutter ──────────────────────────────────
                VStack(spacing: 0) {
                    // Dot
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 26, height: 26)
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                    }

                    // Connecting line (omit on last item)
                    if !isLast {
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 46)

                // ── Commit card ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    commitCard(commit)
                        .padding(.trailing, 16)
                        .padding(.bottom, isLast ? 0 : 12)
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 16)
            .frame(minHeight: 72)
        }
        .buttonStyle(.plain)
    }

    private func commitCard(_ commit: Commit) -> some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {

                // Commit title
                Text(commit.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Meta row
                HStack(spacing: 10) {
                    AvatarView(urlString: nil, name: commit.authorName, size: 18)

                    Text(commit.authorName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("·").foregroundStyle(.quaternary)

                    Text(commit.authoredDate.relativeFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 0)

                    // SHA chip
                    Text(commit.shortSHA)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }

                // Stats bar
                if let stats = commit.stats, stats.total > 0 {
                    HStack(spacing: 6) {
                        if stats.additions > 0 {
                            Label("+\(stats.additions)", systemImage: "plus")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if stats.deletions > 0 {
                            Label("-\(stats.deletions)", systemImage: "minus")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red)
                        }

                        // Mini diff bar
                        let total = CGFloat(max(stats.total, 1))
                        GeometryReader { geo in
                            HStack(spacing: 1) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.green)
                                    .frame(width: geo.size.width * CGFloat(stats.additions) / total)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.red)
                                    .frame(maxWidth: .infinity)
                            }
                            .frame(height: 4)
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }

    // MARK: - Loading Skeleton

    private var skeletonTimeline: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 26, height: 26)
                        if i < 7 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 2, height: 80)
                        }
                    }
                    .frame(width: 46)

                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 11).frame(maxWidth: 180)
                        ShimmerView().frame(height: 8).frame(maxWidth: 100)
                    }
                    .padding(12)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }
                .padding(.leading, 16)
            }
        }
    }

    // MARK: - Helpers

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
