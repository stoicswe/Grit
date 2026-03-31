import SwiftUI

struct RepositoryDetailView: View {
    let repository: Repository
    @StateObject private var viewModel = RepositoryDetailViewModel()
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var selectedTab: RepoTab = .commits
    @State private var showBranchPicker = false

    enum RepoTab: String, CaseIterable {
        case commits = "Commits"
        case branches = "Branches"
        case mergeRequests = "MRs"

        var icon: String {
            switch self {
            case .commits: return "clock.arrow.circlepath"
            case .branches: return "arrow.triangle.branch"
            case .mergeRequests: return "arrow.triangle.merge"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = viewModel.error {
                    ErrorBanner(message: error) { viewModel.error = nil }
                        .padding(.horizontal)
                }

                // Header card
                repoHeaderCard

                // Stats
                if let repo = viewModel.repository {
                    statsRow(repo)
                }

                // Tab selector
                tabSelector

                // Content
                tabContent
            }
            .padding(.bottom, 30)
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                subscribeButton
            }
        }
        .task { await viewModel.load(projectID: repository.id) }
        .sheet(isPresented: $showBranchPicker) {
            BranchPickerSheet(
                branches: viewModel.branches,
                selectedBranch: viewModel.selectedBranch
            ) { branch in
                showBranchPicker = false
                Task { await viewModel.loadCommits(projectID: repository.id, branch: branch) }
            }
        }
    }

    // MARK: - Subviews

    private var repoHeaderCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                        Image(systemName: repository.visibility == "private" ? "lock.fill" : "folder.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.nameWithNamespace)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        VisibilityBadge(visibility: repository.visibility)
                    }

                    Spacer()
                }

                if let desc = repository.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.horizontal)
    }

    private func statsRow(_ repo: Repository) -> some View {
        HStack(spacing: 10) {
            StatBadge(title: "Stars", value: "\(repo.starCount)", icon: "star.fill")
            StatBadge(title: "Forks", value: "\(repo.forksCount)", icon: "tuningfork")
            StatBadge(
                title: "Issues",
                value: "\(repo.openIssuesCount ?? 0)",
                icon: "exclamationmark.circle"
            )
        }
        .padding(.horizontal)
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(RepoTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                        Capsule()
                            .fill(selectedTab == tab ? Color.accentColor : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .commits:
            commitsContent
        case .branches:
            BranchListView(branches: viewModel.branches, isLoading: viewModel.isLoading)
                .padding(.horizontal)
        case .mergeRequests:
            MergeRequestListView(
                projectID: repository.id,
                embeddedMRs: viewModel.mergeRequests
            )
            .padding(.horizontal)
        }
    }

    private var commitsContent: some View {
        VStack(spacing: 12) {
            // Branch selector
            Button {
                showBranchPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12))
                    Text(viewModel.selectedBranch ?? "Select branch")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal)

            if viewModel.isLoading {
                ProgressView().padding()
            } else {
                CommitListView(
                    commits: viewModel.commits,
                    projectID: repository.id
                )
                .padding(.horizontal)
            }
        }
    }

    private var subscribeButton: some View {
        let isSubscribed = settingsStore.isSubscribed(to: repository.id)
        return Button {
            settingsStore.toggleProjectSubscription(repository.id)
        } label: {
            Image(systemName: isSubscribed ? "bell.fill" : "bell")
                .foregroundStyle(isSubscribed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
    }
}

// MARK: - Branch Picker Sheet

struct BranchPickerSheet: View {
    let branches: [Branch]
    let selectedBranch: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    var filteredBranches: [Branch] {
        searchText.isEmpty ? branches : branches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filteredBranches) { branch in
                Button {
                    onSelect(branch.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(branch.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                if branch.isDefault {
                                    Text("default")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                                if branch.protected {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                }
                            }
                            if let commit = branch.commit {
                                Text(commit.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if branch.name == selectedBranch {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search branches")
            .navigationTitle("Select Branch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
