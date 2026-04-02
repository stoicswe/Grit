import Foundation
import SwiftUI

struct ContributionDay: Identifiable {
    let id = UUID()
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

    var intensityColor: Color {
        switch intensity {
        case 0: return Color(.secondarySystemFill)
        case 1: return Color.accentColor.opacity(0.30)
        case 2: return Color.accentColor.opacity(0.55)
        case 3: return Color.accentColor.opacity(0.78)
        default: return Color.accentColor
        }
    }
}

struct ContributionEvent: Codable, Identifiable {
    let id: Int
    let createdAt: String
    let actionName: String
    let targetType: String?
    let projectId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case actionName = "action_name"
        case targetType = "target_type"
        case projectId = "project_id"
    }
}

struct ContributionStats {
    let totalContributions: Int
    let currentStreak: Int
    let longestStreak: Int
    let days: [ContributionDay]

    static func build(from events: [ContributionEvent]) -> ContributionStats {
        let calendar = Calendar.current
        let today = Date()
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today

        // Count events per day
        var countsByDate: [DateComponents: Int] = [:]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let altFormatter = ISO8601DateFormatter()

        for event in events {
            let date = dateFormatter.date(from: event.createdAt) ?? altFormatter.date(from: event.createdAt)
            if let date = date, date >= oneYearAgo {
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                countsByDate[components, default: 0] += 1
            }
        }

        // Build all days in the past year
        var days: [ContributionDay] = []
        var currentDate = oneYearAgo
        while currentDate <= today {
            let components = calendar.dateComponents([.year, .month, .day], from: currentDate)
            let count = countsByDate[components] ?? 0
            days.append(ContributionDay(date: currentDate, count: count))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? today
        }

        let total = days.reduce(0) { $0 + $1.count }

        // Calculate streaks
        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 0

        for day in days.reversed() {
            if day.count > 0 {
                tempStreak += 1
                if currentStreak == 0 { currentStreak = tempStreak }
                longestStreak = max(longestStreak, tempStreak)
            } else {
                if currentStreak == 0 { currentStreak = 0 }
                tempStreak = 0
            }
        }

        return ContributionStats(
            totalContributions: total,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            days: days
        )
    }
}
