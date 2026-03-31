import SwiftUI

struct ContributionGraphView: View {
    let stats: ContributionStats
    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 2.5

    private var weeks: [[ContributionDay]] {
        // Chunk days into weeks of 7
        stride(from: 0, to: stats.days.count, by: 7).map {
            Array(stats.days[$0..<min($0 + 7, stats.days.count)])
        }
    }

    private var monthLabels: [(label: String, weekIndex: Int)] {
        Self.buildMonthLabels()
    }

    private static let monthAbbreviationFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private static func buildMonthLabels() -> [(label: String, weekIndex: Int)] {
        let calendar = Calendar.current
        let today = Date()
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        var result: [(label: String, weekIndex: Int)] = []
        var currentDate = oneYearAgo
        var lastMonth = -1
        var weekIndex = 0

        while currentDate <= today {
            let month = calendar.component(.month, from: currentDate)
            if month != lastMonth {
                result.append((
                    label: monthAbbreviationFormatter.string(from: currentDate),
                    weekIndex: weekIndex
                ))
                lastMonth = month
            }
            currentDate = calendar.date(byAdding: .day, value: 7, to: currentDate) ?? today
            weekIndex += 1
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Month labels
            monthLabelRow

            // Grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(week) { day in
                                ContributionCell(day: day, size: cellSize)
                                    .help("\(day.count) contribution\(day.count == 1 ? "" : "s") on \(day.date.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            // Legend
            HStack(spacing: 6) {
                Text("Less")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(intensityColor(level))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("More")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var monthLabelRow: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                ForEach(monthLabels, id: \.weekIndex) { entry in
                    Text(entry.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .offset(x: CGFloat(entry.weekIndex) * (cellSize + cellSpacing))
                }
            }
        }
        .frame(height: 16)
    }

    private func intensityColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.08)
        case 1: return Color.accentColor.opacity(0.3)
        case 2: return Color.accentColor.opacity(0.55)
        case 3: return Color.accentColor.opacity(0.75)
        default: return Color.accentColor
        }
    }
}
