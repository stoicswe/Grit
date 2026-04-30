import SwiftUI

struct WatchingReposView: View {
    @ObservedObject private var watchVM = WatchingReposViewModel.shared

    var body: some View {
        List {
            if let error = watchVM.error {
                Section {
                    ErrorBanner(message: error) { watchVM.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if watchVM.isLoading && watchVM.repos.isEmpty {
                // Full-screen shimmer while the initial load is in-flight.
                Section {
                    ForEach(0..<4, id: \.self) { _ in shimmerRow }
                }
                .listRowBackground(Color.clear)

            } else if watchVM.repos.isEmpty {
                ContentUnavailableView {
                    Label("No Watched Repositories", systemImage: "bell.slash")
                } description: {
                    Text("Repositories you watch will appear here.")
                }

            } else {
                // ── My Repositories ──────────────────────────────────────────
                // Repos where the user has a membership role.
                if !watchVM.myRepos.isEmpty {
                    Section {
                        ForEach(watchVM.myRepos) { repo in
                            NavigationLink(value: repo) {
                                RepositoryRowView(repo: repo)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        watchSectionHeader(
                            title: "My Repositories",
                            icon:  "person.fill",
                            count: watchVM.myRepos.count
                        )
                    }
                }

                // ── Public ───────────────────────────────────────────────────
                // Repos watched from Explore where the user is not a member.
                if !watchVM.publicRepos.isEmpty {
                    Section {
                        ForEach(watchVM.publicRepos) { repo in
                            NavigationLink(value: repo) {
                                RepositoryRowView(repo: repo)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        watchSectionHeader(
                            title: "Public",
                            icon:  "globe",
                            count: watchVM.publicRepos.count
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.88),
                   value: watchVM.repos.map(\.id))
        .navigationTitle("Watching")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await watchVM.load() }
        .task { await watchVM.loadIfNeeded() }
    }

    // MARK: - Section header

    private func watchSectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
            Spacer()
            Text("\(count)")
        }
        .textCase(nil)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Shimmer row

    private var shimmerRow: some View {
        HStack(spacing: 12) {
            ShimmerView()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                ShimmerView().frame(height: 11).frame(maxWidth: 200)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .allowsHitTesting(false)
    }
}
