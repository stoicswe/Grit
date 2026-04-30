import SwiftUI

struct StarredReposView: View {
    @ObservedObject private var starVM = StarredReposViewModel.shared

    var body: some View {
        List {
            if let error = starVM.error {
                Section {
                    ErrorBanner(message: error) { starVM.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if starVM.isLoading && starVM.repos.isEmpty {
                // Shimmer skeleton while the initial load is in-flight.
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 12) {
                            ShimmerView()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 6) {
                                ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                                ShimmerView().frame(height: 11).frame(maxWidth: 200)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

            } else if starVM.repos.isEmpty {
                ContentUnavailableView {
                    Label("No Starred Repositories", systemImage: "star.slash")
                } description: {
                    Text("Repositories you star will appear here.")
                }

            } else {
                // ── My Repositories ──────────────────────────────────────────
                // Repos in the user's own personal namespace that they've starred.
                if !starVM.myRepos.isEmpty {
                    Section {
                        ForEach(starVM.myRepos) { repo in
                            NavigationLink(value: repo) {
                                RepositoryRowView(
                                    repo: repo,
                                    isStarred: true,
                                    onToggleStar: { Task { await starVM.toggleStar(repo: repo) } }
                                )
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        starSectionHeader(
                            title: "My Repositories",
                            icon:  "person.fill",
                            count: starVM.myRepos.count
                        )
                    }
                }

                // ── Public ───────────────────────────────────────────────────
                // Other users' repos, group projects, etc. that the user has starred.
                if !starVM.publicRepos.isEmpty {
                    Section {
                        ForEach(starVM.publicRepos) { repo in
                            NavigationLink(value: repo) {
                                RepositoryRowView(
                                    repo: repo,
                                    isStarred: true,
                                    onToggleStar: { Task { await starVM.toggleStar(repo: repo) } }
                                )
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        starSectionHeader(
                            title: "Public",
                            icon:  "globe",
                            count: starVM.publicRepos.count
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: starVM.repos.map(\.id))
        .navigationTitle("Starred")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await starVM.load() }
        .task { await starVM.loadIfNeeded() }
        .task { await starVM.backgroundRefresh() }
        .onAppear {
            if starVM.error != nil { starVM.error = nil }
        }
    }

    // MARK: - Section header

    private func starSectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
            Spacer()
            Text("\(count)")
            if starVM.isBackgroundRefreshing {
                ProgressView()
                    .scaleEffect(0.55)
                    .tint(.secondary)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: starVM.isBackgroundRefreshing)
        .textCase(nil)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
