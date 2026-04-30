import SwiftUI

// MARK: - View Model

@MainActor
private final class GroupDetailViewModel: ObservableObject {
    @Published var projects:        [Repository] = []
    @Published var members:         [GitLabUser] = []
    @Published var isLoading        = false
    @Published var isLoadingMembers = false
    @Published var hasMore          = false
    @Published var error:           String?

    private var currentPage  = 1
    private var isPaginating = false
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    let group:       GitLabGroup
    let repoOrderBy: String

    init(group: GitLabGroup, repoOrderBy: String) {
        self.group       = group
        self.repoOrderBy = repoOrderBy
    }

    func load() async {
        await withTaskGroup(of: Void.self) { tg in
            tg.addTask { await self.loadProjects(refresh: true) }
            tg.addTask { await self.loadMembers() }
        }
    }

    func loadProjects(refresh: Bool) async {
        guard let token = auth.accessToken else { return }
        if refresh { currentPage = 1; isPaginating = false }
        isLoading = true
        error     = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchGroupProjects(
                groupID: group.id,
                orderBy: repoOrderBy,
                baseURL: auth.baseURL,
                token:   token,
                page:    currentPage
            )
            if refresh { projects = fetched } else { projects.append(contentsOf: fetched) }
            hasMore     = fetched.count == 25
            currentPage += 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isPaginating, hasMore else { return }
        isPaginating = true
        defer { isPaginating = false }
        await loadProjects(refresh: false)
    }

    func loadMembers() async {
        guard let token = auth.accessToken else { return }
        isLoadingMembers = true
        defer { isLoadingMembers = false }
        members = (try? await api.fetchGroupMembers(
            groupID: group.id,
            baseURL: auth.baseURL,
            token:   token
        )) ?? []
    }

    var repoCountLabel: String {
        if isLoading && projects.isEmpty { return "·  ·  ·" }
        return hasMore ? "\(projects.count)+" : "\(projects.count)"
    }

    var memberCountLabel: String {
        isLoadingMembers ? "·  ·  ·" : "\(members.count)"
    }
}

// MARK: - View

struct GroupDetailView: View {
    let group:       GitLabGroup
    let repoOrderBy: String

    @EnvironmentObject var navState: AppNavigationState
    @StateObject     private var viewModel: GroupDetailViewModel

    init(group: GitLabGroup, repoOrderBy: String) {
        self.group       = group
        self.repoOrderBy = repoOrderBy
        _viewModel = StateObject(
            wrappedValue: GroupDetailViewModel(group: group, repoOrderBy: repoOrderBy)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading && viewModel.projects.isEmpty && viewModel.members.isEmpty {
                    loadingView
                } else {
                    groupHeader

                    if let error = viewModel.error {
                        ErrorBanner(message: error) { viewModel.error = nil }
                            .padding(.horizontal)
                    }

                    statsGrid

                    if !viewModel.members.isEmpty || viewModel.isLoadingMembers {
                        membersSection
                    }

                    repositoriesSection
                }
            }
            .padding(.bottom, 30)
        }
        .background(.clear)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .navigationDestination(for: Repository.self) { repo in
            RepositoryDetailView(repository: repo)
                .environmentObject(navState)
        }
    }

    // MARK: - Header Card

    private var groupHeader: some View {
        GlassCard {
            VStack(spacing: 14) {
                AvatarView(urlString: group.avatarURL, name: group.name, size: 80)
                    .shadow(color: .accentColor.opacity(0.3), radius: 12)

                VStack(spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(group.fullPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let desc = group.description, !desc.isEmpty {
                    Text(desc)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }

                HStack(spacing: 8) {
                    VisibilityBadge(visibility: group.visibility)

                    if let url = URL(string: group.webURL) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Open in GitLab")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 12) {
            StatBadge(
                title: "Repositories",
                value: viewModel.repoCountLabel,
                icon: "folder.fill"
            )
            StatBadge(
                title: "Members",
                value: viewModel.memberCountLabel,
                icon: "person.2.fill"
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Members Section

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(
                title:    "Members",
                trailing: viewModel.isLoadingMembers ? nil : "\(viewModel.members.count)"
            )
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if viewModel.isLoadingMembers {
                        ForEach(0..<8, id: \.self) { _ in
                            VStack(spacing: 6) {
                                ShimmerView()
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                ShimmerView()
                                    .frame(width: 52, height: 9)
                                    .clipShape(Capsule())
                            }
                        }
                    } else {
                        ForEach(viewModel.members) { member in
                            NavigationLink(value: member) {
                                VStack(spacing: 6) {
                                    AvatarView(
                                        urlString: member.avatarURL,
                                        name: member.name,
                                        size: 48
                                    )
                                    .overlay(
                                        Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                                    )
                                    Text("@\(member.username)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 60)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Repositories Section

    private var repositoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(
                title:    "Repositories",
                trailing: (viewModel.isLoading && viewModel.projects.isEmpty) ? nil : viewModel.repoCountLabel
            )
            .padding(.horizontal)

            Group {
                if viewModel.isLoading && viewModel.projects.isEmpty {
                    // Shimmer skeleton
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in shimmerRepoRow }
                    }
                } else if viewModel.projects.isEmpty {
                    // Empty state
                    GlassCard {
                        ContentUnavailableView(
                            "No Repositories",
                            systemImage: "folder",
                            description: Text("This group has no public repositories.")
                        )
                    }
                } else {
                    // Populated list
                    VStack(spacing: 0) {
                        ForEach(viewModel.projects) { repo in
                            NavigationLink(value: repo) {
                                repositoryRow(repo)
                            }
                            .buttonStyle(.plain)

                            if repo.id != viewModel.projects.last?.id {
                                Divider().padding(.leading, 56)
                            }
                        }

                        if viewModel.hasMore {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .padding(.vertical, 14)
                                .onAppear { Task { await viewModel.loadMore() } }
                        }
                    }
                }
            }
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal)
        }
    }

    private func repositoryRow(_ repo: Repository) -> some View {
        HStack(spacing: 12) {
            Image(systemName: repo.visibility == "private" ? "lock.fill" : "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if repo.starCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                        Text("\(repo.starCount)").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var shimmerRepoRow: some View {
        HStack(spacing: 12) {
            ShimmerView()
                .frame(width: 20, height: 14)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 5) {
                ShimmerView().frame(height: 13).frame(maxWidth: .infinity)
                ShimmerView().frame(height: 10).frame(maxWidth: 170)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .allowsHitTesting(false)
    }

    // MARK: - Initial Loading Skeleton

    private var loadingView: some View {
        VStack(spacing: 16) {
            // Header card shimmer
            ShimmerView()
                .frame(height: 180)
                .padding(.horizontal)
            // Stats shimmer
            HStack(spacing: 12) {
                ShimmerView().frame(height: 72)
                ShimmerView().frame(height: 72)
            }
            .padding(.horizontal)
            // Members row shimmer
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 6) {
                        ShimmerView().frame(width: 48, height: 48).clipShape(Circle())
                        ShimmerView().frame(width: 52, height: 9).clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            // Repo rows shimmer
            ShimmerView().frame(height: 200).padding(.horizontal)
        }
        .padding(.top, 4)
    }
}
