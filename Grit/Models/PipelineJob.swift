import SwiftUI

/// A single CI job belonging to a pipeline, grouped by its `stage` name.
struct PipelineJob: Codable, Identifiable, Hashable {
    let id:           Int
    let name:         String
    let stage:        String
    let status:       String
    let createdAt:    Date?
    let startedAt:    Date?
    let finishedAt:   Date?
    let duration:     Double?
    let webURL:       String?
    let allowFailure: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, stage, status, duration
        case createdAt    = "created_at"
        case startedAt    = "started_at"
        case finishedAt   = "finished_at"
        case webURL       = "web_url"
        case allowFailure = "allow_failure"
    }

    // MARK: - Display helpers (mirrors Pipeline model conventions)

    var icon: String {
        switch status.lowercased() {
        case "success":                                    return "checkmark.circle.fill"
        case "failed":                                     return "xmark.circle.fill"
        case "running":                                    return "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
        case "pending", "created",
             "waiting_for_resource", "preparing":          return "clock.fill"
        case "canceled":                                   return "slash.circle.fill"
        case "skipped":                                    return "forward.fill"
        case "manual":                                     return "hand.tap.fill"
        case "scheduled":                                  return "calendar.badge.clock"
        default:                                           return "questionmark.circle"
        }
    }

    var color: Color {
        switch status.lowercased() {
        case "success":                                    return .green
        case "failed":                                     return .red
        case "running":                                    return .blue
        case "pending", "created",
             "waiting_for_resource", "preparing":          return .orange
        case "canceled", "skipped":                        return .secondary
        case "manual":                                     return .purple
        case "scheduled":                                  return .teal
        default:                                           return .secondary
        }
    }

    var label: String {
        switch status.lowercased() {
        case "success":              return String(localized: "Passed",     comment: "CI pipeline or job status: all jobs completed successfully")
        case "failed":               return String(localized: "Failed",     comment: "CI pipeline or job status: one or more jobs failed")
        case "running":              return String(localized: "Running",    comment: "CI pipeline or job status: currently executing")
        case "pending":              return String(localized: "Pending",    comment: "CI pipeline or job status: queued, waiting to start")
        case "created":              return String(localized: "Created",    comment: "CI pipeline or job status: newly created, not yet queued")
        case "waiting_for_resource": return String(localized: "Waiting",    comment: "CI pipeline or job status: waiting for a resource lock")
        case "preparing":            return String(localized: "Preparing",  comment: "CI pipeline or job status: runner is preparing the environment")
        case "canceled":             return String(localized: "Canceled",   comment: "CI pipeline or job status: manually canceled before completion")
        case "skipped":              return String(localized: "Skipped",    comment: "CI pipeline or job status: skipped due to rules or conditions")
        case "manual":               return String(localized: "Manual",     comment: "CI pipeline or job status: requires a manual trigger to run")
        case "scheduled":            return String(localized: "Scheduled",  comment: "CI pipeline or job status: triggered on a schedule")
        default:                     return status.capitalized
        }
    }

    /// Human-readable elapsed time, e.g. "2m 14s".
    var durationFormatted: String? {
        guard let d = duration else { return nil }
        let mins = Int(d) / 60
        let secs = Int(d) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }
}
