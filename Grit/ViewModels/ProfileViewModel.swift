import Foundation
import SwiftUI
import WidgetKit

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

    /// Events younger than this (measured from the last successful fetch) are
    /// not re-fetched when the tab merely re-appears.
    private let freshWindow: TimeInterval = 5 * 60
    private var lastFetched: Date?
    /// Events from the last fetch, kept so the next refresh can be incremental.
    private var knownEvents: [ContributionEvent] = []

    /// Call on every appearance.
    /// • Already have data → silent background refresh only if stale (no shimmer)
    /// • Cache hit         → populate immediately + silent background refresh
    /// • Cold start        → full shimmer load
    /// - Parameter force: bypass the freshness window (pull-to-refresh).
    func load(force: Bool = false) async {
        guard let token = auth.accessToken else { return }

        if user != nil {
            // Revisiting the tab — refresh silently, but only when stale.
            // Every tab switch used to re-download a year of events.
            if force || lastFetched.map({ Date().timeIntervalSince($0) > freshWindow }) ?? true {
                scheduleBackgroundRefresh(token: token)
            }
            return
        }

        if let cached = readCache() {
            user             = cached.user
            ownedRepositories = cached.repos
            followers        = cached.followers
            knownEvents      = cached.events
            lastFetched      = cached.savedAt
            contributionStats = ContributionStats.build(from: cached.events)
            if force || cached.isStale {
                scheduleBackgroundRefresh(token: token)
            }
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
            async let eventsTask    = fetchEventsIncrementally(username: username,
                                                               baseURL: baseURL, token: token)
            let (fetchedUser, repos, events) = try await (userTask, reposTask, eventsTask)
            knownEvents = events
            lastFetched = Date()

            // Followers fetched after we have the user ID
            let fetchedFollowers = (try? await api.fetchUserFollowers(
                userID: fetchedUser.id, baseURL: baseURL, token: token
            )) ?? followers

            user              = fetchedUser
            ownedRepositories = repos
            followers         = fetchedFollowers
            let stats = ContributionStats.build(from: events)
            contributionStats = stats
            writeCache(user: fetchedUser, repos: repos,
                       followers: fetchedFollowers, events: events)
            writeWidgetData(stats: stats, username: fetchedUser.username)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Only surface the error on a cold load; background failures are silent
            if user == nil { self.error = error.localizedDescription }
        }
    }

    private func writeWidgetData(stats: ContributionStats, username: String) {
        let settings = SettingsStore.shared
        let colorRGB: WidgetDataStore.ContributionSnapshot.ColorRGB? = {
            guard let color = settings.accentColor else { return nil }
            var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return .init(r: Double(r), g: Double(g), b: Double(b))
        }()

        let snapshot = WidgetDataStore.ContributionSnapshot(
            days: stats.days.map { .init(date: $0.date, count: $0.count) },
            totalContributions: stats.totalContributions,
            currentStreak: stats.currentStreak,
            longestStreak: stats.longestStreak,
            username: username,
            updatedAt: Date(),
            accentColorRGB: colorRGB
        )
        WidgetDataStore.save(snapshot)
    }

    /// Fetches contribution events for the trailing year.
    ///
    /// The first load pulls the full year (up to 50 pages for very active
    /// accounts). Subsequent refreshes only ask GitLab for events after the
    /// newest one already known (minus a two-day overlap, since the API's
    /// `after` filter is date-granular) and merge them in by ID — typically a
    /// single small page instead of the whole year again.
    private func fetchEventsIncrementally(username: String,
                                          baseURL: String,
                                          token: String) async throws -> [ContributionEvent] {
        guard !username.isEmpty else { return [] }
        let calendar   = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()

        // Drop anything that has aged out of the one-year window.
        let retained = knownEvents.filter { event in
            guard let date = Self.eventDate(event) else { return false }
            return date >= oneYearAgo
        }

        let newestKnown = retained.compactMap(Self.eventDate).max()
        let since: Date
        if let newestKnown, !retained.isEmpty {
            since = max(oneYearAgo, calendar.date(byAdding: .day, value: -2, to: newestKnown) ?? newestKnown)
        } else {
            since = oneYearAgo
        }

        let fresh = try await api.fetchUserEvents(username: username,
                                                  baseURL: baseURL,
                                                  token: token,
                                                  after: since)
        guard !retained.isEmpty else { return fresh }

        var seen   = Set(fresh.map(\.id))
        var merged = fresh
        for event in retained where !seen.contains(event.id) {
            seen.insert(event.id)
            merged.append(event)
        }
        return merged
    }

    private static let eventDateFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let eventDatePlain = ISO8601DateFormatter()

    private static func eventDate(_ event: ContributionEvent) -> Date? {
        eventDateFractional.date(from: event.createdAt) ?? eventDatePlain.date(from: event.createdAt)
    }
}
