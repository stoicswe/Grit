import SwiftUI

struct CommitListView: View {
    let commits: [Commit]
    let projectID: Int
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            if isLoading && commits.isEmpty {
                ProgressView().padding()
            } else if commits.isEmpty {
                ContentUnavailableView("No commits", systemImage: "clock.arrow.circlepath")
            } else {
                ForEach(commits) { commit in
                    NavigationLink(value: CommitNavigation(projectID: projectID, commit: commit)) {
                        CommitRowView(commit: commit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: CommitNavigation.self) { nav in
            CommitDetailView(commit: nav.commit, projectID: nav.projectID)
        }
    }
}

struct CommitNavigation: Hashable {
    let projectID: Int
    let commit: Commit

    func hash(into hasher: inout Hasher) { hasher.combine(commit.id) }
    static func == (lhs: CommitNavigation, rhs: CommitNavigation) -> Bool {
        lhs.commit.id == rhs.commit.id
    }
}

struct CommitRowView: View {
    let commit: Commit

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                // Avatar placeholder based on author name
                AvatarView(urlString: nil, name: commit.authorName, size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9))
                            Text(commit.authorName)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(commit.authoredDate.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    if let stats = commit.stats {
                        HStack(spacing: 8) {
                            if stats.additions > 0 {
                                Text("+\(stats.additions)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            if stats.deletions > 0 {
                                Text("-\(stats.deletions)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(commit.shortSHA)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}
