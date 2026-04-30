import SwiftUI

// MARK: - Deep Link Handler

/// Parses incoming URLs (both `grit://` custom-scheme and `https://` links
/// matching the user's configured GitLab instance) and drives the app's
/// NavigationStacks to the appropriate destination.
///
/// **Supported URL patterns**
/// ```
/// grit://gitlab.com/namespace/repo           → RepositoryDetailView (Repos tab)
/// grit://gitlab.com/namespace/repo/-/…       → RepositoryDetailView (Repos tab)
/// grit://gitlab.com/group-name               → GroupDetailView      (Explore tab)
/// grit://gitlab.com/username                 → PublicProfileView    (Explore tab)
///
/// https://your-gitlab.com/…                  → same routing as grit:// above
///                                              (only when host matches configured instance)
/// ```
///
/// The handler fetches the target resource from the GitLab API (repository or
/// group/user lookup) and then pushes it onto the correct tab's NavigationPath,
/// switching the tab automatically via `AppNavigationState.pendingDeepLinkTab`.
@MainActor
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared
    private let nav  = AppNavigationState.shared

    // MARK: - Entry point

    /// Called from `GritApp`'s `.onOpenURL` modifier and from the Share Extension
    /// (which converts `https://` links to `grit://` before handing off).
    func handle(url: URL) {
        // Spin off the async resolution so the synchronous onOpenURL handler returns quickly.
        Task { await resolve(url: url) }
    }

    // MARK: - Resolution

    private func resolve(url: URL) async {
        // Don't attempt navigation before the user has authenticated.
        guard auth.isAuthenticated, auth.accessToken != nil else { return }

        guard let path = extractPath(from: url), !path.isEmpty else { return }

        // Split the path into non-empty segments.
        // e.g. "/stoicswe-projects/Grit/-/merge_requests" → ["stoicswe-projects", "Grit", "-", "merge_requests"]
        let parts = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !parts.isEmpty else { return }

        if parts.count == 1 {
            // Single segment — could be a group slug or username.
            await resolveProfile(slug: parts[0])
        } else {
            // Two or more segments — treat the first two as namespace/repo.
            let projectPath = "\(parts[0])/\(parts[1])"
            await resolveProject(path: projectPath)
        }
    }

    // MARK: - Path extraction

    /// Returns the URL path if the URL targets the configured GitLab instance (or
    /// is a `grit://` deep link). Returns `nil` for unrecognised URLs.
    private func extractPath(from url: URL) -> String? {
        switch url.scheme?.lowercased() {

        case "grit":
            // grit://gitlab.com/namespace/repo  →  /namespace/repo
            // The host segment is ignored — the configured instance is authoritative.
            return url.path

        case "https", "http":
            // Only handle links that belong to the user's configured GitLab instance.
            let urlHost        = url.host ?? ""
            let configuredHost = URL(string: auth.baseURL)?.host ?? ""
            guard urlHost == configuredHost else { return nil }
            return url.path

        default:
            return nil
        }
    }

    // MARK: - Destination routing

    /// Fetches the project at `path` and pushes it onto the Repositories tab stack.
    private func resolveProject(path: String) async {
        guard let token = auth.accessToken else { return }
        guard let repo = try? await api.fetchProjectByPath(
            path, baseURL: auth.baseURL, token: token) else { return }

        // Build a fresh path so we don't stack on top of unrelated history.
        var fresh = NavigationPath()
        fresh.append(repo)
        nav.repoNavigationPath  = fresh
        nav.pendingDeepLinkTab  = .repositories
    }

    /// Tries to resolve `slug` as a group first, then as a user, and opens the
    /// correct profile view on the Explore tab.
    private func resolveProfile(slug: String) async {
        guard let token = auth.accessToken else { return }

        // Attempt group lookup.
        if let group = try? await api.fetchGroupByPath(
            slug, baseURL: auth.baseURL, token: token) {
            var fresh = NavigationPath()
            fresh.append(ExploreDestination.groupDetail(group))
            nav.exploreNavigationPath = fresh
            nav.pendingDeepLinkTab    = .explore
            return
        }

        // Fall back to user search — match exact username.
        if let users = try? await api.searchUsers(
            query: slug, baseURL: auth.baseURL, token: token),
           let user = users.first(where: { $0.username.lowercased() == slug.lowercased() }) {
            var fresh = NavigationPath()
            fresh.append(user)
            nav.exploreNavigationPath = fresh
            nav.pendingDeepLinkTab    = .explore
        }
    }
}
