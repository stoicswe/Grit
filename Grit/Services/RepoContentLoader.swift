import Foundation

/// Cache-first loaders for repository content that several screens need at
/// the same time (README, contributors, root tree).
///
/// `RepositoryDetailView` (AI context), `RepoInfoTabView` and `RepoInfoOverlay`
/// all used to fetch the README independently — and `fetchReadme` tried up to
/// five filenames each time, so opening one repository could cost 15 round
/// trips for a single document.  These helpers route every caller through
/// `RepoCacheStore` and let `GitLabAPIService` coalesce whatever still has to
/// go to the network.
enum RepoContentLoader {

    /// Cached README text for `projectID` at `ref`.
    ///
    /// - Parameter readmeURL: The project's `readme_url` (from the Projects API).
    ///   When present the exact filename is used so a single request suffices.
    static func readme(projectID: Int,
                       ref: String,
                       readmeURL: String?,
                       baseURL: String,
                       token: String) async -> String? {
        let cache = RepoCacheStore.shared
        let key   = CacheKey.readme(projectID: projectID, ref: ref)

        if let cached: CachedReadme = await cache.get(key) {
            return cached.text
        }

        let text = await GitLabAPIService.shared.fetchReadme(
            projectID: projectID,
            ref: ref,
            preferredFileName: Self.readmeFileName(from: readmeURL),
            baseURL: baseURL,
            token: token
        )
        // Cache misses too (empty text) so repos without a README don't
        // re-probe five filenames on every visit.
        await cache.set(CachedReadme(text: text), for: key, ttl: RepoCacheStore.readmeTTL)
        return text
    }

    /// Cached contributor list for `projectID`.
    static func contributors(projectID: Int,
                             baseURL: String,
                             token: String) async throws -> [GitLabContributor] {
        let cache = RepoCacheStore.shared
        let key   = CacheKey.contributors(projectID: projectID)
        if let cached: [GitLabContributor] = await cache.get(key) {
            return cached
        }
        let fresh = try await GitLabAPIService.shared.fetchContributors(
            projectID: projectID, baseURL: baseURL, token: token
        )
        await cache.set(fresh, for: key, ttl: RepoCacheStore.contributorsTTL)
        return fresh
    }

    /// Cached, sorted root tree listing for `projectID` at `ref`.
    /// Serves a stale entry when `allowStale` is true.
    static func rootTree(projectID: Int,
                         ref: String,
                         allowStale: Bool = true,
                         baseURL: String,
                         token: String) async -> [RepositoryFile]? {
        let cache = RepoCacheStore.shared
        let key   = CacheKey.rootTree(projectID: projectID, ref: ref)
        if let cached: [RepositoryFile] = await cache.get(key, allowStale: allowStale) {
            return cached
        }
        guard let tree = try? await GitLabAPIService.shared.fetchRepositoryTree(
            projectID: projectID, path: "", ref: ref, baseURL: baseURL, token: token
        ) else { return nil }
        let sorted = tree.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        await cache.set(sorted, for: key, ttl: RepoCacheStore.rootTreeTTL)
        return sorted
    }

    /// Extracts the README filename from a GitLab `readme_url`
    /// (e.g. `https://gitlab.com/org/proj/-/blob/main/README.md` → `README.md`).
    static func readmeFileName(from readmeURL: String?) -> String? {
        guard let readmeURL, let url = URL(string: readmeURL) else { return nil }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }
        return name.removingPercentEncoding ?? name
    }
}

/// Disk-cacheable README wrapper. `text == nil` records "no README found" so
/// the miss itself is cached.
struct CachedReadme: Codable {
    let text: String?
}

// MARK: - Per-project access & labels

/// Cache-first accessors for per-project data that is needed on every issue
/// or MR open but changes very rarely.
enum ProjectAccessCache {

    /// The signed-in user's access level in `projectID` (10 = Guest … 50 = Owner),
    /// or `nil` when the user is not a member (or the lookup failed).
    /// A "not a member" answer is cached too so 404s aren't repeated per open.
    static func accessLevel(projectID: Int,
                            userID: Int,
                            baseURL: String,
                            token: String) async -> Int? {
        let cache = RepoCacheStore.shared
        let key   = CacheKey.memberAccess(projectID: projectID, userID: userID)
        if let cached: CachedAccessLevel = await cache.get(key) {
            return cached.level
        }
        let member = try? await GitLabAPIService.shared.fetchProjectMemberSelf(
            projectID: projectID, userID: userID, baseURL: baseURL, token: token
        )
        // Only cache definitive answers; transient failures are retried next time.
        if let member {
            await cache.set(CachedAccessLevel(level: member.accessLevel), for: key,
                            ttl: RepoCacheStore.memberAccessTTL)
        }
        return member?.accessLevel
    }

    /// Project labels for the label picker. Refreshed after the user creates a
    /// label (see `invalidateLabels`).
    static func labels(projectID: Int,
                       baseURL: String,
                       token: String) async -> [ProjectLabel] {
        let cache = RepoCacheStore.shared
        let key   = CacheKey.projectLabels(projectID: projectID)
        if let cached: [ProjectLabel] = await cache.get(key) {
            return cached
        }
        guard let fresh = try? await GitLabAPIService.shared.fetchProjectLabels(
            projectID: projectID, baseURL: baseURL, token: token
        ) else { return [] }
        await cache.set(fresh, for: key, ttl: RepoCacheStore.labelsTTL)
        return fresh
    }

    static func invalidateLabels(projectID: Int) async {
        await RepoCacheStore.shared.invalidate(.projectLabels(projectID: projectID))
    }
}

struct CachedAccessLevel: Codable {
    let level: Int?
}
