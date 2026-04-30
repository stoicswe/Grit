import SwiftUI

struct BranchListView: View {
    let branches: [Branch]
    let projectID: Int
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            if isLoading && branches.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        ShimmerView()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            ShimmerView().frame(height: 14).frame(maxWidth: 200)
                            ShimmerView().frame(height: 11).frame(maxWidth: 140)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .transition(.opacity)
            } else if branches.isEmpty {
                ContentUnavailableView("No branches", systemImage: "arrow.triangle.branch")
            } else {
                ForEach(branches) { branch in
                    NavigationLink(value: BranchNavigation(projectID: projectID, branch: branch)) {
                        BranchRowView(branch: branch)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: branches.isEmpty)
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
