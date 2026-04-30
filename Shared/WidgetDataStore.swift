import Foundation

/// Shared data store for passing contribution data from the main app to the widget
/// via an App Group container.
enum WidgetDataStore {
    static let appGroupID = "group.com.stoicswe.grit.app"
    private static let contributionKey = "widget.contributionData"

    // MARK: - Shared model

    struct ContributionSnapshot: Codable {
        let days: [Day]
        let totalContributions: Int
        let currentStreak: Int
        let longestStreak: Int
        let username: String
        let updatedAt: Date
        /// User-selected accent color as RGB components, or `nil` for the default.
        let accentColorRGB: ColorRGB?

        struct Day: Codable {
            let date: Date
            let count: Int

            var intensity: Int {
                switch count {
                case 0: return 0
                case 1...3: return 1
                case 4...6: return 2
                case 7...9: return 3
                default: return 4
                }
            }
        }

        struct ColorRGB: Codable {
            let r: Double
            let g: Double
            let b: Double
        }
    }

    // MARK: - Read / Write

    static func save(_ snapshot: ContributionSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: contributionKey)
    }

    static func load() -> ContributionSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: contributionKey),
              let snapshot = try? JSONDecoder().decode(ContributionSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
