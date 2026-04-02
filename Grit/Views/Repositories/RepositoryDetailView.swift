import SwiftUI

struct RepositoryDetailView: View {
    let repository: Repository

    @StateObject private var viewModel = RepositoryDetailViewModel()
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var starVM = StarredReposViewModel.shared

    @State private var selectedTab: RepoTab = .files
    @State private var showBranchPicker = false
    @State private var showSearch = false
    @State private var showIssues = false
    @State private var showForks  = false
    @State private var showRepoInfo = false

    enum RepoTab: String, CaseIterable {
        case files = "Files"
        case commits = "Commits"
        case branches = "Branches"
        case mergeRequests = "MRs"

        var icon: String {
            switch self {
            case .files:         return "folder"
            case .commits:       return "clock.arrow.circlepath"
            case .branches:      return "arrow.triangle.branch"
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

                repoHeaderCard
                if let repo = viewModel.repository { statsRow(repo) }
                tabSelector
                tabContent
            }
            .padding(.bottom, 100)
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    // Contextual search
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }

                    // Context menu
                    repoContextMenu
                }
            }
        }
        .task {
            await viewModel.load(projectID: repository.id)
            navState.enterRepository(repository, branch: viewModel.selectedBranch)
        }
        .onDisappear {
            navState.leaveRepository()
        }
        .sheet(isPresented: $showBranchPicker) {
            BranchPickerSheet(
                branches: viewModel.branches,
                selectedBranch: viewModel.selectedBranch
            ) { branch in
                showBranchPicker = false
                navState.currentBranch = branch
                Task { await viewModel.loadCommits(projectID: repository.id, branch: branch) }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
                .environmentObject(navState)
        }
        .sheet(isPresented: $showIssues) {
            IssuesView(projectID: repository.id, repoName: repository.name)
        }
        .sheet(isPresented: $showForks) {
            ForksView(projectID: repository.id, parentRepoName: repository.name)
                .environmentObject(navState)
        }
        // File navigation destinations live on the parent NavigationStack
        .navigationDestination(for: FileNavigation.self) { nav in
            if nav.file.isDirectory {
                FileBrowserView(
                    projectID: nav.projectID,
                    ref: nav.ref,
                    path: nav.file.path,
                    displayName: nav.file.name
                )
            } else {
                FileContentView(
                    projectID: nav.projectID,
                    filePath: nav.file.path,
                    fileName: nav.file.name,
                    ref: nav.ref
                )
            }
        }
        .navigationDestination(for: CommitNavigation.self) { nav in
            CommitDetailView(commit: nav.commit, projectID: nav.projectID)
        }
        .navigationDestination(for: BranchNavigation.self) { nav in
            BranchDetailView(projectID: nav.projectID, branch: nav.branch)
        }
        // Repo info center popup — floats above all content
        .overlay {
            if showRepoInfo {
                RepoInfoOverlay(
                    repository:  repository,
                    projectID:   repository.id,
                    isPresented: $showRepoInfo
                )
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showRepoInfo)
    }

    // MARK: - Context Menu

    private var repoContextMenu: some View {
        Menu {
            Section("Repository") {
                Button {
                    Task { await viewModel.toggleWatch(projectID: repository.id) }
                } label: {
                    if viewModel.isTogglingWatch {
                        Label("Updating…", systemImage: "clock")
                    } else if viewModel.isWatching {
                        Label("Unwatch Repository", systemImage: "bell.slash")
                    } else {
                        Label("Watch Repository", systemImage: "bell.badge")
                    }
                }
                .disabled(viewModel.isTogglingWatch || viewModel.notificationLevel == nil)

                Button {
                    UIPasteboard.general.string = repository.httpURLToRepo
                } label: {
                    Label("Copy Clone URL", systemImage: "doc.on.clipboard")
                }

                if let url = URL(string: repository.webURL) {
                    Link(destination: url) {
                        Label("Open in Browser", systemImage: "safari")
                    }
                }

                Button {
                    showBranchPicker = true
                } label: {
                    Label("Switch Branch", systemImage: "arrow.triangle.branch")
                }
            }

            Divider()

            Section("App") {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Preferences", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Header

    private var repoHeaderCard: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showRepoInfo = true
            }
        } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                            Image(systemName: repository.visibility == "private" ? "lock.fill" : "folder.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repository.nameWithNamespace)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                VisibilityBadge(visibility: repository.visibility)
                                PipelineStatusBadge(
                                    pipeline: viewModel.defaultBranchPipeline,
                                    isLoading: viewModel.isPipelineLoading
                                )
                            }
                        }
                        Spacer()
                        // Tap hint chevron
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    if let desc = repository.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func statsRow(_ repo: Repository) -> some View {
        HStack(spacing: 10) {
            // Tappable star badge — stars/unstars the repo
            Button {
                Task { await starVM.toggleStar(repo: repo) }
            } label: {
                StatBadge(
                    title: starVM.isStarred(repo.id) ? "Starred" : "Stars",
                    value: "\(repo.starCount)",
                    icon: starVM.isStarred(repo.id) ? "star.fill" : "star"
                )
                .foregroundStyle(starVM.isStarred(repo.id) ? .yellow : .primary)
            }
            .buttonStyle(.plain)

            // Tappable forks badge — opens forks list sheet
            Button { showForks = true } label: {
                StatBadge(title: "Forks", value: "\(repo.forksCount)", icon: "tuningfork")
            }
            .buttonStyle(.plain)

            // Tappable issues badge — opens issues list sheet
            Button { showIssues = true } label: {
                StatBadge(title: "Issues", value: "\(repo.openIssuesCount ?? 0)", icon: "exclamationmark.circle")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .task { await starVM.loadIfNeeded() }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(RepoTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { selectedTab = tab }
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon).font(.system(size: 12))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            }
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            Capsule()
                                .fill(selectedTab == tab ? Color.accentColor : .clear)
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .files:
            filesContent
        case .commits:
            commitsContent
        case .branches:
            BranchListView(branches: viewModel.branches, projectID: repository.id, isLoading: viewModel.isLoading)
                .padding(.horizontal)
        case .mergeRequests:
            MergeRequestListView(projectID: repository.id, embeddedMRs: viewModel.mergeRequests)
                .padding(.horizontal)
        }
    }

    // ── Files tab ──

    private var filesContent: some View {
        Group {
            if viewModel.isLoading && viewModel.branches.isEmpty {
                ProgressView().padding()
            } else if let branch = viewModel.selectedBranch {
                FileBrowserView(
                    projectID: repository.id,
                    ref: branch,
                    path: "",
                    displayName: repository.name
                )
                .frame(minHeight: 300)
            } else {
                ContentUnavailableView("No branch selected", systemImage: "arrow.triangle.branch")
            }
        }
    }

    // ── Commits tab ──

    private var commitsContent: some View {
        VStack(spacing: 12) {
            Button {
                showBranchPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
                    Text(viewModel.selectedBranch ?? "Select branch")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal)

            if viewModel.isLoading {
                ProgressView().padding()
            } else {
                CommitListView(commits: viewModel.commits, projectID: repository.id)
                    .padding(.horizontal)
            }
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
        searchText.isEmpty ? branches : branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredBranches) { branch in
                Button { onSelect(branch.name) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(branch.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                if branch.isDefault {
                                    Text("default")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                                if branch.protected {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10)).foregroundStyle(.orange)
                                }
                            }
                            if let commit = branch.commit {
                                Text(commit.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
