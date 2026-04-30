import SwiftUI

/// Full-screen profile view for any GitLab user other than the currently
/// authenticated account. Mirrors the layout of ProfileView (glass card header,
/// stat badges, followers scroll, repos list) but omits the contributions graph
/// and adds a Follow / Following toggle button.
struct PublicProfileView: View {
    let userID:    Int
    let username:  String
    let avatarURL: String?

    @StateObject private var viewModel = UserProfileViewModel()

    @State private var reposExpanded  = false
    @State private var groupsExpanded = false

    private let sectionCap = 6

    private var isOwnProfile: Bool {
        AuthenticationService.shared.currentUser?.id == userID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading && viewModel.user == nil {
                    loadingView
                } else if let user = viewModel.user {
                    profileHeader(user)

                    if let error = viewModel.error {
                        ErrorBanner(message: error)
                            .padding(.horizontal)
                    }

                    statsGrid(user)

                    if !isOwnProfile {
                        followButton(userID: user.id)
                            .padding(.horizontal)
                    }

                    if !viewModel.followers.isEmpty {
                        followersSection
                    }

                    if !viewModel.repos.isEmpty {
                        reposSection
                    }

                    if !viewModel.groups.isEmpty {
                        groupsSection
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .background(.clear)
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.isBackgroundRefreshing {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView().scaleEffect(0.8)
                }
            }
        }
        .task { await viewModel.load(userID: userID) }
        .navigationDestination(for: GitLabGroup.self) { group in
            GroupDetailView(group: group, repoOrderBy: "last_activity_at")
                .environmentObject(AppNavigationState.shared)
        }
    }

    // MARK: - Header Card

    private func profileHeader(_ user: GitLabUser) -> some View {
        GlassCard {
            VStack(spacing: 14) {
                AvatarView(urlString: user.avatarURL, name: user.name, size: 80)
                    .shadow(color: .accentColor.opacity(0.3), radius: 12)

                VStack(spacing: 4) {
                    Text(user.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                if let location = user.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.caption)
                        Text(location)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                if !user.socialLinks.isEmpty {
                    socialLinksRow(user.socialLinks)
                }

                if let url = URL(string: user.webURL) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Open Profile in GitLab")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func socialLinksRow(_ links: [GitLabUser.SocialLink]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(links) { link in
                    Link(destination: link.url) {
                        HStack(spacing: 5) {
                            Image(systemName: link.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(link.label)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Stats Grid

    private func statsGrid(_ user: GitLabUser) -> some View {
        HStack(spacing: 12) {
            StatBadge(
                title: "Repos",
                value: "\(viewModel.repos.count)",
                icon:  "folder.fill"
            )
            StatBadge(
                title: "Groups",
                value: "\(viewModel.groups.count)",
                icon:  "person.3.fill"
            )
            StatBadge(
                title: "Followers",
                value: "\(user.followers ?? 0)",
                icon:  "person.2.fill"
            )
            StatBadge(
                title: "Following",
                value: "\(user.following ?? 0)",
                icon:  "figure.walk.arrival"
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Follow Button

    private func followButton(userID: Int) -> some View {
        Button {
            Task { await viewModel.toggleFollow(userID: userID) }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isTogglingFollow {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: viewModel.isFollowing
                          ? "person.fill.checkmark" : "person.badge.plus")
                }
                Text(viewModel.isFollowing ? "Following" : "Follow")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                viewModel.isFollowing
                    ? Color.secondary.opacity(0.15)
                    : Color.accentColor,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(viewModel.isFollowing ? Color.primary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTogglingFollow)
        .symbolEffect(.bounce, value: viewModel.isFollowing)
    }

    // MARK: - Followers Section

    private var followersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(
                title:    "Followers",
                trailing: "\(viewModel.followers.count)"
            )
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.followers) { follower in
                        NavigationLink(value: follower) {
                            VStack(spacing: 6) {
                                AvatarView(
                                    urlString: follower.avatarURL,
                                    name: follower.name,
                                    size: 48
                                )
                                .overlay(
                                    Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                                )
                                Text("@\(follower.username)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Repos Section

    private var reposSection: some View {
        let visible = reposExpanded
            ? viewModel.repos
            : Array(viewModel.repos.prefix(sectionCap))
        let overflow = viewModel.repos.count - sectionCap

        return VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(
                title:    "Repositories",
                trailing: "\(viewModel.repos.count)"
            )
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(visible) { repo in
                    NavigationLink(value: repo) {
                        repositoryRow(repo)
                    }
                    .buttonStyle(.plain)

                    if repo.id != visible.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }

                if overflow > 0 || reposExpanded {
                    Divider().padding(.leading, 16)
                    expandToggle(
                        isExpanded: $reposExpanded,
                        overflow: overflow
                    )
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

    // MARK: - Groups Section

    private var groupsSection: some View {
        let visible = groupsExpanded
            ? viewModel.groups
            : Array(viewModel.groups.prefix(sectionCap))
        let overflow = viewModel.groups.count - sectionCap

        return VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(
                title:    "Groups",
                trailing: "\(viewModel.groups.count)"
            )
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(visible) { group in
                    NavigationLink(value: group) {
                        groupRow(group)
                    }
                    .buttonStyle(.plain)

                    if group.id != visible.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }

                if overflow > 0 || groupsExpanded {
                    Divider().padding(.leading, 16)
                    expandToggle(
                        isExpanded: $groupsExpanded,
                        overflow: overflow
                    )
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

    private func groupRow(_ group: GitLabGroup) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: group.avatarURL, name: group.name, size: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(group.fullPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let count = group.membersCount, count > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill").font(.system(size: 10))
                        Text("\(count)").font(.caption)
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

    // MARK: - Expand / Collapse Toggle

    private func expandToggle(isExpanded: Binding<Bool>, overflow: Int) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(isExpanded.wrappedValue
                     ? "Show less"
                     : "\(overflow) more")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading Skeleton

    private var loadingView: some View {
        VStack(spacing: 16) {
            ShimmerView().frame(height: 200).padding(.horizontal)
            HStack(spacing: 12) {
                ShimmerView().frame(height: 72)
                ShimmerView().frame(height: 72)
                ShimmerView().frame(height: 72)
                ShimmerView().frame(height: 72)
            }
            .padding(.horizontal)
            ShimmerView().frame(height: 44).padding(.horizontal)
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 6) {
                        ShimmerView().frame(width: 48, height: 48).clipShape(Circle())
                        ShimmerView().frame(width: 52, height: 9).clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            ShimmerView().frame(height: 200).padding(.horizontal)
        }
        .padding(.top, 4)
    }
}
