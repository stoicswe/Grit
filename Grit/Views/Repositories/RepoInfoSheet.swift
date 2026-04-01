import SwiftUI

// MARK: - Center-popup overlay wrapper

/// Presents a floating, centred glass popup over the current screen.
/// Tap the dimmed background or the × button to dismiss.
struct RepoInfoOverlay: View {
    let repository:  Repository
    let projectID:   Int
    @Binding var isPresented: Bool

    @StateObject private var viewModel = RepoInfoViewModel()
    @State private var showAllContributors = false

    var body: some View {
        ZStack {
            // ── Dim layer ──────────────────────────────────────────────────
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isPresented = false
                    }
                }
                .transition(.opacity)

            // ── Floating card ──────────────────────────────────────────────
            RepoInfoCard(
                repository:           repository,
                viewModel:            viewModel,
                showAllContributors:  $showAllContributors,
                onDismiss: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isPresented = false
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
            .transition(
                .asymmetric(
                    insertion:  .scale(scale: 0.88).combined(with: .opacity),
                    removal:    .scale(scale: 0.92).combined(with: .opacity)
                )
            )
        }
        .task {
            await viewModel.load(
                projectID: projectID,
                ref: repository.defaultBranch ?? "main"
            )
        }
        .sheet(isPresented: $showAllContributors) {
            ContributorsSheet(contributors: viewModel.contributors)
        }
    }
}

// MARK: - Card

private struct RepoInfoCard: View {
    let repository:          Repository
    @ObservedObject var viewModel: RepoInfoViewModel
    @Binding var showAllContributors: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar (title + close) ────────────────────────────────────
            cardTopBar

            Divider().opacity(0.4)

            // ── Scrollable body ────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    contributorsSection
                    if let desc = repository.description,
                       !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        descriptionSection(desc)
                    }
                    readmeSection
                }
                .padding(20)
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

    // MARK: Top bar

    private var cardTopBar: some View {
        HStack(spacing: 12) {
            // Repo icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    )
                Image(systemName: repository.visibility == "private" ? "lock.fill" : "folder.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }

            // Namespace + name
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.nameWithNamespace)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                VisibilityBadge(visibility: repository.visibility)
            }

            Spacer()

            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "Details")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 10
            ) {
                if let branch = repository.defaultBranch {
                    metaChip(icon: "arrow.triangle.branch", label: branch)
                }
                if let activity = repository.lastActivityAt {
                    metaChip(icon: "clock", label: "Active \(activity.relativeFormatted)")
                }
                metaChip(icon: "star", label: "\(repository.starCount) stars")
                metaChip(icon: "tuningfork", label: "\(repository.forksCount) forks")
                if let issues = repository.openIssuesCount {
                    metaChip(icon: "exclamationmark.circle", label: "\(issues) issues")
                }
                if let stats = repository.statistics,
                   let commits = stats.commitCount {
                    metaChip(icon: "clock.arrow.circlepath", label: "\(commits) commits")
                }
                if let stats = repository.statistics,
                   let bytes = stats.repositorySize {
                    metaChip(icon: "internaldrive", label: formatBytes(bytes))
                }
            }
        }
    }

    private func metaChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }

    // MARK: Contributors

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(
                title: "Contributors",
                trailing: viewModel.contributors.isEmpty ? nil : "\(viewModel.contributors.count)"
            )

            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Loading…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if viewModel.contributors.isEmpty {
                Text("No contributor data available")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                // Top-5 avatar strip
                let preview = viewModel.contributors.prefix(5)
                Button {
                    showAllContributors = true
                } label: {
                    HStack(spacing: 12) {
                        // Overlapping avatars via negative spacing — SwiftUI handles
                        // the layout bounds correctly so circles never bleed into text.
                        HStack(spacing: -10) {
                            ForEach(Array(preview.enumerated()), id: \.element.id) { idx, contrib in
                                AvatarView(urlString: nil, name: contrib.name, size: 30)
                                    .overlay(
                                        Circle().strokeBorder(.ultraThinMaterial, lineWidth: 1.5)
                                    )
                                    .zIndex(Double(preview.count - idx))
                            }
                        }

                        // Summary label — takes remaining space so chevron stays right
                        VStack(alignment: .leading, spacing: 2) {
                            let top = viewModel.contributors.first
                            Text(top?.name ?? "")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if viewModel.contributors.count > 1 {
                                Text("+ \(viewModel.contributors.count - 1) more")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Description

    private func descriptionSection(_ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "Description")
            MarkdownRendererView(source: desc)
        }
    }

    // MARK: README

    @ViewBuilder
    private var readmeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "README")

            if viewModel.isLoading {
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerView().frame(height: 12).frame(maxWidth: .infinity)
                    }
                }
            } else if let readme = viewModel.readmeContent {
                MarkdownRendererView(source: readme)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                    Text("No README found")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Contributors full sheet

struct ContributorsSheet: View {
    let contributors: [GitLabContributor]
    @Environment(\.dismiss) private var dismiss

    @State private var resolvedUser: GitLabUser? = nil
    @State private var isResolving: Bool = false
    @State private var showProfile: Bool = false

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(contributors.enumerated()), id: \.element.id) { idx, contrib in
                    Button {
                        Task { await resolveAndShowProfile(for: contrib) }
                    } label: {
                        HStack(spacing: 12) {
                            // Rank badge
                            Text("\(idx + 1)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .frame(width: 22, alignment: .trailing)

                            AvatarView(urlString: nil, name: contrib.name, size: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(contrib.name)
                                    .font(.system(size: 14, weight: .medium))
                                Text(contrib.email)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                HStack(spacing: 3) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 10))
                                    Text("\(contrib.commits)")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.tint)

                                HStack(spacing: 4) {
                                    Text("+\(contrib.additions)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.green)
                                    Text("−\(contrib.deletions)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                }
                            }

                            if isResolving {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Contributors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if showProfile, let user = resolvedUser {
                    UserProfileOverlay(
                        userID: user.id,
                        username: user.username,
                        avatarURL: user.avatarURL,
                        isPresented: $showProfile
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    private func resolveAndShowProfile(for contrib: GitLabContributor) async {
        guard let token = auth.accessToken else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            let results = try await api.searchUsers(query: contrib.name, baseURL: auth.baseURL, token: token)
            if let first = results.first {
                resolvedUser = first
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    showProfile = true
                }
            }
        } catch {
            // Silently ignore — user lookup is best-effort
        }
    }
}
