import SwiftUI

struct BranchListView: View {
    let branches: [Branch]
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            if isLoading && branches.isEmpty {
                ProgressView().padding()
            } else if branches.isEmpty {
                ContentUnavailableView("No branches", systemImage: "arrow.triangle.branch")
            } else {
                ForEach(branches) { branch in
                    BranchRowView(branch: branch)
                }
            }
        }
    }
}

struct BranchRowView: View {
    let branch: Branch

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(branch.name)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)

                        if branch.isDefault {
                            Text("default")
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        if branch.protected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                        if branch.merged {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                    }

                    if let commit = branch.commit {
                        HStack(spacing: 4) {
                            Text(commit.shortId)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(commit.title)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let date = commit.committedDate {
                            Text(date.relativeFormatted)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}
