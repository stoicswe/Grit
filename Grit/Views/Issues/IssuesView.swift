import SwiftUI

struct IssuesView: View {
    let projectID:   Int
    let repoName:    String

    @StateObject private var viewModel = IssuesViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.issues.isEmpty {
                    loadingSkeleton
                } else if viewModel.issues.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    issuesList
                }
            }
            .navigationTitle("Issues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    statePicker
                }
            }
            .task { await viewModel.load(projectID: projectID, refresh: true) }
            .refreshable { await viewModel.load(projectID: projectID, refresh: true) }
            .onChange(of: viewModel.stateFilter) { _, _ in
                Task { await viewModel.load(projectID: projectID, refresh: true) }
            }
            .navigationDestination(for: GitLabIssue.self) { issue in
                IssueDetailView(issue: issue, projectID: projectID)
            }
        }
    }

    // MARK: - State Picker

    private var statePicker: some View {
        Menu {
            ForEach(IssuesViewModel.IssueState.allCases, id: \.self) { state in
                Button {
                    viewModel.stateFilter = state
                } label: {
                    HStack {
                        Text(state.label)
                        if viewModel.stateFilter == state {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.stateFilter.label)
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.tint)
        }
    }

    // MARK: - Issues List

    private var issuesList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(viewModel.issues) { issue in
                    NavigationLink(value: issue) {
                        IssueRowView(issue: issue)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if viewModel.hasMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .onAppear {
                            Task { await viewModel.load(projectID: projectID) }
                        }
                }
            } header: {
                let count = viewModel.issues.count
                let hasMore = viewModel.hasMore
                Text("\(count)\(hasMore ? "+" : "") \(viewModel.stateFilter.label.lowercased()) issue\(count == 1 ? "" : "s")")
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No \(viewModel.stateFilter.label) Issues",
            systemImage: viewModel.stateFilter == .closed
                ? "checkmark.circle"
                : "exclamationmark.circle",
            description: Text(
                viewModel.stateFilter == .opened
                    ? "This repository has no open issues."
                    : "No issues match this filter."
            )
        )
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        List {
            ForEach(0..<8, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    ShimmerView()
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 11).frame(maxWidth: 220)
                        ShimmerView().frame(height: 10).frame(maxWidth: 140)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .allowsHitTesting(false)
    }
}

// MARK: - Issue Row

struct IssueRowView: View {
    let issue: GitLabIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {

                // State indicator dot
                Circle()
                    .fill(issue.isOpen ? Color.green : Color.purple)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 5) {

                    // Title
                    Text(issue.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Meta row
                    HStack(spacing: 8) {
                        Text("#\(issue.iid)")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)

                        Text(issue.author.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("·").foregroundStyle(.quaternary)

                        Text(issue.updatedAt.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    // Labels + comment count
                    if !issue.labels.isEmpty || issue.userNotesCount > 0 {
                        HStack(spacing: 6) {
                            ForEach(issue.labels.prefix(3), id: \.self) { label in
                                labelChip(label)
                            }
                            if issue.labels.count > 3 {
                                Text("+\(issue.labels.count - 3)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if issue.userNotesCount > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "bubble.right")
                                        .font(.system(size: 10))
                                    Text("\(issue.userNotesCount)")
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(.tint)
    }
}
