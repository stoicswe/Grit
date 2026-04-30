import SwiftUI

// Typed destinations for the Repositories NavigationStack
enum RepoListDestination: Hashable {
    case activity
    case starred
    case watching
}

struct RepositoryListView: View {
    @StateObject private var viewModel = RepositoryViewModel()
    @ObservedObject private var starVM = StarredReposViewModel.shared
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var navState: AppNavigationState
    @State private var showSearchSheet = false

    private var resolvedAccentColor: Color {
        settingsStore.accentColor ?? Color.accentColor
    }

    var body: some View {
        NavigationStack(path: $navState.repoNavigationPath) {
            VStack(spacing: 0) {
                filterChipBar

                ZStack {
                    List {
                        repositoriesContent
                    }
                    .listStyle(.plain)
                    .refreshable { await viewModel.loadRepositories(refresh: true) }
                    .animation(.spring(response: 0.38, dampingFraction: 0.88),
                               value: viewModel.filteredAndSorted.map(\.id))

                    if viewModel.isLoading && viewModel.repositories.isEmpty {
                        loadingOverlay
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.28),
                           value: viewModel.isLoading && viewModel.repositories.isEmpty)
            }
            .navigationTitle("Repositories")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadRepositories(refresh: true)
                await starVM.loadIfNeeded()
            }
            .task {
                await viewModel.backgroundRefresh()
            }
            .navigationDestination(for: Repository.self) { repo in
                RepositoryDetailView(repository: repo)
            }
            .navigationDestination(for: Repository.Namespace.self) { ns in
                GroupByIDView(namespace: ns)
                    .environmentObject(navState)
            }
            .navigationDestination(for: RepoListDestination.self) { destination in
                switch destination {
                case .activity: ActivityView()
                case .starred:  StarredReposView()
                case .watching: WatchingReposView()
                }
            }
            .onChange(of: navState.triggerRepoSearch) { _, triggered in
                if triggered {
                    showSearchSheet = true
                    navState.triggerRepoSearch = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Sort By") {
                            ForEach(RepoSortOrder.allCases) { order in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.sortOrder = order
                                    }
                                } label: {
                                    Label(
                                        order.label,
                                        systemImage: viewModel.sortOrder == order
                                            ? "checkmark" : order.icon
                                    )
                                }
                            }
                        }

                        Section("Repositories") {
                            Button {
                                navState.repoNavigationPath.append(RepoListDestination.starred)
                            } label: {
                                Label("Starred", systemImage: "star")
                            }
                            Button {
                                navState.repoNavigationPath.append(RepoListDestination.watching)
                            } label: {
                                Label("Watching", systemImage: "bell")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSearchSheet) {
                SearchView(userRepos: viewModel.repositories)
                    .environmentObject(navState)
                    .tint(resolvedAccentColor)
            }
        }
    }

    // MARK: - Filter Chip Bar

    private var filterChipBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    RepoFilterChip(
                        label: "All",
                        systemIcon: "square.grid.2x2",
                        avatarURL: nil,
                        isSelected: viewModel.groupFilter == .all,
                        accentColor: resolvedAccentColor
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) { viewModel.groupFilter = .all }
                    }

                    RepoFilterChip(
                        label: "Personal",
                        systemIcon: "person.fill",
                        avatarURL: nil,
                        isSelected: viewModel.groupFilter == .personal,
                        accentColor: resolvedAccentColor
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) { viewModel.groupFilter = .personal }
                    }

                    ForEach(viewModel.groups) { group in
                        let filter = RepoGroupFilter.group(group)
                        RepoFilterChip(
                            label: group.name,
                            systemIcon: "folder.fill",
                            avatarURL: group.avatarURL,
                            isSelected: viewModel.groupFilter == filter,
                            accentColor: resolvedAccentColor
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) { viewModel.groupFilter = filter }
                        }
                    }

                    if viewModel.isLoadingGroups {
                        ProgressView().scaleEffect(0.75)
                            .tint(resolvedAccentColor)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(.bar)

            Divider()
        }
    }

    // MARK: - Repositories (list section content)

    @ViewBuilder
    private var repositoriesContent: some View {
        if let error = viewModel.error {
            Section {
                ErrorBanner(message: error) { viewModel.error = nil }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        let filtered  = viewModel.filteredAndSorted
        let active    = filtered.filter { !$0.isScheduledForDeletion }
        let pending   = filtered.filter {  $0.isScheduledForDeletion }
        let starred   = active.filter {  starVM.isStarred($0.id) }
        let unstarred = active.filter { !starVM.isStarred($0.id) }

        // ── Count + sort indicator (top of list) ─────────────────────────
        if !viewModel.repositories.isEmpty {
            let countLabel: String = {
                // Append "+" when pagination is still ongoing — the true total is unknown.
                let totalSuffix = viewModel.hasMore ? "+" : ""
                let total       = "\(viewModel.repositories.count)\(totalSuffix)"
                switch viewModel.groupFilter {
                case .all:
                    return "\(total) repositories"
                default:
                    return "\(filtered.count) of \(total) repositories"
                }
            }()
            HStack(spacing: 6) {
                Text(countLabel)
                Text("·")
                Label(viewModel.sortOrder.label, systemImage: viewModel.sortOrder.icon)
                if viewModel.isBackgroundRefreshing {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isBackgroundRefreshing)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.top, 4)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        // ── Starred section ─────────────────────────────────────────────
        if !starred.isEmpty {
            Section {
                ForEach(starred) { repo in
                    repoRow(repo, forceStarred: true)
                }
            } header: {
                Label("Starred", systemImage: "star.fill")
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }

        // ── Main content — group-aware in "All", flat otherwise ─────────
        switch viewModel.groupFilter {
        case .all:
            allModeSections(unstarred: unstarred)
        case .personal, .group:
            flatSection(unstarred: unstarred)
        }

        // ── Deletion-pending section ─────────────────────────────────────
        if !pending.isEmpty {
            Section {
                ForEach(pending) { repo in repoRow(repo) }
            } header: {
                Label("Scheduled for Deletion", systemImage: "trash.fill")
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - All-mode sections (Personal + per-group)

    @ViewBuilder
    private func allModeSections(unstarred: [Repository]) -> some View {
        let personal      = unstarred.filter { $0.namespace?.kind == "user" }
        let knownGroupIDs = Set(viewModel.groups.map(\.id))
        let orphaned      = unstarred.filter {
            $0.namespace?.kind != "user" && !knownGroupIDs.contains($0.namespace?.id ?? -1)
        }

        // Personal repos
        if !personal.isEmpty {
            Section {
                ForEach(personal) { repo in repoRow(repo) }
            } header: {
                Label("Personal", systemImage: "person.fill")
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // One section per group (only shown if that group has repos in the list)
        ForEach(viewModel.groups) { group in
            let groupRepos = unstarred.filter { $0.namespace?.id == group.id }
            if !groupRepos.isEmpty {
                Section {
                    ForEach(groupRepos) { repo in repoRow(repo) }
                } header: {
                    HStack(spacing: 6) {
                        if let url = group.avatarURL, !url.isEmpty {
                            AvatarView(urlString: url, name: group.name, size: 14)
                        } else {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                        }
                        Text(group.name)
                    }
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }

        // Repos not matching any known group or personal namespace (subgroups, etc.)
        if !orphaned.isEmpty {
            Section {
                ForEach(orphaned) { repo in repoRow(repo) }
            } header: {
                Text("Other")
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // Load-more trigger
        if viewModel.hasMore {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowBackground(Color.clear)
                .onAppear { Task { await viewModel.loadRepositories() } }
        }
    }

    // MARK: - Flat section (Personal / Group filter active)

    @ViewBuilder
    private func flatSection(unstarred: [Repository]) -> some View {
        Section {
            ForEach(unstarred) { repo in repoRow(repo) }

            if viewModel.hasMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
                    .onAppear { Task { await viewModel.loadRepositories() } }
            }
        }
    }

    // MARK: - Shared row builder

    @ViewBuilder
    private func repoRow(_ repo: Repository, forceStarred: Bool? = nil) -> some View {
        NavigationLink(value: repo) {
            RepositoryRowView(
                repo: repo,
                isStarred: forceStarred ?? starVM.isStarred(repo.id),
                onToggleStar: { Task { await starVM.toggleStar(repo: repo) } },
                onTapNamespace: { ns in navState.repoNavigationPath.append(ns) }
            )
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Loading Skeleton

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 11).frame(maxWidth: 200)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Filter Chip

private struct RepoFilterChip: View {
    let label: String
    let systemIcon: String
    let avatarURL: String?
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let url = avatarURL, !url.isEmpty {
                    AvatarView(urlString: url, name: label, size: 16)
                } else {
                    Image(systemName: systemIcon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                isSelected ? accentColor.opacity(0.18) : Color.clear,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? accentColor.opacity(0.55) : Color.secondary.opacity(0.28),
                    lineWidth: 0.5
                )
            )
            .foregroundStyle(isSelected ? accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Repository Row

struct RepositoryRowView: View {
    let repo: Repository
    var isStarred: Bool = false
    var onToggleStar: (() -> Void)? = nil
    var showPipeline: Bool = false
    /// Called when the user taps the group namespace chip. Only fires when
    /// `repo.namespace?.kind == "group"`. Callers should append the namespace
    /// to their `NavigationPath` to push `GroupByIDView`.
    var onTapNamespace: ((Repository.Namespace) -> Void)? = nil

    @State private var pipeline: Pipeline? = nil

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                Image(systemName: repo.visibility == "private" ? "lock.fill" : "folder.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if repo.archived == true {
                        Text("archived")
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Row 1: group chip + visibility + pipeline
                HStack(spacing: 6) {
                    // Group namespace chip — inline before the visibility badge.
                    // Closure mode: caller appends to its own NavigationPath.
                    // Auto-link mode: NavigationLink(value:) resolved by the active stack.
                    if let ns = repo.namespace, ns.kind == "group" {
                        if let handler = onTapNamespace {
                            Button { handler(ns) } label: { namespaceChip(ns) }
                                .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: ns) { namespaceChip(ns) }
                                .buttonStyle(.plain)
                        }
                    }
                    VisibilityBadge(visibility: repo.visibility)
                    if showPipeline, let pipeline {
                        PipelineStatusBadge(pipeline: pipeline)
                    }
                }

                // Row 2: stars + timestamp
                HStack(spacing: 8) {
                    starBadge
                    if let activity = repo.lastActivityAt {
                        Text(activity.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                if repo.isScheduledForDeletion {
                    deletionBadge
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(repo.isScheduledForDeletion ? 0.72 : 1.0)
        .task(id: showPipeline) {
            guard showPipeline,
                  let token  = auth.accessToken,
                  let branch = repo.defaultBranch else { return }
            pipeline = try? await api.fetchLatestPipeline(
                projectID: repo.id,
                ref: branch,
                baseURL: auth.baseURL,
                token: token
            )
        }
    }

    // MARK: - Namespace chip

    private func namespaceChip(_ ns: Repository.Namespace) -> some View {
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

    // MARK: - Deletion badge

    private var deletionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "trash.fill")
                .font(.system(size: 9))
            if let date = repo.markedForDeletionDate {
                Text("Deletion scheduled · \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.system(size: 11))
            } else {
                Text("Scheduled for deletion")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.red.opacity(0.1), in: Capsule())
    }

    // MARK: - Star badge

    @ViewBuilder
    private var starBadge: some View {
        if repo.starCount > 0 || onToggleStar != nil {
            let label = HStack(spacing: 2) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                if repo.starCount > 0 {
                    Text("\(repo.starCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let action = onToggleStar {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }
}

// MARK: - Date Extension

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

