import SwiftUI

/// Minimal GitLab pipeline representation used for status display.
/// Full response contains many more fields; we only decode what the UI needs.
struct Pipeline: Codable, Identifiable, Hashable {
    let id:     Int
    let status: String   // "success" | "failed" | "running" | "pending" | "canceled" |
                         // "skipped" | "created" | "manual" | "scheduled" |
                         // "waiting_for_resource" | "preparing"
    let ref:    String?
    let webURL: String?

    enum CodingKeys: String, CodingKey {
        case id, status, ref
        case webURL = "web_url"
    }

    // MARK: - Display helpers

    var icon: String {
        switch status.lowercased() {
        case "success":                return "checkmark.circle.fill"
        case "failed":                 return "xmark.circle.fill"
        case "running":                return "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
        case "pending", "created",
             "waiting_for_resource",
             "preparing":              return "clock.fill"
        case "canceled":               return "slash.circle.fill"
        case "skipped":                return "forward.fill"
        case "manual":                 return "hand.tap.fill"
        case "scheduled":              return "calendar.badge.clock"
        default:                       return "questionmark.circle"
        }
    }

    var label: String {
        switch status.lowercased() {
        case "success":              return "Passed"
        case "failed":               return "Failed"
        case "running":              return "Running"
        case "pending":              return "Pending"
        case "created":              return "Created"
        case "waiting_for_resource": return "Waiting"
        case "preparing":            return "Preparing"
        case "canceled":             return "Canceled"
        case "skipped":              return "Skipped"
        case "manual":               return "Manual"
        case "scheduled":            return "Scheduled"
        default:                     return status.capitalized
        }
    }

    var color: Color {
        switch status.lowercased() {
        case "success":                              return .green
        case "failed":                               return .red
        case "running":                              return .blue
        case "pending", "created",
             "waiting_for_resource", "preparing":    return .orange
        case "canceled", "skipped":                  return .secondary
        case "manual":                               return .purple
        case "scheduled":                            return .teal
        default:                                     return .secondary
        }
    }
}
