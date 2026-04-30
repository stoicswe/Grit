import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct ContributionEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDataStore.ContributionSnapshot?
}

// MARK: - Timeline Provider

struct ContributionProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContributionEntry {
        ContributionEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContributionEntry) -> Void) {
        let entry = ContributionEntry(date: .now, snapshot: WidgetDataStore.load() ?? .placeholder)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContributionEntry>) -> Void) {
        let snapshot = WidgetDataStore.load()
        let entry = ContributionEntry(date: .now, snapshot: snapshot)
        // Refresh every 30 minutes — actual data updates when the main app is opened.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Configuration

struct ContributionWidget: Widget {
    let kind = "ContributionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContributionProvider()) { entry in
            ContributionWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Contributions")
        .description("View your GitLab contribution graph.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Placeholder data

extension WidgetDataStore.ContributionSnapshot {
    static let placeholder: Self = {
        let calendar = Calendar.current
        let today = Date()
        let days: [WidgetDataStore.ContributionSnapshot.Day] = (0..<365).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let count = [0, 0, 0, 1, 2, 3, 0, 1, 0, 4, 5, 0, 0, 1, 2][offset % 15]
            return .init(date: date, count: count)
        }
        return .init(
            days: days,
            totalContributions: 142,
            currentStreak: 5,
            longestStreak: 12,
            username: "username",
            updatedAt: today,
            accentColorRGB: nil
        )
    }()
}
