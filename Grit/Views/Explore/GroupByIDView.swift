import SwiftUI

/// A transitional view shown when navigating to a group from a repository's
/// namespace. It resolves the partial `Repository.Namespace` into a full
/// `GitLabGroup` (via the API), then hands off to `GroupDetailView`.
struct GroupByIDView: View {
    let namespace: Repository.Namespace

    @EnvironmentObject var navState: AppNavigationState
    @State private var group:     GitLabGroup?
    @State private var isLoading  = true
    @State private var error:     String?

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    var body: some View {
        Group {
            if let group {
                GroupDetailView(group: group, repoOrderBy: "last_activity_at")
                    .environmentObject(navState)
            } else if isLoading {
                loadingView
            } else if let error {
                errorView(error)
            }
        }
        .navigationTitle(namespace.name)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    // MARK: - Load

    private func load() async {
        guard let token = auth.accessToken else {
            error     = "Not authenticated."
            isLoading = false
            return
        }
        isLoading = true
        error     = nil
        do {
            group = try await api.fetchGroup(
                id:      namespace.id,
                baseURL: auth.baseURL,
                token:   token
            )
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Loading skeleton

    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 20) {
                ShimmerView()
                    .frame(height: 180)
                    .padding(.horizontal)
                HStack(spacing: 12) {
                    ShimmerView().frame(height: 72)
                    ShimmerView().frame(height: 72)
                }
                .padding(.horizontal)
                HStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(spacing: 6) {
                            ShimmerView().frame(width: 48, height: 48).clipShape(Circle())
                            ShimmerView().frame(width: 52, height: 9).clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load Group", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.bordered)
        }
    }
}
