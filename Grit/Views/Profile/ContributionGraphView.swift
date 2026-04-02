import SwiftUI

struct ContributionGraphView: View {
    let stats: ContributionStats

    // Match the original cell size and spacing.
    private let cellSize: CGFloat  = 11
    private let spacing:  CGFloat  = 2.5

    // Measured via background GeometryReader; seeded with a sensible default so
    // the first frame renders without a jarring layout jump.
    @State private var graphWidth: CGFloat = 300

    // MARK: - Derived layout

    private var allWeeks: [[ContributionDay]] {
        stride(from: 0, to: stats.days.count, by: 7).map {
            Array(stats.days[$0..<min($0 + 7, stats.days.count)])
        }
    }

    /// How many week-columns fit in the measured width at the original cell size.
    private var visibleWeekCount: Int {
        max(1, Int((graphWidth + spacing) / (cellSize + spacing)))
    }

    /// The most recent N weeks that fit on screen — newest on the right.
    private var weeks: [[ContributionDay]] {
        Array(allWeeks.suffix(visibleWeekCount))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            monthLabelRow

            // Grid — only the most recent weeks that fit at full cell size, newest on the right.
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(week) { day in
                            ContributionCell(day: day, size: cellSize)
                                .help(
                                    "\(day.count) contribution\(day.count == 1 ? "" : "s") on "
                                    + day.date.formatted(date: .abbreviated, time: .omitted)
                                )
                        }
                    }
                }
            }

            legendRow
        }
        // Measure available width without expanding height the way a top-level
        // GeometryReader would.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { graphWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in graphWidth = w }
            }
        )
    }

    // MARK: - Month labels

    private var monthLabelRow: some View {
        // ZStack lets us position each label at its computed x offset without
        // requiring a fixed-width container — labels that fall off the trailing
        // edge simply aren't visible (which is the correct behaviour).
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 14)   // establishes row height
            ForEach(computedMonthLabels, id: \.x) { entry in
                Text(entry.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: entry.x)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 14)
    }

    /// Builds (label, x-position) pairs from the actual week data, skipping labels
    /// that would overlap their predecessor (minimum 22 pt gap).
    private var computedMonthLabels: [(label: String, x: CGFloat)] {
        let calendar = Calendar.current
        let step     = cellSize + spacing
        let minGap: CGFloat = 22

        var result: [(label: String, x: CGFloat)] = []
        var lastMonth = -1

        for (i, week) in weeks.enumerated() {
            guard let first = week.first else { continue }
            let month = calendar.component(.month, from: first.date)
            guard month != lastMonth else { continue }
            lastMonth = month
            let x = CGFloat(i) * step
            // Skip label if it's too close to the previous one.
            if let prev = result.last, x - prev.x < minGap { continue }
            result.append((monthAbbreviation(for: first.date), x))
        }
        return result
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private func monthAbbreviation(for date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(0...4, id: \.self) { level in
                Circle()
                    .fill(intensityColor(level))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Colour scale

    private func intensityColor(_ level: Int) -> Color {
        switch level {
        case 0:  return Color(.secondarySystemFill)
        case 1:  return Color.accentColor.opacity(0.30)
        case 2:  return Color.accentColor.opacity(0.55)
        case 3:  return Color.accentColor.opacity(0.78)
        default: return Color.accentColor
        }
    }
}
