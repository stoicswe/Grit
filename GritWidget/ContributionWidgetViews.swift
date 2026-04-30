import SwiftUI
import WidgetKit

// MARK: - Entry View (routes to the correct size)

struct ContributionWidgetEntryView: View {
    let entry: ContributionEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let snapshot = entry.snapshot {
            let accent = userAccentColor(from: snapshot.accentColorRGB)
            switch family {
            case .systemSmall:
                SmallContributionView(snapshot: snapshot, accent: accent)
            case .systemMedium:
                MediumContributionView(snapshot: snapshot, accent: accent)
            case .systemLarge:
                LargeContributionView(snapshot: snapshot, accent: accent)
            default:
                MediumContributionView(snapshot: snapshot, accent: accent)
            }
        } else {
            Text("Open Grit to load contributions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Small Widget

private struct SmallContributionView: View {
    let snapshot: WidgetDataStore.ContributionSnapshot
    let accent: Color

    private let cellSize: CGFloat = 7
    private let spacing: CGFloat = 1.5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.username)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            // Mini grid — last N weeks that fit
            miniGrid
                .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                statItem(value: snapshot.totalContributions, label: "Total")
                statItem(value: snapshot.currentStreak, label: "Streak")
            }
        }
    }

    private var miniGrid: some View {
        let weeks = buildWeeks(from: snapshot.days, cellSize: cellSize, spacing: spacing, maxColumns: 13)
        return HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: spacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        Circle()
                            .fill(intensityColor(for: day.intensity, accent: accent))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium Widget

private struct MediumContributionView: View {
    let snapshot: WidgetDataStore.ContributionSnapshot
    let accent: Color

    private let cellSize: CGFloat = 9
    private let spacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.username)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                statsRow
            }

            GeometryReader { geo in
                let maxCols = Int((geo.size.width + spacing) / (cellSize + spacing))
                let weeks = buildWeeks(from: snapshot.days, cellSize: cellSize, spacing: spacing, maxColumns: maxCols)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                Circle()
                                    .fill(intensityColor(for: day.intensity, accent: accent))
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            legendRow
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            Label("\(snapshot.totalContributions)", systemImage: "square.fill.text.grid.1x2")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Label("\(snapshot.currentStreak) day streak", systemImage: "flame.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 3) {
            Text("Less")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            ForEach(0...4, id: \.self) { level in
                Circle()
                    .fill(intensityColor(for: level, accent: accent))
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Large Widget

private struct LargeContributionView: View {
    let snapshot: WidgetDataStore.ContributionSnapshot
    let accent: Color

    private let cellSize: CGFloat = 11
    private let spacing: CGFloat = 2.5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.username)
                        .font(.headline)
                    Text("\(snapshot.totalContributions) contributions in the last year")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Month labels
            GeometryReader { geo in
                let maxCols = Int((geo.size.width + spacing) / (cellSize + spacing))
                let weeks = buildWeeks(from: snapshot.days, cellSize: cellSize, spacing: spacing, maxColumns: maxCols)

                VStack(alignment: .leading, spacing: 4) {
                    monthLabels(weeks: weeks, step: cellSize + spacing)
                        .frame(height: 14)

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: spacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    Circle()
                                        .fill(intensityColor(for: day.intensity, accent: accent))
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Spacer(minLength: 0)

            // Stats row
            HStack(spacing: 0) {
                statCard(value: snapshot.totalContributions, label: "Total", icon: "square.fill.text.grid.1x2")
                Spacer()
                statCard(value: snapshot.currentStreak, label: "Current Streak", icon: "flame.fill")
                Spacer()
                statCard(value: snapshot.longestStreak, label: "Longest Streak", icon: "trophy.fill")
            }

            // Legend
            HStack(spacing: 3) {
                Spacer()
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                ForEach(0...4, id: \.self) { level in
                    Circle()
                        .fill(intensityColor(for: level, accent: accent))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statCard(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func monthLabels(weeks: [[WidgetDataStore.ContributionSnapshot.Day]], step: CGFloat) -> some View {
        let calendar = Calendar.current
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MMM"
            return f
        }()

        var labels: [(label: String, x: CGFloat)] = []
        var lastMonth = -1
        for (i, week) in weeks.enumerated() {
            guard let first = week.first else { continue }
            let month = calendar.component(.month, from: first.date)
            guard month != lastMonth else { continue }
            lastMonth = month
            let x = CGFloat(i) * step
            if let prev = labels.last, x - prev.x < 22 { continue }
            labels.append((formatter.string(from: first.date), x))
        }

        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(labels.enumerated()), id: \.offset) { _, entry in
                Text(entry.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: entry.x)
            }
        }
    }
}

// MARK: - Shared Helpers

private func buildWeeks(
    from days: [WidgetDataStore.ContributionSnapshot.Day],
    cellSize: CGFloat,
    spacing: CGFloat,
    maxColumns: Int
) -> [[WidgetDataStore.ContributionSnapshot.Day]] {
    let allWeeks: [[WidgetDataStore.ContributionSnapshot.Day]] = stride(from: 0, to: days.count, by: 7).map {
        Array(days[$0..<min($0 + 7, days.count)])
    }
    return Array(allWeeks.suffix(maxColumns))
}

private func userAccentColor(from rgb: WidgetDataStore.ContributionSnapshot.ColorRGB?) -> Color {
    guard let rgb else { return Color.accentColor }
    return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
}

private func intensityColor(for level: Int, accent: Color) -> Color {
    switch level {
    case 0:  return Color(.secondarySystemFill)
    case 1:  return accent.opacity(0.30)
    case 2:  return accent.opacity(0.55)
    case 3:  return accent.opacity(0.78)
    default: return accent
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    ContributionWidget()
} timeline: {
    ContributionEntry(date: .now, snapshot: .placeholder)
}

#Preview("Medium", as: .systemMedium) {
    ContributionWidget()
} timeline: {
    ContributionEntry(date: .now, snapshot: .placeholder)
}

#Preview("Large", as: .systemLarge) {
    ContributionWidget()
} timeline: {
    ContributionEntry(date: .now, snapshot: .placeholder)
}
