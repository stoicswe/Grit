import SwiftUI

// MARK: - Explore Navigation Destinations

enum ExploreDestination: Hashable {
    case allRepos
    case allGroups
    case groupDetail(GitLabGroup)
}

// MARK: - ExploreView

struct ExploreView: View {
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var viewModel = ExploreViewModel()
    @ObservedObject private var starVM = StarredReposViewModel.shared

    @State private var searchText = ""
    @State private var isSearchActive = false

    var body: some View {
        NavigationStack(path: $navState.exploreNavigationPath) {
            List {
                if isSearchActive && !searchText.isEmpty {
                    searchResultsContent
                } else {
                    trendingContent
                }
            }
            .listStyle(.plain)
            .animation(.spring(response: 0.38, dampingFraction: 0.88),
                       value: viewModel.projects.map(\.id))
            .animation(.spring(response: 0.38, dampingFraction: 0.85),
                       value: viewModel.searchResults.count +
                              viewModel.groupResults.count +
                              viewModel.userResults.count)
            .overlay {
                let showOverlay = viewModel.isLoading && viewModel.projects.isEmpty
                    && !(isSearchActive && !searchText.isEmpty)
                if showOverlay {
                    loadingOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.28),
                       value: viewModel.isLoading && viewModel.projects.isEmpty)
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                prompt: "Search all of GitLab"
            )
            .onChange(of: searchText) { _, query in viewModel.search(query: query) }
            .task {
                await viewModel.loadTrending(refresh: true)
                await starVM.loadIfNeeded()
            }
            .refreshable { await viewModel.loadTrending(refresh: true) }
            .navigationDestination(for: Repository.self) { repo in
                RepositoryDetailView(repository: repo)
                    .environmentObject(navState)
            }
            .navigationDestination(for: Repository.Namespace.self) { ns in
                GroupByIDView(namespace: ns)
                    .environmentObject(navState)
            }
            .navigationDestination(for: ExploreDestination.self) { destination in
                switch destination {
                case .allRepos:
                    ExploreAllReposView(sort: viewModel.sort)
                        .environmentObject(navState)
                case .allGroups:
                    ExploreAllGroupsView()
                        .environmentObject(navState)
                case .groupDetail(let group):
                    GroupDetailView(group: group, repoOrderBy: viewModel.sort.rawValue)
                        .environmentObject(navState)
                }
            }
            .navigationDestination(for: GitLabUser.self) { user in
                PublicProfileView(userID: user.id, username: user.username, avatarURL: user.avatarURL)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(ExploreSort.allCases) { option in
                Button {
                    Task { await viewModel.changeSort(option) }
                } label: {
                    Label(option.label, systemImage: option.icon)
                    if viewModel.sort == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }

    // MARK: - Trending (list section content)

    @ViewBuilder
    private var trendingContent: some View {
        if let error = viewModel.error {
            Section {
                ErrorBanner(message: error) { viewModel.error = nil }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        // ── Top 4 Repositories ──────────────────────────────────────────
        Section {
            if viewModel.projects.isEmpty && viewModel.isLoading {
                ForEach(0..<4, id: \.self) { _ in shimmerRow }
            } else {
                ForEach(viewModel.projects.prefix(4)) { repo in
                    NavigationLink(value: repo) {
                        RepositoryRowView(
                            repo: repo,
                            isStarred: starVM.isStarred(repo.id),
                            onToggleStar: { Task { await starVM.toggleStar(repo: repo) } },
                            onTapNamespace: { ns in navState.exploreNavigationPath.append(ns) }
                        )
                    }
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            exploreSectionHeader(
                title: "Repositories",
                icon: "folder.fill",
                isLoading: viewModel.isBackgroundRefreshing
            ) {
                navState.exploreNavigationPath.append(ExploreDestination.allRepos)
            }
        }

        // ── Top 4 Public Groups ─────────────────────────────────────────
        Section {
            if viewModel.groups.isEmpty && viewModel.isLoadingGroups {
                ForEach(0..<4, id: \.self) { _ in shimmerRow }
            } else {
                ForEach(viewModel.groups) { group in
                    Button {
                        navState.exploreNavigationPath.append(ExploreDestination.groupDetail(group))
                    } label: {
                        GroupRowView(group: group)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            exploreSectionHeader(
                title: "Public Groups",
                icon: "building.2.fill",
                isLoading: viewModel.isLoadingGroups && !viewModel.groups.isEmpty
            ) {
                navState.exploreNavigationPath.append(ExploreDestination.allGroups)
            }
        }
    }

    // MARK: - Section header builder

    private func exploreSectionHeader(
        title: String,
        icon: String,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.6)
                        .transition(.opacity)
                } else {
                    Label("See All", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(.secondary)
            .textCase(nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
        if !viewModel.isSearching && viewModel.searchIsEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowBackground(Color.clear)
        } else if !viewModel.searchIsEmpty {
            // ── Repositories (name / description match) ──────────────────────
            if !viewModel.searchResults.isEmpty {
                Section {
                    ForEach(viewModel.searchResults) { repo in
                        NavigationLink(value: repo) {
                            RepositoryRowView(
                                repo: repo,
                                isStarred: starVM.isStarred(repo.id),
                                onToggleStar: { Task { await starVM.toggleStar(repo: repo) } },
                                onTapNamespace: { ns in navState.exploreNavigationPath.append(ns) }
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    exploreSearchHeader(
                        icon: "folder.fill",
                        title: "Repositories",
                        count: viewModel.searchResults.count
                    )
                }
            }

            // ── Repositories matching topic / tag ────────────────────────────
            if !viewModel.topicResults.isEmpty {
                Section {
                    ForEach(viewModel.topicResults) { repo in
                        NavigationLink(value: repo) {
                            RepositoryRowView(
                                repo: repo,
                                isStarred: starVM.isStarred(repo.id),
                                onToggleStar: { Task { await starVM.toggleStar(repo: repo) } },
                                onTapNamespace: { ns in navState.exploreNavigationPath.append(ns) }
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    exploreSearchHeader(
                        icon: "tag.fill",
                        title: "Matching Topic",
                        count: viewModel.topicResults.count
                    )
                }
            }

            // ── Groups ───────────────────────────────────────────────────────
            if !viewModel.groupResults.isEmpty {
                Section {
                    ForEach(viewModel.groupResults) { group in
                        Button {
                            navState.exploreNavigationPath.append(ExploreDestination.groupDetail(group))
                        } label: {
                            GroupRowView(group: group)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    exploreSearchHeader(
                        icon: "building.2.fill",
                        title: "Groups",
                        count: viewModel.groupResults.count
                    )
                }
            }

            // ── People ───────────────────────────────────────────────────────
            if !viewModel.userResults.isEmpty {
                Section {
                    ForEach(viewModel.userResults) { user in
                        NavigationLink(value: user) {
                            userRow(user)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    exploreSearchHeader(
                        icon: "person.fill",
                        title: "People",
                        count: viewModel.userResults.count
                    )
                }
            }
        }
    }

    private func exploreSearchHeader(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(count)")
                .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    // MARK: - User Row

    private func userRow(_ user: GitLabUser) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: user.avatarURL, name: user.name, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shimmer row

    private var shimmerRow: some View {
        HStack(spacing: 12) {
            ShimmerView().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                ShimmerView().frame(height: 11).frame(maxWidth: 200)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .allowsHitTesting(false)
    }

    // MARK: - Loading Skeleton

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
