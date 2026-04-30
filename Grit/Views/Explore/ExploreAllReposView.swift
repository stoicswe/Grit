import SwiftUI

// MARK: - View Model

@MainActor
private final class AllReposViewModel: ObservableObject {
    @Published var projects:  [Repository] = []
    @Published var isLoading  = false
    @Published var hasMore    = false
    @Published var error:     String?
    @Published var sort:      ExploreSort

    private var currentPage  = 1
    private var isPaginating = false
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    init(sort: ExploreSort) { self.sort = sort }

    func changeSort(_ newSort: ExploreSort) async {
        sort         = newSort
        projects     = []
        hasMore      = false
        isPaginating = false
        await load(refresh: true)
    }

    func load(refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }

        if refresh {
            currentPage  = 1
            isPaginating = false
        } else {
            guard !isPaginating, hasMore else { return }
            isPaginating = true
        }

        if refresh { isLoading = true }
        error = nil
        defer {
            withAnimation(.easeOut(duration: 0.25)) { isLoading = false }
            isPaginating = false
        }

        let page = currentPage
        do {
            let fetched = try await api.fetchExploreProjects(
                orderBy:       sort.rawValue,
                sortDirection: sort.sortDirection,
                baseURL:       auth.baseURL,
                token:         token,
                page:          page
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                if refresh { projects = fetched } else { projects.append(contentsOf: fetched) }
            }
            hasMore     = fetched.count == 25
            currentPage = page + 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View

struct ExploreAllReposView: View {
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var starVM = StarredReposViewModel.shared
    @StateObject private var viewModel: AllReposViewModel

    init(sort: ExploreSort) {
        _viewModel = StateObject(wrappedValue: AllReposViewModel(sort: sort))
    }

    var body: some View {
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
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .onAppear { Task { await viewModel.load() } }
                }
            } header: {
                if !viewModel.projects.isEmpty || viewModel.isLoading {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.sort.icon)
                        Text("Sorted by \(viewModel.sort.label.lowercased())")
                        Spacer()
                        if viewModel.isLoading && !viewModel.projects.isEmpty {
                            ProgressView().scaleEffect(0.6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.sort)
                    .textCase(nil)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.88),
                   value: viewModel.projects.map(\.id))
        .navigationTitle("Repositories")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ExploreSort.allCases) { option in
                        Button {
                            Task { await viewModel.changeSort(option) }
                        } label: {
                            Label(option.label, systemImage: option.icon)
                            if viewModel.sort == option { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.projects.isEmpty {
                loadingOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.28),
                   value: viewModel.isLoading && viewModel.projects.isEmpty)
        .task { await viewModel.load(refresh: true) }
        .refreshable { await viewModel.load(refresh: true) }
        .navigationDestination(for: Repository.self) { repo in
            RepositoryDetailView(repository: repo)
                .environmentObject(navState)
        }
        .navigationDestination(for: Repository.Namespace.self) { ns in
            GroupByIDView(namespace: ns)
                .environmentObject(navState)
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ForEach(0..<8, id: \.self) { _ in
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
