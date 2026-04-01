import SwiftUI

// MARK: - Overlay wrapper

struct UserProfileOverlay: View {
    let userID: Int
    let username: String
    let avatarURL: String?
    @Binding var isPresented: Bool

    @StateObject private var viewModel = UserProfileViewModel()
    private var currentUserID: Int? { AuthenticationService.shared.currentUser?.id }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isPresented = false
                    }
                }

            UserProfileCard(
                viewModel:     viewModel,
                currentUserID: currentUserID,
                onDismiss: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isPresented = false
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.88).combined(with: .opacity),
                removal:   .scale(scale: 0.92).combined(with: .opacity)
            ))
        }
        .task { await viewModel.load(userID: userID) }
    }
}

// MARK: - Card

private struct UserProfileCard: View {
    @ObservedObject var viewModel: UserProfileViewModel
    let currentUserID: Int?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Close button row
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading && viewModel.user == nil {
                        loadingShimmer
                    } else if let user = viewModel.user {
                        profileHeader(user)
                        if let error = viewModel.error {
                            ErrorBanner(message: error).padding(.horizontal)
                        }
                        statsRow(user)
                        if currentUserID != user.id {
                            followButton(userID: user.id)
                        }
                        if !viewModel.repos.isEmpty {
                            reposSection
                        }
                        openInBrowserButton(user)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 32, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Header

    private func profileHeader(_ user: GitLabUser) -> some View {
        VStack(spacing: 10) {
            AvatarView(urlString: user.avatarURL, name: user.name, size: 72)
                .shadow(color: .accentColor.opacity(0.28), radius: 12)

            VStack(spacing: 3) {
                Text(user.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let location = user.location, !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle").font(.caption)
                    Text(location).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stats

    private func statsRow(_ user: GitLabUser) -> some View {
        HStack(spacing: 10) {
            statChip(icon: "folder.fill",         value: "\(viewModel.repos.count)", label: "Repos")
            statChip(icon: "person.2.fill",       value: "\(user.followers ?? 0)",   label: "Followers")
            statChip(icon: "figure.walk.arrival", value: "\(user.following ?? 0)",   label: "Following")
        }
    }

    private func statChip(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Follow Button

    private func followButton(userID: Int) -> some View {
        Button {
            Task { await viewModel.toggleFollow(userID: userID) }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isTogglingFollow {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: viewModel.isFollowing ? "person.fill.checkmark" : "person.badge.plus")
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

    // MARK: Repos

    private var reposSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "Public Repositories", trailing: "\(viewModel.repos.count)")
            VStack(spacing: 6) {
                ForEach(viewModel.repos.prefix(5)) { repo in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(repo.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if let desc = repo.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if repo.starCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").font(.system(size: 9))
                                Text("\(repo.starCount)").font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: Browser Link

    private func openInBrowserButton(_ user: GitLabUser) -> some View {
        Link(destination: URL(string: user.webURL) ?? URL(string: "https://gitlab.com")!) {
            HStack(spacing: 6) {
                Image(systemName: "safari").font(.system(size: 13))
                Text("Open Profile in Browser").font(.system(size: 14))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.tint)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Loading shimmer

    private var loadingShimmer: some View {
        VStack(spacing: 16) {
            Circle().fill(.quaternary).frame(width: 72, height: 72)
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            ShimmerView().frame(height: 16).frame(maxWidth: 160)
            ShimmerView().frame(height: 12).frame(maxWidth: 100)
            ShimmerView().frame(height: 50).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
