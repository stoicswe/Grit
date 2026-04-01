import Foundation
import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var user:               GitLabUser?
    @Published var contributionStats:  ContributionStats?
    @Published var ownedRepositories:  [Repository]   = []
    @Published var followers:          [GitLabUser]   = []
    @Published var isLoading           = false
    @Published var isBackgroundRefreshing = false
    @Published var error:              String?

    private var backgroundTask: Task<Void, Never>?
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Cache

    private struct CacheEntry: Codable {
        let user:      GitLabUser
        let repos:     [Repository]
        let followers: [GitLabUser]
        let events:    [ContributionEvent]   // stored so ContributionStats can be rebuilt
        let savedAt:   Date

        var isStale: Bool { Date().timeIntervalSince(savedAt) > 10 * 60 }
    }

    private var cacheKey: String {
        let host = URL(string: auth.baseURL)?.host ?? auth.baseURL
        return "own_profile_cache_\(host)"
    }

    private func readCache() -> CacheEntry? {
        guard
            let data  = UserDefaults.standard.data(forKey: cacheKey),
            let entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        else { return nil }
        return entry
    }

    private func writeCache(user: GitLabUser, repos: [Repository],
                            followers: [GitLabUser], events: [ContributionEvent]) {
        let entry = CacheEntry(user: user, repos: repos,
                               followers: followers, events: events, savedAt: Date())
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Load

    /// Call on every appearance.
    /// • Already have data → silent background refresh only (no shimmer)
    /// • Cache hit         → populate immediately + silent background refresh
    /// • Cold start        → full shimmer load
    func load() async {
        guard let token = auth.accessToken else { return }

        if user != nil {
            // Revisiting the tab — just refresh silently
            scheduleBackgroundRefresh(token: token)
            return
        }

        if let cached = readCache() {
            user             = cached.user
            ownedRepositories = cached.repos
            followers        = cached.followers
            contributionStats = ContributionStats.build(from: cached.events)
            scheduleBackgroundRefresh(token: token)
            return
        }

        // No data at all: full shimmer
        isLoading = true
        error     = nil
        defer { isLoading = false }
        await fetchAndPublish(token: token)
    }

    // MARK: - Background refresh

    private func scheduleBackgroundRefresh(token: String) {
        backgroundTask?.cancel()
        backgroundTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isBackgroundRefreshing = true
            defer { isBackgroundRefreshing = false }
            await fetchAndPublish(token: token)
        }
    }

    // MARK: - Fetch

    private func fetchAndPublish(token: String) async {
        let baseURL  = auth.baseURL
        let username = auth.currentUser?.username ?? user?.username ?? ""
        do {
            async let userTask      = api.fetchCurrentUser(baseURL: baseURL, token: token)
            async let reposTask     = api.fetchUserRepositories(baseURL: baseURL, token: token)
            async let eventsTask    = fetchAllEvents(username: username,
                                                     baseURL: baseURL, token: token)
            let (fetchedUser, repos, events) = try await (userTask, reposTask, eventsTask)

            // Followers fetched after we have the user ID
            let fetchedFollowers = (try? await api.fetchUserFollowers(
                userID: fetchedUser.id, baseURL: baseURL, token: token
            )) ?? followers

            user              = fetchedUser
            ownedRepositories = repos
            followers         = fetchedFollowers
            contributionStats = ContributionStats.build(from: events)
            writeCache(user: fetchedUser, repos: repos,
                       followers: fetchedFollowers, events: events)
        } catch {
            // Only surface the error on a cold load; background failures are silent
            if user == nil { self.error = error.localizedDescription }
        }
    }

    private func fetchAllEvents(username: String,
                                 baseURL: String,
                                 token: String) async throws -> [ContributionEvent] {
        guard !username.isEmpty else { return [] }
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return try await api.fetchUserEvents(username: username,
                                             baseURL: baseURL,
                                             token: token,
                                             after: oneYearAgo)
    }
}
