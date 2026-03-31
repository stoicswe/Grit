import Foundation
import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var user: GitLabUser?
    @Published var contributionStats: ContributionStats?
    @Published var ownedRepositories: [Repository] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load() async {
        guard let token = auth.accessToken else { return }
        let baseURL = auth.baseURL
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let userTask = api.fetchCurrentUser(baseURL: baseURL, token: token)
            async let eventsTask = fetchAllEvents(baseURL: baseURL, token: token)
            async let reposTask = api.fetchUserRepositories(baseURL: baseURL, token: token)

            let (fetchedUser, events, repos) = try await (userTask, eventsTask, reposTask)
            user = fetchedUser
            contributionStats = ContributionStats.build(from: events)
            ownedRepositories = repos
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchAllEvents(baseURL: String, token: String) async throws -> [ContributionEvent] {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        guard let username = auth.currentUser?.username else { return [] }
        return try await api.fetchUserEvents(username: username, baseURL: baseURL, token: token, after: oneYearAgo)
    }
}
