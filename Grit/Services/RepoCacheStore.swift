import Foundation

// MARK: - Cache Key

/// Typed key for every cacheable data shape in the repository layer.
enum CacheKey: Hashable {
    case repoList(page: Int)
    case repoDetail(projectID: Int)
    case branches(projectID: Int)
    case commits(projectID: Int, branch: String)
    case mrList(projectID: Int)
    case groups
    case starredList
    case rootTree(projectID: Int, ref: String)
    case readme(projectID: Int, ref: String)
    case contributors(projectID: Int)
    case projectLabels(projectID: Int)
    case memberAccess(projectID: Int, userID: Int)
    case notificationLevel(projectID: Int)
    case watchedList

    /// Filesystem-safe string used as the disk filename and memory dictionary key.
    var stringKey: String {
        switch self {
        case .repoList(let page):
            return "repo_list_p\(page)"
        case .repoDetail(let id):
            return "repo_detail_\(id)"
        case .branches(let id):
            return "branches_\(id)"
        case .commits(let id, let branch):
            let safe = String(
                branch
                    .replacingOccurrences(of: "/",  with: "_")
                    .replacingOccurrences(of: "\\", with: "_")
                    .replacingOccurrences(of: ":",  with: "_")
                    .prefix(80)                 // cap to avoid excessively long filenames
            )
            return "commits_\(id)_\(safe)"
        case .mrList(let id):
            return "mr_list_\(id)"
        case .groups:
            return "user_groups"
        case .starredList:
            return "starred_list"
        case .rootTree(let id, let ref):
            return "root_tree_\(id)_\(Self.safeRef(ref))"
        case .readme(let id, let ref):
            return "readme_\(id)_\(Self.safeRef(ref))"
        case .contributors(let id):
            return "contributors_\(id)"
        case .projectLabels(let id):
            return "labels_\(id)"
        case .memberAccess(let id, let userID):
            return "member_access_\(id)_u\(userID)"
        case .notificationLevel(let id):
            return "notif_level_\(id)"
        case .watchedList:
            return "watched_list"
        }
    }

    private static func safeRef(_ ref: String) -> String {
        String(
            ref
                .replacingOccurrences(of: "/",  with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .replacingOccurrences(of: ":",  with: "_")
                .prefix(80)
        )
    }
}

// MARK: - Cache Entry (disk envelope)

private struct CacheEntry<T: Codable>: Codable {
    let value:    T
    let cachedAt: Date
    let ttl:      TimeInterval

    var isValid: Bool { Date().timeIntervalSince(cachedAt) < ttl }
}

// MARK: - Memory Slot

private struct MemorySlot {
    /// The decoded value (type-erased). Kept so hot reads never re-decode JSON.
    let value:    Any
    let cachedAt: Date
    let ttl:      TimeInterval
    var isValid:  Bool { Date().timeIntervalSince(cachedAt) < ttl }
    var age:      TimeInterval { Date().timeIntervalSince(cachedAt) }
}

// MARK: - Two-Tier Cache Store

/// A two-tier (memory + disk) cache for repository data.
///
/// **Memory tier** — an in-process dictionary; near-zero latency; cleared on
/// low-memory notification or when the app is killed.
///
/// **Disk tier** — JSON files in the system Caches directory; survives app
/// restarts; trimmed automatically when the file count exceeds `maxDiskFiles`.
///
/// Both tiers honour per-entry TTLs.  Expired entries are evicted lazily on
/// read and proactively trimmed from disk periodically.
///
/// Use `allowStale: true` (stale-while-revalidate) to show cached content
/// immediately while a background refresh is in flight.
actor RepoCacheStore {
    static let shared = RepoCacheStore()

    // MARK: TTLs
    static let repoListTTL:    TimeInterval =  5 * 60   //  5 min — list can change often
    static let repoDetailTTL:  TimeInterval = 10 * 60   // 10 min — metadata is fairly stable
    static let branchesTTL:    TimeInterval = 15 * 60   // 15 min — branches change infrequently
    static let commitsTTL:     TimeInterval =  5 * 60   //  5 min — new commits arrive regularly
    static let groupsTTL:      TimeInterval = 30 * 60   // 30 min — group membership rarely changes
    static let mrListTTL:      TimeInterval =  5 * 60   //  5 min — MR state changes often
    static let starredListTTL: TimeInterval =  5 * 60   //  5 min — starred set can change often
    static let rootTreeTTL:    TimeInterval = 10 * 60   // 10 min — root tree rarely changes
    static let readmeTTL:      TimeInterval = 30 * 60   // 30 min — READMEs change rarely
    static let contributorsTTL: TimeInterval = 30 * 60  // 30 min — derived from full history
    static let labelsTTL:      TimeInterval = 15 * 60   // 15 min — label sets are stable
    static let memberAccessTTL: TimeInterval = 60 * 60  // 60 min — access level almost never changes
    static let notifLevelTTL:  TimeInterval = 30 * 60   // 30 min — updated locally on toggle
    static let watchedListTTL: TimeInterval = 15 * 60   // 15 min — costs ~1 call per member repo

    /// How recently a detail bundle must have been written for
    /// `RepositoryDetailViewModel` to skip the metadata/branch/MR refetch on
    /// open and only refresh the live pipeline badge.
    static let repoDetailFreshWindow: TimeInterval = 120

    // MARK: Private State
    private var memCache: [String: MemorySlot] = [:]
    private let diskURL: URL
    private let maxDiskFiles = 120         // beyond this, oldest files are pruned
    /// Directory listing + sort is not free; only run it every N writes.
    private var writesSinceTrim = 0
    private let trimEveryNWrites = 25

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskURL = caches.appendingPathComponent("GritRepoCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: diskURL, withIntermediateDirectories: true
        )
    }

    // MARK: - Read

    /// Returns a cached value.
    ///
    /// - Parameter allowStale: When `true` the entry is returned even if its TTL
    ///   has elapsed — useful for the stale-while-revalidate pattern where you
    ///   want to show something immediately while a background refresh runs.
    ///   Default is `false`.
    func get<T: Codable>(_ key: CacheKey, allowStale: Bool = false) -> T? {
        getWithAge(key, allowStale: allowStale)?.value
    }

    /// Like `get`, but also reports how old the entry is and whether it is
    /// still within its TTL. Lets callers make "fresh enough to skip the
    /// network" decisions without a second lookup.
    func getWithAge<T: Codable>(_ key: CacheKey,
                                allowStale: Bool = false) -> (value: T, age: TimeInterval, isFresh: Bool)? {
        let k = key.stringKey

        // 1. Memory tier — no I/O, no decoding
        if let slot = memCache[k] {
            if let typed = slot.value as? T, allowStale || slot.isValid {
                return (typed, slot.age, slot.isValid)
            }
            if !slot.isValid && !allowStale { memCache.removeValue(forKey: k) }
            // A type mismatch (same key, different T) falls through to disk.
        }

        // 2. Disk tier
        let file = diskURL.appendingPathComponent(k + ".json")
        guard let data = try? Data(contentsOf: file) else { return nil }

        guard let entry = try? decoder.decode(CacheEntry<T>.self, from: data) else {
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }
            return nil
        }

        guard allowStale || entry.isValid else {
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }
            return nil
        }

        // Promote to memory tier so the next read skips disk I/O and decoding
        memCache[k] = MemorySlot(value: entry.value, cachedAt: entry.cachedAt, ttl: entry.ttl)
        return (entry.value, Date().timeIntervalSince(entry.cachedAt), entry.isValid)
    }

    // MARK: - Write

    /// Stores `value` in both memory and disk tiers with the given TTL.
    func set<T: Codable>(_ value: T, for key: CacheKey, ttl: TimeInterval) {
        let k   = key.stringKey
        let now = Date()

        // Memory: synchronous, stores the decoded value directly
        memCache[k] = MemorySlot(value: value, cachedAt: now, ttl: ttl)

        // Disk: encode + write off the actor so callers never wait on I/O
        let entry   = CacheEntry(value: value, cachedAt: now, ttl: ttl)
        let fileURL = diskURL.appendingPathComponent(k + ".json")
        let encoder = self.encoder
        Task.detached(priority: .utility) {
            guard let data = try? encoder.encode(entry) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }

        // Prune stale disk entries occasionally (directory listing isn't free)
        writesSinceTrim += 1
        if writesSinceTrim >= trimEveryNWrites {
            writesSinceTrim = 0
            Task.detached(priority: .background) { [weak self] in
                await self?.trimDiskIfNeeded()
            }
        }
    }

    // MARK: - Invalidation

    func invalidate(_ key: CacheKey) {
        let k = key.stringKey
        memCache.removeValue(forKey: k)
        let file = diskURL.appendingPathComponent(k + ".json")
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func invalidateAll() {
        memCache.removeAll()
        let url = diskURL
        Task.detached(priority: .utility) {
            let files = (try? FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    // MARK: - Age-Based Project Eviction

    /// Removes every memory and disk cache entry associated with the given project IDs.
    ///
    /// Called by `RepoPrefetchService.performAgeBasedTrim()` after
    /// `RepoAccessTracker` identifies which projects have exceeded their
    /// adaptive max-age.
    func evictProjects(_ projectIDs: Set<Int>) {
        guard !projectIDs.isEmpty else { return }

        // ── Memory tier (synchronous — just dictionary removals) ────────────
        // A project's cache keys follow the patterns:
        //   repo_detail_<id>           branches_<id>
        //   mr_list_<id>               commits_<id>_<branch>
        //   readme_<id>_<ref>          contributors_<id>
        //   labels_<id>                member_access_<id>_u<user>
        //   notif_level_<id>           root_tree_<id>_<ref>
        //
        // We check both suffix and infix to correctly match multi-digit IDs
        // without catching partial matches (e.g. id=1 must not evict key for id=12).
        let keysToRemove = memCache.keys.filter { key in
            projectIDs.contains { id in
                key.hasSuffix("_\(id)") || key.contains("_\(id)_")
            }
        }
        keysToRemove.forEach { memCache.removeValue(forKey: $0) }

        // ── Disk tier (asynchronous) ────────────────────────────────────────
        let url = diskURL
        Task.detached(priority: .utility) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { return }
            for file in files {
                // Strip the ".json" extension to get the raw key string.
                let name = file.deletingPathExtension().lastPathComponent
                if projectIDs.contains(where: { id in
                    name.hasSuffix("_\(id)") || name.contains("_\(id)_")
                }) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    /// Drops the in-process memory tier (e.g. in response to a low-memory warning).
    func evictMemory() { memCache.removeAll() }

    // MARK: - Housekeeping

    private func trimDiskIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ), files.count > maxDiskFiles else { return }

        // Remove the oldest files first
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return a < b
        }
        sorted.prefix(files.count - maxDiskFiles).forEach {
            try? FileManager.default.removeItem(at: $0)
        }
    }
}

// MARK: - Cached Repository Detail Bundle

/// A single cacheable snapshot of everything loaded for one repository detail view:
/// metadata, branches, open MRs, and first-page commits on the default branch.
///
/// Pipeline **results** are intentionally excluded — CI status must always be
/// fetched fresh.  `hasPipeline` is the only pipeline-related field cached here:
/// it records whether this repo has CI/CD configured at all so subsequent loads
/// can skip the `fetchLatestPipeline` round-trip when it's known to return nil.
///
/// Notification level is also excluded — it's user-specific and always fetched fresh.
struct CachedRepoDetail: Codable {
    let repository:    Repository
    let branches:      [Branch]
    let mergeRequests: [MergeRequest]
    let commits:       [Commit]
    let selectedBranch: String?
    /// `nil`   = unknown (first visit or older cache entry — always attempt fetch)
    /// `false` = CI not configured — skip `fetchLatestPipeline` on future loads
    /// `true`  = CI is active — always fetch fresh status, never cache the result
    let hasPipeline:   Bool?
}

// MARK: - Cache Inventory

extension RepoCacheStore {
    /// Returns the project IDs of all repositories that currently have a detail
    /// bundle on disk.  Used by `BackgroundRefreshService` to refresh MRs for
    /// repos the user has recently visited, without requiring the app to be open.
    func cachedProjectIDs() -> [Int] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }
        return files.compactMap { file -> Int? in
            let name = file.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("repo_detail_") else { return nil }
            return Int(name.dropFirst("repo_detail_".count))
        }
    }
}
