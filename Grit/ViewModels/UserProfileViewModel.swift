import Foundation
import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var user: GitLabUser?
    @Published var repos: [Repository] = []
    @Published var isFollowing: Bool = false
    @Published var isLoading: Bool = false
    @Published var isTogglingFollow: Bool = false
    @Published var error: String? = nil

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(userID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let userTask  = api.fetchUser(id: userID, baseURL: auth.baseURL, token: token)
            async let reposTask = api.fetchUserProjects(userID: userID, baseURL: auth.baseURL, token: token)
            let (fetchedUser, fetchedRepos) = try await (userTask, reposTask)
            user        = fetchedUser
            repos       = fetchedRepos
            isFollowing = fetchedUser.isFollowing ?? false
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleFollow(userID: Int) async {
        guard let token = auth.accessToken else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let wasFollowing = isFollowing
        isFollowing.toggle() // optimistic
        do {
            if wasFollowing {
                _ = try await api.unfollowUser(userID: userID, baseURL: auth.baseURL, token: token)
            } else {
                _ = try await api.followUser(userID: userID, baseURL: auth.baseURL, token: token)
            }
        } catch {
            isFollowing = wasFollowing // rollback
            self.error = error.localizedDescription
        }
    }
}
