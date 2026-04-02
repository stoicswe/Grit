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
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                .listRowBackground(Color.clear)
            } else if watchVM.repos.isEmpty {
                ContentUnavailableView {
                    Label("No Watched Repositories", systemImage: "bell.slash")
                } description: {
                    Text("Repositories you watch will appear here.")
                }
            } else {
                Section {
                    ForEach(watchVM.repos) { repo in
                        NavigationLink(value: repo) {
                            RepositoryRowView(repo: repo)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("\(watchVM.repos.count) watched")
                        .textCase(nil)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Watching")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await watchVM.load() }
        .task { await watchVM.loadIfNeeded() }
    }
}
