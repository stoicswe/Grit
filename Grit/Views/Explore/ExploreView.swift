import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var viewModel = ExploreViewModel()
    @ObservedObject private var starVM = StarredReposViewModel.shared

    @State private var searchText = ""
    @State private var isSearchActive = false

    var body: some View {
        NavigationStack {
            Group {
                if isSearchActive && !searchText.isEmpty {
                    searchResultsList
                } else {
                    trendingList
                }
            }
            .navigationTitle("Explore")
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                prompt: "Search all of GitLab"
            )
            .onChange(of: searchText) { _, query in viewModel.search(query: query) }
            .task {
                await viewModel.loadTrending(refresh: true)
                await starVM.loadIfNeeded()
            }
            .refreshable { await viewModel.loadTrending(refresh: true) }
            .navigationDestination(for: Repository.self) { repo in
                RepositoryDetailView(repository: repo)
                    .environmentObject(navState)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(ExploreSort.allCases) { option in
                Button {
                    Task { await viewModel.changeSort(option) }
                } label: {
                    Label(
                        option.label,
                        systemImage: option.icon
                    )
                    if viewModel.sort == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }

    // MARK: - Trending

    private var trendingList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(viewModel.projects) { repo in
                    NavigationLink(value: repo) {
                        RepositoryRowView(
                            repo: repo,
                            isStarred: starVM.isStarred(repo.id),
                            onToggleStar: { Task { await starVM.toggleStar(repo: repo) } }
                        )
                    }
                    .listRowBackground(Color.clear)
                }

                if viewModel.hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onAppear {
                        Task { await viewModel.loadTrending() }
                    }
                }
            } header: {
                if !viewModel.projects.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.sort.icon)
                        Text("Sorted by \(viewModel.sort.label.lowercased())")
                        Spacer()
                        if viewModel.isBackgroundRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: viewModel.isBackgroundRefreshing)
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading && viewModel.projects.isEmpty {
                loadingOverlay
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            if viewModel.isSearching {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if viewModel.searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(viewModel.searchResults) { repo in
                        NavigationLink(value: repo) {
                            RepositoryRowView(
                                repo: repo,
                                isStarred: starVM.isStarred(repo.id),
                                onToggleStar: { Task { await starVM.toggleStar(repo: repo) } }
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("\(viewModel.searchResults.count) results")
                        .textCase(nil)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Loading Skeleton

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 11).frame(maxWidth: 200)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
