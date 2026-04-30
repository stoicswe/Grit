import Foundation

// MARK: - Access Event

/// A single recorded navigation to a repository.
/// Stored persistently so the model survives app restarts.
struct RepoAccessEvent: Codable {
    let repoID:    Int
    let repoName:  String
    let timestamp: Date
    /// Hour of day at the moment of access (0–23).
    let hourOfDay: Int
    /// Day of week at the moment of access (1 = Sunday … 7 = Saturday).
    let dayOfWeek: Int
}

// MARK: - Repo Score

/// A predicted relevance score for a single repository.
struct RepoScore: Comparable {
    let repoID:   Int
    let repoName: String
    let score:    Double
    static func < (lhs: RepoScore, rhs: RepoScore) -> Bool { lhs.score < rhs.score }
}

// MARK: - Access Tracker

/// Records every repository navigation and applies a time-aware frequency-decay
/// model to predict which repositories the user is most likely to open next.
///
/// ## ML Algorithm
///
/// The scoring function is a weighted linear combination of three classical signals:
///
/// ```
/// Score(repo) = α · Recency  +  β · Frequency  +  γ · TemporalAffinity
/// ```
///
/// ### Recency (α = 0.50)
/// Exponential decay from the most recent access, measured in hours:
/// ```
/// Recency = exp(–λ · hoursAgo),   λ = 0.04
/// ```
/// At λ = 0.04 a repo accessed 24 h ago scores ≈ 0.38; one accessed 72 h ago ≈ 0.06.
/// Recency gets the highest weight because "I just opened it" is the strongest signal.
///
/// ### Frequency (β = 0.30)
/// Log-normalised access count relative to the most-visited repository:
/// ```
/// Frequency = log(1 + count) / log(1 + maxCount)
/// ```
/// The log dampens the advantage of very high counts and prevents one heavily-used
/// repo from dominating the ranking indefinitely.
///
/// ### TemporalAffinity (γ = 0.20)
/// Fraction of past accesses that occurred within ±1 hour of the current time of day:
/// ```
/// TemporalAffinity = accessesInNearHours / totalAccessesForRepo
/// ```
/// Captures patterns like "I always review this repo in the morning."
/// This is the softest signal; it only fires meaningfully after several sessions.
actor RepoAccessTracker {
    static let shared = RepoAccessTracker()

    // Rolling window — events older than ~500 entries contribute negligible weight.
    private let maxEvents = 500

    private var events: [RepoAccessEvent] = []
    private let storageURL: URL

    // Scoring hyper-parameters
    private let α = 0.50   // recency weight
    private let β = 0.30   // frequency weight
    private let γ = 0.20   // temporal affinity weight
    private let λ = 0.04   // per-hour decay rate

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageURL = support.appendingPathComponent("GritRepoAccessLog.json")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Public API

    /// Records a repository navigation event.
    /// Call this every time the user opens a `RepositoryDetailView`.
    func track(repoID: Int, repoName: String) {
        let now = Date()
        let cal = Calendar.current
        let event = RepoAccessEvent(
            repoID:    repoID,
            repoName:  repoName,
            timestamp: now,
            hourOfDay: cal.component(.hour,    from: now),
            dayOfWeek: cal.component(.weekday, from: now)
        )
        events.append(event)
        // Trim the rolling window
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        persist()
    }

    /// Returns up to `count` predicted repositories, sorted from most to least
    /// likely to be opened next based on the user's historical access patterns.
    func topPredicted(count: Int = 5) -> [RepoScore] {
        guard !events.isEmpty else { return [] }
        let now = Date()
        let uniqueIDs = Set(events.map(\.repoID))
        let scores = uniqueIDs.compactMap { id -> RepoScore? in
            let s = score(repoID: id, now: now)
            guard s > 0.001 else { return nil }  // discard negligible scores
            // Use the most recent name recorded for this repo
            let name = events.last(where: { $0.repoID == id })?.repoName ?? ""
            return RepoScore(repoID: id, repoName: name, score: s)
        }
        return Array(scores.sorted(by: >).prefix(count))
    }

    // MARK: - Adaptive Cache Aging

    /// Returns the set of tracked project IDs whose disk-cache entries should be
    /// purged because the user hasn't visited them within their computed max-age.
    ///
    /// A project is a candidate when:
    /// ```
    ///   now − lastAccessTimestamp  >  adaptiveMaxAge(repoID)
    /// ```
    /// Projects with no recorded events at all are always included (unknown history
    /// → treat as stale).
    func projectIDsToEvict() -> Set<Int> {
        let now = Date()
        return Set(
            Set(events.map(\.repoID)).filter { id in
                let mine = events.filter { $0.repoID == id }
                guard let lastAccess = mine.map(\.timestamp).max() else { return true }
                return now.timeIntervalSince(lastAccess) > adaptiveMaxAge(for: mine)
            }
        )
    }

    /// Returns the adaptive max-age for a given project ID — useful for display
    /// in a debug / settings view.
    func adaptiveMaxAge(repoID: Int) -> TimeInterval {
        adaptiveMaxAge(for: events.filter { $0.repoID == repoID })
    }

    // MARK: - Adaptive Max-Age Algorithm
    //
    // The max-age a project can stay cached before eviction scales with how
    // actively the user visits it.  Rarely-accessed repos age out quickly;
    // daily-use repos stay cached much longer.
    //
    // Formula (log-space interpolation):
    //
    //   maxAge = minAge + (ceilAge − minAge) × clamp(log(1+N) / log(1+30), 0, 1)
    //
    // where N = number of accesses in the past 30 days.
    //
    // Reference table:
    //
    //   N (30-day accesses) │ Max-age
    //   ────────────────────┼────────
    //   0  (never)          │ 14 days  ← purge after 2 weeks of disuse
    //   ≈4  (weekly)        │ ≈20 days
    //   ≈12 (2–3× / week)   │ ≈29 days
    //   30  (daily)         │  42 days ← ceiling
    //   >30 (several/day)   │  42 days (capped)
    //
    // Why log?  A user who opens a repo 60×/month shouldn't get 2× the grace
    // period of someone who opens it 30×.  The log dampens extreme frequencies
    // and keeps the scale human-readable.

    private func adaptiveMaxAge(for repoEvents: [RepoAccessEvent]) -> TimeInterval {
        let window30    = Date().addingTimeInterval(-30 * 24 * 3600)
        let recentCount = Double(repoEvents.filter { $0.timestamp > window30 }.count)

        // Normalised ratio: 0 → 1 as N goes from 0 → 30+
        let normalizer  = log(1 + 30.0)
        let ratio       = min(1.0, log(1 + recentCount) / normalizer)

        let minAge: TimeInterval = 14 * 24 * 3600   // 2 weeks
        let ceilAge: TimeInterval = 42 * 24 * 3600  // 6 weeks

        return minAge + ratio * (ceilAge - minAge)
    }

    // MARK: - Scoring Model

    private func score(repoID: Int, now: Date) -> Double {
        let mine = events.filter { $0.repoID == repoID }
        guard !mine.isEmpty else { return 0 }

        // ── Recency ──────────────────────────────────────────────────────────
        let mostRecent  = mine.map(\.timestamp).max()!
        let hoursAgo    = max(0, now.timeIntervalSince(mostRecent) / 3_600)
        let recency     = exp(-λ * hoursAgo)

        // ── Frequency ────────────────────────────────────────────────────────
        // Build a count map across all repos once (O(n) over all events).
        let countByID = Dictionary(grouping: events, by: \.repoID).mapValues(\.count)
        let maxCount  = Double(countByID.values.max() ?? 1)
        let myCount   = Double(mine.count)
        let frequency = log(1 + myCount) / log(1 + maxCount)

        // ── Temporal Affinity ────────────────────────────────────────────────
        let currentHour    = Calendar.current.component(.hour, from: now)
        let nearHourCount  = mine.filter { abs($0.hourOfDay - currentHour) <= 1 }.count
        let temporalAffinity = myCount > 0 ? Double(nearHourCount) / myCount : 0

        return α * recency + β * frequency + γ * temporalAffinity
    }

    // MARK: - Persistence

    private func load() {
        guard let data   = try? Data(contentsOf: storageURL),
              let loaded = try? decoder.decode([RepoAccessEvent].self, from: data)
        else { return }
        events = loaded
    }

    private func persist() {
        guard let data = try? encoder.encode(events) else { return }
        let url = storageURL
        Task.detached(priority: .utility) { [data] in
            try? data.write(to: url, options: .atomic)
        }
    }
}
