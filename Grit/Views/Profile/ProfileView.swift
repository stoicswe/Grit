import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var viewModel = ProfileViewModel()

    // Follower profile overlay
    @State private var showFollowerProfile    = false
    @State private var followerProfileID:     Int    = 0
    @State private var followerProfileUsername = ""
    @State private var followerProfileAvatarURL: String? = nil

    var body: some View {
        NavigationStack {
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

                        if let stats = viewModel.contributionStats {
                            contributionSection(stats)
                        }

                        statsGrid(user)

                        if !viewModel.followers.isEmpty {
                            followersSection
                        }

                        if !viewModel.ownedRepositories.isEmpty {
                            reposSection
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .background(.clear)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .onAppear { Task { await viewModel.load() } }
        .refreshable { await viewModel.load() }
        .overlay {
            if showFollowerProfile {
                UserProfileOverlay(
                    userID:   followerProfileID,
                    username: followerProfileUsername,
                    avatarURL: followerProfileAvatarURL,
                    isPresented: $showFollowerProfile
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Subviews

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
                        .background(Color.accentColor.opacity(0.1),
                                    in: Capsule())
                    }
                }
            }
        }
    }

    private func statsGrid(_ user: GitLabUser) -> some View {
        HStack(spacing: 12) {
            StatBadge(
                title: "Repos",
                value: "\(viewModel.ownedRepositories.count)",
                icon: "folder.fill"
            )
            StatBadge(
                title: "Streak",
                value: "\(viewModel.contributionStats?.currentStreak ?? 0)d",
                icon: "flame.fill"
            )
            StatBadge(
                title: "Contributions",
                value: formatCount(viewModel.contributionStats?.totalContributions ?? 0),
                icon: "chart.bar.fill"
            )
        }
        .padding(.horizontal)
    }

    private func contributionSection(_ stats: ContributionStats) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(
                    title: "Contributions",
                    trailing: "\(stats.totalContributions) this year"
                )

                ContributionGraphView(stats: stats)

                HStack(spacing: 16) {
                    contributionStat(
                        value: "\(stats.currentStreak)",
                        label: "Current streak",
                        unit: "days",
                        icon: "flame.fill",
                        color: .orange
                    )
                    Divider().frame(height: 40)
                    contributionStat(
                        value: "\(stats.longestStreak)",
                        label: "Longest streak",
                        unit: "days",
                        icon: "trophy.fill",
                        color: .yellow
                    )
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }

    private func contributionStat(
        value: String, label: String, unit: String, icon: String, color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Followers Section

    private var followersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSectionHeader(
                    title: "Followers",
                    trailing: "\(viewModel.followers.count)"
                )
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.followers) { follower in
                        Button {
                            followerProfileID       = follower.id
                            followerProfileUsername = follower.username
                            followerProfileAvatarURL = follower.avatarURL
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                showFollowerProfile = true
                            }
                        } label: {
                            VStack(spacing: 6) {
                                AvatarView(urlString: follower.avatarURL,
                                           name: follower.name, size: 48)
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
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: "Recent Repositories")
                .padding(.horizontal)

            VStack(spacing: 1) {
                ForEach(viewModel.ownedRepositories.prefix(5)) { repo in
                    NavigationLink(value: repo) {
                        repositoryRow(repo)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal)
        }
        .navigationDestination(for: Repository.self) { repo in
            RepositoryDetailView(repository: repo)
        }
    }

    private func repositoryRow(_ repo: Repository) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.system(size: 15, weight: .medium))
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if repo.starCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                        Text("\(repo.starCount)").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                ShimmerView().frame(height: 80).padding(.horizontal)
            }
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}
