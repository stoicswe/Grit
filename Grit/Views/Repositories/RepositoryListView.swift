import SwiftUI

struct RepositoryListView: View {
    @Binding var showSearch: Bool
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var viewModel = RepositoryViewModel()
    @State private var inlineSearchText = ""
    @State private var isInlineSearchActive = false

    var body: some View {
        NavigationStack {
            Group {
                if isInlineSearchActive && !inlineSearchText.isEmpty {
                    searchResultsList
                } else {
                    repositoriesList
                }
            }
            .navigationTitle("Repositories")
            .searchable(
                text: $inlineSearchText,
                isPresented: $isInlineSearchActive,
                prompt: "Filter my repositories"
            )
            .onChange(of: inlineSearchText) { _, query in viewModel.search(query: query) }
            .task { await viewModel.loadRepositories(refresh: true) }
            .refreshable { await viewModel.loadRepositories(refresh: true) }
            .navigationDestination(for: Repository.self) { repo in
                RepositoryDetailView(repository: repo)
                    .environmentObject(navState)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        // Global search button
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }

                        // Context menu — no repo selected at this level
                        Menu {
                            Section("App") {
                                NavigationLink {
                                    SettingsView()
                                } label: {
                                    Label("Preferences", systemImage: "gearshape")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Repositories List

    private var repositoriesList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(viewModel.repositories) { repo in
                    NavigationLink(value: repo) {
                        RepositoryRowView(repo: repo)
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
                        Task { await viewModel.loadRepositories() }
                    }
                }
            } header: {
                if !viewModel.repositories.isEmpty {
                    Text("\(viewModel.repositories.count) repositories")
                        .textCase(nil)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading && viewModel.repositories.isEmpty {
                loadingOverlay
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            if viewModel.isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if viewModel.searchResults.isEmpty && !inlineSearchText.isEmpty {
                ContentUnavailableView.search(text: inlineSearchText)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.searchResults) { repo in
                    NavigationLink(value: repo) {
                        RepositoryRowView(repo: repo)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
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

// MARK: - Repository Row

struct RepositoryRowView: View {
    let repo: Repository

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                Image(systemName: repo.visibility == "private" ? "lock.fill" : "folder.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if repo.archived == true {
                        Text("archived")
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    VisibilityBadge(visibility: repo.visibility)

                    if repo.starCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 9))
                            Text("\(repo.starCount)").font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }

                    if let activity = repo.lastActivityAt {
                        Text(activity.relativeFormatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Date Extension

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
