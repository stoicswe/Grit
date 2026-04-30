import SwiftUI

/// Embedded tab that shows repository metadata and a Markdown-rendered README.
/// Mirrors the content of `RepoInfoCard` but without the build-status section,
/// and is designed to live inline in the `RepositoryDetailView` tab area.
struct RepoInfoTabView: View {
    let repository: Repository
    let branch: String

    @StateObject private var vm = RepoInfoViewModel()
    @State private var showAllContributors = false

    /// Base URL for resolving relative image paths in the README.
    /// Uses `webURL` (e.g. https://gitlab.com/group/project) which is already
    /// URL-safe, unlike `nameWithNamespace` which contains display-name spaces.
    private var imageBaseURL: String {
        let base = repository.webURL.hasSuffix("/")
            ? String(repository.webURL.dropLast())
            : repository.webURL
        return "\(base)/-/raw/\(branch)/"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            metadataSection
            topicsSection
            contributorsSection
            readmeSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await vm.load(projectID: repository.id, ref: branch)
        }
        .sheet(isPresented: $showAllContributors) {
            ContributorsSheet(contributors: vm.contributors)
        }
    }

    // MARK: - Metadata


    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "Details")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 10
            ) {
                if let defaultBranch = repository.defaultBranch {
                    metaChip(icon: "arrow.triangle.branch", label: defaultBranch)
                }
                if let activity = repository.lastActivityAt {
                    metaChip(icon: "clock", label: "Active \(activity.relativeFormatted)")
                }
                metaChip(icon: "star", label: "\(repository.starCount) stars")
                metaChip(icon: "tuningfork", label: "\(repository.forksCount) forks")
                if let issues = repository.openIssuesCount {
                    metaChip(icon: "exclamationmark.circle", label: "\(issues) issues")
                }
                if let stats = repository.statistics, let commits = stats.commitCount {
                    metaChip(icon: "clock.arrow.circlepath", label: "\(commits) commits")
                }
                if let stats = repository.statistics, let bytes = stats.repositorySize {
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
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }

    // MARK: - Topics

    @ViewBuilder
    private var topicsSection: some View {
        if let topics = repository.topics, !topics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader(title: "Topics")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(topics, id: \.self) { topic in
                            Text(topic)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Contributors

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(
                title: "Contributors",
                trailing: vm.contributors.isEmpty ? nil : "\(vm.contributors.count)"
            )

            if vm.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Loading…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if vm.contributors.isEmpty {
                Text("No contributor data available")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                let preview = vm.contributors.prefix(5)
                Button {
                    showAllContributors = true
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: -10) {
                            ForEach(Array(preview.enumerated()), id: \.element.id) { idx, contrib in
                                AvatarView(urlString: nil, name: contrib.name, size: 30)
                                    .overlay(Circle().strokeBorder(.ultraThinMaterial, lineWidth: 1.5))
                                    .zIndex(Double(preview.count - idx))
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            let top = vm.contributors.first
                            Text(top?.name ?? "")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if vm.contributors.count > 1 {
                                Text("+ \(vm.contributors.count - 1) more")
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
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - README

    @ViewBuilder
    private var readmeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "README")

            if vm.isLoading {
                VStack(spacing: 8) {
                    ShimmerView().frame(height: 26).frame(maxWidth: .infinity)
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                    }
                    ShimmerView().frame(height: 14).frame(maxWidth: 200, alignment: .leading)
                }
            } else if let readme = vm.readmeContent {
                MarkdownReaderView(source: readme, imageBaseURL: imageBaseURL)
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
