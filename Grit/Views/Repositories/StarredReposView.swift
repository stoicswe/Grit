import SwiftUI

struct StarredReposView: View {
    @EnvironmentObject var navState: AppNavigationState
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
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                .listRowBackground(Color.clear)
            } else if starVM.repos.isEmpty {
                ContentUnavailableView {
                    Label("No Starred Repositories", systemImage: "star.slash")
                } description: {
                    Text("Repositories you star will appear here.")
                }
            } else {
                Section {
                    ForEach(starVM.repos) { repo in
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
                    Text("\(starVM.repos.count) starred")
                        .textCase(nil)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Starred")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await starVM.load() }
        .task { await starVM.loadIfNeeded() }
        // Own destination so value-links here don't depend on the parent NavigationStack
        .navigationDestination(for: Repository.self) { repo in
            RepositoryDetailView(repository: repo)
                .environmentObject(navState)
        }
        .onAppear {
            // Clear any stale error from a previous toggle so it doesn't show up
            // as a phantom banner every time the user reopens this list.
            if starVM.error != nil { starVM.error = nil }
        }
    }
}
