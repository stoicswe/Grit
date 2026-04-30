import AppIntents
import SwiftUI

struct RepositoryDetailView: View {
    let repository: Repository

    @StateObject private var viewModel = RepositoryDetailViewModel()
    /// Use the singleton directly rather than @EnvironmentObject so the view works
    /// correctly when pushed from any context (sheet, NavigationStack, SearchView, etc.)
    /// without relying on environment propagation through Menu / NavigationLink chains.
    @ObservedObject private var navState = AppNavigationState.shared
    @ObservedObject private var starVM = StarredReposViewModel.shared

    @State private var selectedTab: RepoTab = .info
    @State private var showBranchPicker   = false
    @State private var showSearch         = false
    @State private var showIssues         = false
    @State private var showForks          = false
    @State private var showRepoInfo       = false
    @State private var showPipelineDetail = false

    enum RepoTab: String, CaseIterable {
        case info = "info"
        case files = "files"
        case commits = "commits"
        case branches = "branches"
        case mergeRequests = "mergeRequests"

        /// Localised display label.  Use this in UI instead of `rawValue`.
        var label: String {
            switch self {
            case .info:          return String(localized: "Info",     comment: "Repository detail tab: repo overview")
            case .files:         return String(localized: "Files",    comment: "Repository detail tab: file browser")
            case .commits:       return String(localized: "Commits",  comment: "Repository detail tab: commit history")
            case .branches:      return String(localized: "Branches", comment: "Repository detail tab: branch list")
            case .mergeRequests: return String(localized: "MRs",      comment: "Repository detail tab: merge requests (abbreviated)")
            }
        }

        var icon: String {
            switch self {
            case .info:          return "info.circle"
            case .files:         return "folder"
            case .commits:       return "clock.arrow.circlepath"
            case .branches:      return "arrow.triangle.branch"
            case .mergeRequests: return "arrow.triangle.merge"
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Zero-height anchor placed before all content so we can
                    // programmatically scroll back to the very top reliably,
                    // even when the view is pushed while keyboard insets are
                    // still animating out after a search sheet dismissal.
                    Color.clear.frame(height: 0).id("repoDetailTop")

                    if let error = viewModel.error {
                        ErrorBanner(message: error) { viewModel.error = nil }
                            .padding(.horizontal)
                            .transition(.opacity)
                    }

                    repoHeaderCard

                    if let repo = viewModel.repository {
                        statsRow(repo)
                            .transition(.opacity)
                    }

                    tabSelector
                    tabContent
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
                .animation(.easeOut(duration: 0.3), value: viewModel.repository != nil)
            }
            // Prevent the keyboard's animated layout guide from affecting this
            // scroll view's contentInset — the most common cause of the
            // "header scrolled out of view" bug after a search sheet dismissal.
            .ignoresSafeArea(.keyboard)
            .defaultScrollAnchor(.top)
            .onAppear {
                // DispatchQueue.main.async defers the scroll until after the
                // current layout pass, ensuring geometry is stable before we
                // force the position — onAppear alone fires too early during
                // the push animation and may be overridden by UIKit layout.
                DispatchQueue.main.async {
                    proxy.scrollTo("repoDetailTop", anchor: .top)
                }
            }
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Context menu
                repoContextMenu
            }
        }
        .task {
            await viewModel.load(projectID: repository.id)
            navState.enterRepository(repository, branch: viewModel.selectedBranch)
            viewModel.startPolling(projectID: repository.id)

            // Fetch AI context (README + top-level tree) in the background.
            // Non-blocking and best-effort — failures are silently ignored.
            guard let branch = viewModel.selectedBranch,
                  let token  = AuthenticationService.shared.accessToken else { return }
            let api     = GitLabAPIService.shared
            let baseURL = AuthenticationService.shared.baseURL
            let projID  = repository.id
            async let readme   = api.fetchReadme(
                projectID: projID, ref: branch, baseURL: baseURL, token: token)
            async let topLevel = try? api.fetchRepositoryTree(
                projectID: projID, path: "", ref: branch, baseURL: baseURL, token: token)
            navState.setRepositoryAIContext(readme: await readme, topLevel: await topLevel)
        }
        .onDisappear {
            viewModel.stopPolling()
            navState.leaveRepository()
        }
        // On-screen awareness: lets Siri / Apple Intelligence know which
        // project the user is currently viewing so it can act on it contextually.
        .userActivity("com.stoicswe.grit.viewingProject") { activity in
            activity.title = repository.name
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.targetContentIdentifier = "project-\(repository.id)"
            let entity = ProjectEntity(from: repository)
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
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
        .sheet(isPresented: $showPipelineDetail) {
            if let pipeline = viewModel.defaultBranchPipeline {
                PipelineDetailView(pipeline: pipeline, projectID: repository.id)
            }
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
                    repository:    repository,
                    projectID:     repository.id,
                    pipeline:      viewModel.defaultBranchPipeline,
                    onPipelineTap: viewModel.defaultBranchPipeline != nil ? {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            showRepoInfo = false
                        }
                        showPipelineDetail = true
                    } : nil,
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
                    Task { await viewModel.toggleWatch(repo: repository) }
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

            Section("CI/CD") {
                NavigationLink {
                    PipelineHistoryView(projectID: repository.id, defaultBranch: repository.defaultBranch)
                        .environmentObject(navState)
                } label: {
                    Label("Pipeline History", systemImage: "clock.arrow.circlepath")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(repository.nameWithNamespace)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                if let ns = repository.namespace, ns.kind == "group" {
                                    NavigationLink(value: ns) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 9, weight: .semibold))
                                            Text(ns.name)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                VisibilityBadge(visibility: repository.visibility)
                            }
                            if let pipeline = viewModel.defaultBranchPipeline {
                                Button { showPipelineDetail = true } label: {
                                    PipelineStatusBadge(pipeline: pipeline, isTappable: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                PipelineStatusBadge(
                                    pipeline: nil,
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
            HStack(spacing: 8) {
                ForEach(RepoTab.allCases, id: \.self) { tab in
                    let selected = selectedTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon).font(.system(size: 11, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            selected ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                selected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.28),
                                lineWidth: 0.5
                            )
                        )
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .info:
            RepoInfoTabView(
                repository: repository,
                branch: viewModel.selectedBranch ?? repository.defaultBranch ?? "main"
            )
            .padding(.horizontal)
            .transition(.opacity)
        case .files:
            filesContent
                .transition(.opacity)
        case .commits:
            commitsContent
                .transition(.opacity)
        case .branches:
            BranchListView(branches: viewModel.branches, projectID: repository.id, isLoading: viewModel.isLoading)
                .padding(.horizontal)
                .transition(.opacity)
        case .mergeRequests:
            MergeRequestListView(projectID: repository.id, embeddedMRs: viewModel.mergeRequests)
                .padding(.horizontal)
                .transition(.opacity)
        }
    }

    // ── Files tab ──

    private var filesContent: some View {
        Group {
            if viewModel.isLoading && viewModel.branches.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { _ in
                        HStack(spacing: 12) {
                            ShimmerView()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal)
                .transition(.opacity)
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

            CommitListView(
                commits: viewModel.commits,
                projectID: repository.id,
                isLoading: viewModel.isLoading
            )
            .padding(.horizontal)
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
