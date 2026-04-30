import SwiftUI

// MARK: - View Model

@MainActor
private final class PublicGroupsViewModel: ObservableObject {
    @Published var groups:    [GitLabGroup] = []
    @Published var isLoading  = false
    @Published var hasMore    = false
    @Published var error:     String?
    @Published var sort:      PublicGroupSort = .recentActivity

    private var currentPage  = 1
    private var isPaginating = false
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func changeSort(_ newSort: PublicGroupSort) async {
        sort         = newSort
        groups       = []
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
        defer { isLoading = false; isPaginating = false }

        let page = currentPage
        do {
            let fetched = try await api.fetchPublicGroups(
                orderBy:       sort.groupOrderBy,
                sortDirection: sort.sortDirection,
                baseURL:       auth.baseURL,
                token:         token,
                page:          page
            )

            if refresh { groups = fetched } else { groups.append(contentsOf: fetched) }
            hasMore     = fetched.count == 25
            currentPage = page + 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View

struct ExploreAllGroupsView: View {
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var viewModel = PublicGroupsViewModel()

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
                ForEach(viewModel.groups) { group in
                    NavigationLink(value: ExploreDestination.groupDetail(group)) {
                        GroupRowView(group: group)
                    }
                    .listRowBackground(Color.clear)
                }

                if viewModel.hasMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .onAppear { Task { await viewModel.load() } }
                }
            } header: {
                if !viewModel.groups.isEmpty || viewModel.isLoading {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.sort.icon)
                        Text("Sorted by \(viewModel.sort.label.lowercased())")
                        Spacer()
                        if viewModel.isLoading && !viewModel.groups.isEmpty {
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
        .navigationTitle("Public Groups")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(PublicGroupSort.allCases) { option in
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
            if viewModel.isLoading && viewModel.groups.isEmpty {
                loadingOverlay
            }
        }
        .task { await viewModel.load(refresh: true) }
        .refreshable { await viewModel.load(refresh: true) }
        .navigationDestination(for: ExploreDestination.self) { destination in
            if case .groupDetail(let group) = destination {
                GroupDetailView(group: group, repoOrderBy: viewModel.sort.repoOrderBy)
                    .environmentObject(navState)
            }
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10))
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

// MARK: - Group Row

struct GroupRowView: View {
    let group: GitLabGroup

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: group.avatarURL, name: group.name, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                if let desc = group.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(group.fullPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if let count = group.membersCount, count > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                            Text("\(count)")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
