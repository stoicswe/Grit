import SwiftUI

/// Context-aware search sheet.
///
/// **User-repos mode** (`userRepos` is non-nil, no repo in context):
///   Repo name/description/topic matching is done locally against the provided list.
///   Blobs, commits, and MRs are fetched from the global endpoint and filtered
///   client-side to only include results from the user's own projects.
///
/// **Explore / global mode** (no repo in context, `userRepos` is nil):
///   Searches repos by name, repos by topic, groups, users,
///   file blobs, commits, and merge requests concurrently across all of GitLab.
///
/// **Repo-detail mode** (repo in context):
///   Searches file blobs, commits, and merge requests within
///   that specific repository concurrently.
struct SearchView: View {
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.dismiss) var dismiss

    /// When non-nil, search is scoped to these repos (Repositories tab context).
    /// Repo name matching runs locally; blobs/commits/MRs are API-filtered to these IDs.
    var userRepos: [Repository]? = nil

    @State private var query = ""
    @State private var isSearchPresented = false

    private var isInsideRepo: Bool  { navState.currentRepository != nil }
    private var currentRepoID: Int? { navState.currentRepository?.id }
    /// True when we're searching the user's own repo list (not inside a specific repo, not Explore).
    private var isUserReposMode: Bool { userRepos != nil && !isInsideRepo }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    placeholderView
                } else if isInsideRepo {
                    repoResultsList
                } else {
                    globalResultsList
                }
            }
            .navigationTitle(isInsideRepo
                ? "Search \(navState.currentRepository!.name)"
                : isUserReposMode ? "My Repositories" : "Search GitLab"
            )
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $isSearchPresented, prompt: searchPrompt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, q in
                if isInsideRepo, let id = currentRepoID {
                    viewModel.searchRepo(query: q, projectID: id)
                } else if let repos = userRepos {
                    viewModel.searchWithinUserRepos(query: q, userRepos: repos)
                } else {
                    viewModel.searchGlobal(query: q)
                }
            }
            .onAppear { isSearchPresented = true }
            .onDisappear {
                // Explicitly resign first responder so the keyboard is fully
                // dismissed before the parent view re-lays out. Without this,
                // the keyboard's dismiss animation can leave transitional safe-area
                // insets that cause RepositoryDetailView to scroll past its header.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                viewModel.reset()
            }
            // ── Navigation destinations ───────────────────────────────────
            .navigationDestination(for: Repository.self) { repo in
                RepositoryDetailView(repository: repo)
                    .environmentObject(navState)
            }
            .navigationDestination(for: GitLabUser.self) { user in
                PublicProfileView(userID: user.id, username: user.username,
                                  avatarURL: user.avatarURL)
                    .environmentObject(navState)
            }
            .navigationDestination(for: GitLabGroup.self) { group in
                GroupDetailView(group: group, repoOrderBy: "last_activity_at")
                    .environmentObject(navState)
            }
            .navigationDestination(for: CommitNavigation.self) { nav in
                CommitDetailView(commit: nav.commit, projectID: nav.projectID)
            }
            .navigationDestination(for: MRNavigation.self) { nav in
                MergeRequestDetailView(projectID: nav.projectID, mr: nav.mr)
            }
        }
    }

    // MARK: - Prompt / placeholder

    private var searchPrompt: String {
        if isInsideRepo, let repo = navState.currentRepository {
            return "Files, commits, MRs in \(repo.name)…"
        }
        if isUserReposMode { return "Repos, files, commits, MRs…" }
        return "Repos, files, commits, MRs, groups, users…"
    }

    private var placeholderView: some View {
        ContentUnavailableView {
            Label(
                isInsideRepo      ? "Search this repository"
                : isUserReposMode ? "Search My Repositories"
                :                   "Search GitLab",
                systemImage: isInsideRepo      ? "magnifyingglass.circle"
                           : isUserReposMode   ? "folder.badge.magnifyingglass"
                           :                    "globe"
            )
        } description: {
            Text(isInsideRepo
                ? "Search files, commits, and merge requests in \(navState.currentRepository?.name ?? "this repo")"
                : isUserReposMode
                ? "Search repos, files, commits, and merge requests across your repositories"
                : "Search repos, files, commits, MRs, groups, and users"
            )
        }
    }

    // MARK: - Global / repo-list results

    @ViewBuilder
    private var globalResultsList: some View {
        if viewModel.globalIsEmpty && !viewModel.isSearching {
            // Search finished with no results
            ContentUnavailableView.search(text: query)
        } else {
            List {
                // Show repo skeleton while the first results are in-flight
                if viewModel.isSearching && viewModel.projectResults.isEmpty
                    && viewModel.taggedRepoResults.isEmpty {
                    repoSkeletonSection
                } else {
                    reposSection
                    topicsSection
                }
                if viewModel.isSearching && viewModel.fileResults.isEmpty {
                    skeletonSection(icon: "doc.text.magnifyingglass", title: "Files")
                } else {
                    filesSection
                }
                commitsSection(results: viewModel.commitResults, projectIDForNav: nil)
                mrsSection(results: viewModel.mrResults, projectIDForNav: nil)
                groupsSection
                usersSection
            }
            .listStyle(.plain)
            .animation(.spring(response: 0.38, dampingFraction: 0.85),
                       value: viewModel.projectResults.isEmpty)
        }
    }

    // MARK: - In-repo results

    @ViewBuilder
    private var repoResultsList: some View {
        if viewModel.repoIsEmpty && !viewModel.isSearching {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if viewModel.isSearching && viewModel.repoBlobResults.isEmpty {
                    skeletonSection(icon: "doc.text.magnifyingglass", title: "Files")
                } else {
                    repoBlobsSection
                }
                if let id = currentRepoID {
                    commitsSection(results: viewModel.repoCommitResults, projectIDForNav: id)
                    mrsSection(results: viewModel.repoMRResults, projectIDForNav: id)
                }
            }
            .listStyle(.plain)
            .animation(.spring(response: 0.38, dampingFraction: 0.85),
                       value: viewModel.repoIsEmpty)
        }
    }

    // MARK: - Section builders

    // ── Repositories by name ───────────────────────────────────────────────

    @ViewBuilder
    private var reposSection: some View {
        if !viewModel.projectResults.isEmpty {
            Section {
                ForEach(viewModel.projectResults) { repo in
                    NavigationLink(value: repo) {
                        repoRow(repo, showTopics: false)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                sectionHeader(icon: "folder.fill", title: "Repositories",
                              count: viewModel.projectResults.count)
            }
        }
    }

    // ── Repositories by topic ──────────────────────────────────────────────

    @ViewBuilder
    private var topicsSection: some View {
        if !viewModel.taggedRepoResults.isEmpty {
            Section {
                ForEach(viewModel.taggedRepoResults) { repo in
                    NavigationLink(value: repo) {
                        repoRow(repo, showTopics: true)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                sectionHeader(icon: "tag.fill", title: "Matching Topic",
                              count: viewModel.taggedRepoResults.count)
            }
        }
    }

    // ── File blobs (global) ────────────────────────────────────────────────

    @ViewBuilder
    private var filesSection: some View {
        if !viewModel.fileResults.isEmpty {
            Section {
                ForEach(viewModel.fileResults, id: \.displayID) { blob in
                    blobRow(blob)
                        .listRowBackground(Color.clear)
                }
            } header: {
                sectionHeader(icon: "doc.text.magnifyingglass", title: "Files",
                              count: viewModel.fileResults.count)
            }
        }
    }

    // ── File blobs (in-repo) ───────────────────────────────────────────────

    @ViewBuilder
    private var repoBlobsSection: some View {
        if !viewModel.repoBlobResults.isEmpty {
            Section {
                ForEach(viewModel.repoBlobResults, id: \.displayID) { blob in
                    blobRow(blob)
                        .listRowBackground(Color.clear)
                }
            } header: {
                sectionHeader(icon: "doc.text.magnifyingglass", title: "Files",
                              count: viewModel.repoBlobResults.count)
            }
        }
    }

    // ── Commits ────────────────────────────────────────────────────────────
    // `projectIDForNav` is nil for global results (use commit.projectID) or
    // the current repo's ID for in-repo results.

    @ViewBuilder
    private func commitsSection(results: [Commit], projectIDForNav: Int?) -> some View {
        if !results.isEmpty {
            Section {
                ForEach(results) { commit in
                    let pid = projectIDForNav ?? commit.projectID
                    if let pid {
                        NavigationLink(value: CommitNavigation(projectID: pid, commit: commit)) {
                            commitRow(commit)
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        commitRow(commit)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                sectionHeader(icon: "clock.arrow.circlepath", title: "Commits",
                              count: results.count)
            }
        }
    }

    // ── Merge Requests ─────────────────────────────────────────────────────

    @ViewBuilder
    private func mrsSection(results: [MergeRequest], projectIDForNav: Int?) -> some View {
        if !results.isEmpty {
            Section {
                ForEach(results) { mr in
                    let pid = projectIDForNav ?? mr.projectID
                    NavigationLink(value: MRNavigation(projectID: pid, mr: mr)) {
                        mrRow(mr)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                sectionHeader(icon: "arrow.triangle.merge", title: "Merge Requests",
                              count: results.count)
            }
        }
    }

    // ── Groups ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var groupsSection: some View {
        if !viewModel.groupResults.isEmpty {
            Section {
                ForEach(viewModel.groupResults) { group in
                    NavigationLink(value: group) {
                        groupRow(group)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                sectionHeader(icon: "person.3.fill", title: "Groups",
                              count: viewModel.groupResults.count)
            }
        }
    }

    // ── Users ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var usersSection: some View {
        if !viewModel.userResults.isEmpty {
            Section {
                ForEach(viewModel.userResults) { user in
                    NavigationLink(value: user) {
                        userRow(user)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                sectionHeader(icon: "person.fill", title: "Users",
                              count: viewModel.userResults.count)
            }
        }
    }

    // MARK: - Row views

    private func repoRow(_ repo: Repository, showTopics: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: repo.visibility == "private" ? "lock.fill" : "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(repo.nameWithNamespace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if showTopics, let topics = repo.topics, !topics.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(topics.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            if repo.starCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.system(size: 9))
                    Text("\(repo.starCount)").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func blobRow(_ blob: SearchBlob) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tint)
                Text(blob.filename)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
            }
            Text(blob.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(blob.data.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
    }

    private func commitRow(_ commit: Commit) -> some View {
        HStack(spacing: 12) {
            Text(commit.shortSHA)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(commit.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(commit.authoredDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func mrRow(_ mr: MergeRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mr.state == .merged ? "arrow.triangle.merge"
                             : mr.state == .closed ? "xmark.circle"
                             : "arrow.triangle.branch")
                .font(.system(size: 14))
                .foregroundStyle(mr.state == .opened ? Color.green
                                : mr.state == .merged ? Color.purple
                                : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(mr.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("!\(mr.iid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tint)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(mr.sourceBranch)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func groupRow(_ group: GitLabGroup) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: group.avatarURL, name: group.name, size: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(group.fullPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if let desc = group.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let count = group.membersCount, count > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "person.2.fill").font(.system(size: 9))
                    Text("\(count)").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func userRow(_ user: GitLabUser) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: user.avatarURL, name: user.name, size: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(.system(size: 15, weight: .semibold))
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Skeleton / shimmer sections

    /// A repos section with 3 shimmer rows, shown while the project search is in-flight.
    @ViewBuilder
    private var repoSkeletonSection: some View {
        Section {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 13).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 10).frame(maxWidth: 180)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .allowsHitTesting(false)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Repositories")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                ProgressView().scaleEffect(0.6)
            }
            .foregroundStyle(.secondary)
            .textCase(nil)
        }
    }

    /// A generic single-row shimmer section for any result type still loading.
    @ViewBuilder
    private func skeletonSection(icon: String, title: String) -> some View {
        Section {
            HStack(spacing: 12) {
                ShimmerView()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 5) {
                    ShimmerView().frame(height: 12).frame(maxWidth: .infinity)
                    ShimmerView().frame(height: 10).frame(maxWidth: 140)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(Color.clear)
            .allowsHitTesting(false)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                ProgressView().scaleEffect(0.6)
            }
            .foregroundStyle(.secondary)
            .textCase(nil)
        }
    }

    // MARK: - Section header

    private func sectionHeader(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(count)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}
