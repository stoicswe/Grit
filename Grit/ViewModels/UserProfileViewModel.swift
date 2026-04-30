import Foundation
import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var user:                GitLabUser?
    @Published var repos:               [Repository]  = []
    @Published var groups:              [GitLabGroup] = []
    @Published var followers:           [GitLabUser]  = []
    @Published var isFollowing:         Bool          = false
    @Published var isLoading:           Bool          = false
    @Published var isBackgroundRefreshing = false
    @Published var isTogglingFollow:    Bool          = false
    @Published var error:               String?       = nil

    private var backgroundTask: Task<Void, Never>?
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Cache

    private struct CacheEntry: Codable {
        let user:      GitLabUser
        let repos:     [Repository]
        let groups:    [GitLabGroup]
        let followers: [GitLabUser]
        let savedAt:   Date

        var isStale: Bool { Date().timeIntervalSince(savedAt) > 10 * 60 }
    }

    private func cacheKey(for userID: Int) -> String {
        let host = URL(string: auth.baseURL)?.host ?? auth.baseURL
        return "user_profile_cache_\(userID)_\(host)"
    }

    private func readCache(for userID: Int) -> CacheEntry? {
        guard
            let data  = UserDefaults.standard.data(forKey: cacheKey(for: userID)),
            let entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        else { return nil }
        return entry
    }

    private func writeCache(_ entry: CacheEntry, for userID: Int) {
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey(for: userID))
        }
    }

    // MARK: - Load

    func load(userID: Int) async {
        guard let token = auth.accessToken else { return }

        if let cached = readCache(for: userID) {
            user        = cached.user
            repos       = cached.repos
            groups      = cached.groups
            followers   = cached.followers
            isFollowing = cached.user.isFollowing ?? false
            scheduleBackgroundRefresh(userID: userID, token: token)
            return
        }

        isLoading = true
        error     = nil
        defer { isLoading = false }
        await fetchAndPublish(userID: userID, token: token)
    }

    // MARK: - Background refresh

    private func scheduleBackgroundRefresh(userID: Int, token: String) {
        backgroundTask?.cancel()
        backgroundTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isBackgroundRefreshing = true
            defer { isBackgroundRefreshing = false }
            await fetchAndPublish(userID: userID, token: token)
        }
    }

    // MARK: - Fetch

    private func fetchAndPublish(userID: Int, token: String) async {
        let baseURL = auth.baseURL
        do {
            // Fetch user, repos, and followers concurrently (all throwing).
            async let userTask      = api.fetchUser(id: userID, baseURL: baseURL, token: token)
            async let reposTask     = api.fetchUserProjects(userID: userID, baseURL: baseURL, token: token)
            async let followersTask = api.fetchUserFollowers(userID: userID, baseURL: baseURL, token: token)
            let (fetchedUser, fetchedRepos, fetchedFollowers) =
                try await (userTask, reposTask, followersTask)

            // Groups are best-effort (non-throwing) — fetch after the main trio resolves.
            let fetchedGroups = await api.fetchUserGroupMemberships(
                userID: userID, baseURL: baseURL, token: token)

            user        = fetchedUser
            repos       = fetchedRepos
            groups      = fetchedGroups
            followers   = fetchedFollowers
            isFollowing = fetchedUser.isFollowing ?? false

            let entry = CacheEntry(user: fetchedUser, repos: fetchedRepos,
                                   groups: fetchedGroups, followers: fetchedFollowers,
                                   savedAt: Date())
            writeCache(entry, for: userID)
        } catch {
            if user == nil { self.error = error.localizedDescription }
        }
    }

    // MARK: - Follow

    func toggleFollow(userID: Int) async {
        guard let token = auth.accessToken else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let wasFollowing = isFollowing
        isFollowing.toggle()
        do {
            if wasFollowing {
                _ = try await api.unfollowUser(userID: userID, baseURL: auth.baseURL, token: token)
            } else {
                _ = try await api.followUser(userID: userID, baseURL: auth.baseURL, token: token)
            }
        } catch {
            isFollowing = wasFollowing
            self.error  = error.localizedDescription
        }
    }
}
