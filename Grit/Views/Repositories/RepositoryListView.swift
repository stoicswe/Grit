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
    @State private var navigationPath  = NavigationPath()
    @State private var inlineSearchText = ""
    @State private var isInlineSearchActive = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isInlineSearchActive && !inlineSearchText.isEmpty {
                    searchResultsList
                } else {
                    repositoriesList
                }
            }
            .navigationTitle("Repositories")
            .searchable(
                text: $inlineSearchText,
                isPresented: $isInlineSearchActive,
                prompt: "Filter my repositories"
            )
            .onChange(of: inlineSearchText) { _, query in viewModel.search(query: query) }
            .task {
                await viewModel.loadRepositories(refresh: true)
                await starVM.loadIfNeeded()
            }
            .refreshable { await viewModel.loadRepositories(refresh: true) }
            .navigationDestination(for: Repository.self) { repo in
                RepositoryDetailView(repository: repo)
            }
            .navigationDestination(for: RepoListDestination.self) { destination in
                switch destination {
                case .activity: ActivityView()
                case .starred:  StarredReposView()
                case .watching: WatchingReposView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        navigationPath.append(RepoListDestination.activity)
                    } label: {
                        Image(systemName: "waveform")
                    }
                }
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
                                        order.rawValue,
                                        systemImage: viewModel.sortOrder == order
                                            ? "checkmark" : order.icon
                                    )
                                }
                            }
                        }

                        Section("Repositories") {
                            Button {
                                navigationPath.append(RepoListDestination.starred)
                            } label: {
                                Label("Starred", systemImage: "star")
                            }
                            Button {
                                navigationPath.append(RepoListDestination.watching)
                            } label: {
                                Label("Watching", systemImage: "bell")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Repositories List

    private var repositoriesList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Apply sort then pin deletion-scheduled repos to the bottom
            let sorted  = viewModel.sortedRepositories
            let active  = sorted.filter { !$0.isScheduledForDeletion }
            let pending = sorted.filter {  $0.isScheduledForDeletion }

            Section {
                ForEach(active) { repo in
                    NavigationLink(value: repo) {
                        RepositoryRowView(
                            repo: repo,
                            isStarred: starVM.isStarred(repo.id),
                            onToggleStar: { Task { await starVM.toggleStar(repo: repo) } }
                        )
                    }
                    .listRowBackground(Color.clear)
                }

                if viewModel.hasMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .onAppear { Task { await viewModel.loadRepositories() } }
                }
            } header: {
                if !viewModel.repositories.isEmpty {
                    HStack(spacing: 6) {
                        Text("\(viewModel.repositories.count) repositories")
                        Text("·")
                        Label(viewModel.sortOrder.rawValue, systemImage: viewModel.sortOrder.icon)
                    }
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { repo in
                        NavigationLink(value: repo) {
                            RepositoryRowView(
                                repo: repo,
                                isStarred: starVM.isStarred(repo.id),
                                onToggleStar: { Task { await starVM.toggleStar(repo: repo) } }
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Label("Scheduled for Deletion", systemImage: "trash.fill")
                        .textCase(nil)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading && viewModel.repositories.isEmpty {
                loadingOverlay
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            if viewModel.isSearching {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if viewModel.searchResults.isEmpty && !inlineSearchText.isEmpty {
                ContentUnavailableView.search(text: inlineSearchText)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.searchResults) { repo in
                    NavigationLink(value: repo) {
                        RepositoryRowView(
                            repo: repo,
                            isStarred: starVM.isStarred(repo.id),
                            onToggleStar: { Task { await starVM.toggleStar(repo: repo) } }
                        )
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
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

// MARK: - Repository Row

struct RepositoryRowView: View {
    let repo: Repository
    var isStarred: Bool = false
    var onToggleStar: (() -> Void)? = nil
    var showPipeline: Bool = false

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

                HStack(spacing: 10) {
                    VisibilityBadge(visibility: repo.visibility)
                    if showPipeline, let pipeline {
                        PipelineStatusBadge(pipeline: pipeline)
                    }
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
