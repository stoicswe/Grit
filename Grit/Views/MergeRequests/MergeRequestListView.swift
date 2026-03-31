import SwiftUI

struct MergeRequestListView: View {
    let projectID: Int
    var embeddedMRs: [MergeRequest]? = nil

    @StateObject private var viewModel = MergeRequestViewModel()

    private var displayedMRs: [MergeRequest] {
        embeddedMRs ?? viewModel.mergeRequests
    }

    var body: some View {
        VStack(spacing: 12) {
            // Filter chips
            if embeddedMRs == nil {
                filterChips
            }

            if let error = viewModel.error {
                ErrorBanner(message: error) { viewModel.error = nil }
            }

            if viewModel.isLoading && displayedMRs.isEmpty {
                ProgressView().padding()
            } else if displayedMRs.isEmpty {
                emptyState
            } else {
                ForEach(displayedMRs) { mr in
                    NavigationLink(value: MRNavigation(projectID: projectID, mr: mr)) {
                        MergeRequestRowView(mr: mr)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: MRNavigation.self) { nav in
            MergeRequestDetailView(projectID: nav.projectID, mr: nav.mr)
        }
        .task {
            if embeddedMRs == nil {
                await viewModel.loadMergeRequests(projectID: projectID)
            }
        }
        .onChange(of: viewModel.filterState) { _, _ in
            Task { await viewModel.loadMergeRequests(projectID: projectID) }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["opened", "merged", "closed"], id: \.self) { state in
                    Button {
                        viewModel.filterState = state
                    } label: {
                        Text(state.capitalized)
                            .font(.system(size: 13, weight: viewModel.filterState == state ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                viewModel.filterState == state
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    viewModel.filterState == state
                                        ? Color.accentColor.opacity(0.5)
                                        : Color.secondary.opacity(0.3),
                                    lineWidth: 0.5
                                )
                            )
                    }
                    .foregroundStyle(viewModel.filterState == state ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No merge requests")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(30)
    }
}

// MARK: - Navigation wrapper

struct MRNavigation: Hashable {
    let projectID: Int
    let mr: MergeRequest

    func hash(into hasher: inout Hasher) { hasher.combine(mr.id) }
    static func == (lhs: MRNavigation, rhs: MRNavigation) -> Bool { lhs.mr.id == rhs.mr.id }
}

// MARK: - MR Row

struct MergeRequestRowView: View {
    let mr: MergeRequest

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // Top row
                HStack(alignment: .top, spacing: 8) {
                    MRStateBadge(state: mr.state)

                    Spacer()

                    if mr.isDraft {
                        Text("Draft")
                            .font(.system(size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    Text("!\(mr.iid)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                // Title
                Text(mr.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // Branches
                HStack(spacing: 4) {
                    branchTag(mr.sourceBranch)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    branchTag(mr.targetBranch)
                }

                // Author + time
                HStack(spacing: 8) {
                    AvatarView(
                        urlString: mr.author.avatarURL,
                        name: mr.author.name,
                        size: 20
                    )
                    Text(mr.author.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mr.updatedAt.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Labels
                if let labels = mr.labels, !labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func branchTag(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }
}
