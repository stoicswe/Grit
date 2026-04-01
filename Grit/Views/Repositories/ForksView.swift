import SwiftUI

struct ForksView: View {
    let projectID:      Int
    let parentRepoName: String

    @StateObject private var viewModel = ForksViewModel()
    @ObservedObject  private var starVM = StarredReposViewModel.shared
    @EnvironmentObject var navState: AppNavigationState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.forks.isEmpty {
                    loadingSkeleton
                } else if viewModel.forks.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    forksList
                }
            }
            .navigationTitle("Forks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.load(projectID: projectID, refresh: true)
                await starVM.loadIfNeeded()
            }
            .refreshable { await viewModel.load(projectID: projectID, refresh: true) }
            .navigationDestination(for: Repository.self) { repo in
                RepositoryDetailView(repository: repo)
                    .environmentObject(navState)
            }
        }
    }

    // MARK: - Forks List

    private var forksList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(viewModel.forks) { fork in
                    NavigationLink(value: fork) {
                        forkRow(fork)
                    }
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
                let count = viewModel.forks.count
                Text("\(count)\(viewModel.hasMore ? "+" : "") fork\(count == 1 ? "" : "s") of \(parentRepoName)")
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Fork Row

    private func forkRow(_ fork: Repository) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                Image(systemName: fork.visibility == "private" ? "lock.fill" : "tuningfork")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(fork.nameWithNamespace)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if let desc = fork.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    VisibilityBadge(visibility: fork.visibility)

                    if fork.starCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star")
                                .font(.system(size: 10))
                            Text("\(fork.starCount)")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }

                    if let date = fork.lastActivityAt {
                        Text("·").foregroundStyle(.quaternary)
                        Text(date.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Star indicator
            if starVM.isStarred(fork.id) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Forks",
            systemImage: "tuningfork",
            description: Text("\(parentRepoName) has not been forked yet.")
        )
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 11).frame(maxWidth: 200)
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
