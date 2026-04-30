import SwiftUI

// MARK: - PipelineDetail
// Full pipeline metadata returned by GET /projects/:id/pipelines/:pipeline_id

struct PipelineDetail: Codable, Identifiable {
    let id:             Int
    let status:         String
    let ref:            String?
    let sha:            String?
    let webURL:         String?
    let source:         String?
    let duration:       Double?
    let queuedDuration: Double?
    let createdAt:      Date?
    let startedAt:      Date?
    let finishedAt:     Date?
    let user:           GitLabUser?

    enum CodingKeys: String, CodingKey {
        case id, status, ref, sha, source, duration, user
        case webURL         = "web_url"
        case queuedDuration = "queued_duration"
        case createdAt      = "created_at"
        case startedAt      = "started_at"
        case finishedAt     = "finished_at"
    }

    // MARK: - Computed display helpers

    var shortSHA: String? { sha.map { String($0.prefix(8)) } }

    var sourceLabel: String {
        switch source?.lowercased() {
        case "push":                          return String(localized: "Push",                   comment: "CI pipeline trigger source: triggered by a git push")
        case "web":                           return String(localized: "Manual (Web UI)",        comment: "CI pipeline trigger source: triggered manually via the GitLab web interface")
        case "schedule":                      return String(localized: "Scheduled",              comment: "CI pipeline or job status: triggered on a schedule")
        case "api":                           return String(localized: "API",                    comment: "CI pipeline trigger source: triggered via the GitLab API")
        case "trigger":                       return String(localized: "Trigger",                comment: "CI pipeline trigger source: triggered via a pipeline trigger token")
        case "external":                      return String(localized: "External",               comment: "CI pipeline trigger source: triggered by an external service")
        case "pipeline":                      return String(localized: "Child Pipeline",         comment: "CI pipeline trigger source: triggered as a child of another pipeline")
        case "parent_pipeline":               return String(localized: "Parent Pipeline",        comment: "CI pipeline trigger source: triggered by a parent pipeline")
        case "chat":                          return String(localized: "ChatOps",                comment: "CI pipeline trigger source: triggered via a ChatOps command")
        case "webide":                        return String(localized: "Web IDE",                comment: "CI pipeline trigger source: triggered from the GitLab Web IDE")
        case "merge_request_event":           return String(localized: "Merge Request",          comment: "Merge request entity label")
        case "external_pull_request_event":   return String(localized: "External Pull Request",  comment: "CI pipeline trigger source: triggered by an external pull request event")
        case "ondemand_dast_scan":            return String(localized: "DAST Scan",              comment: "CI pipeline trigger source: triggered by an on-demand DAST security scan")
        default:                              return source?.capitalized ?? String(localized: "Unknown")
        }
    }

    var sourceIcon: String {
        switch source?.lowercased() {
        case "push":                          return "arrow.up.circle.fill"
        case "web":                           return "cursorarrow.click"
        case "schedule":                      return "calendar.badge.clock"
        case "api":                           return "terminal.fill"
        case "trigger":                       return "bolt.fill"
        case "pipeline", "parent_pipeline":   return "arrow.triangle.branch"
        case "merge_request_event":           return "arrow.triangle.merge"
        case "chat":                          return "bubble.left.fill"
        default:                              return "questionmark.circle"
        }
    }

    var durationFormatted: String? {
        guard let d = duration else { return nil }
        let h = Int(d) / 3600
        let m = Int(d) / 60 % 60
        let s = Int(d) % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    var queuedDurationFormatted: String? {
        guard let q = queuedDuration, q >= 1 else { return nil }
        let s = Int(q)
        return s >= 60 ? "\(s / 60)m \(s % 60)s queued" : "\(s)s queued"
    }
}

// MARK: - Pipeline (minimal, used for list/badge display)
/// Minimal GitLab pipeline representation used for status display.
/// Full response contains many more fields; we only decode what the UI needs.
struct Pipeline: Codable, Identifiable, Hashable {
    let id:        Int
    let status:    String   // "success" | "failed" | "running" | "pending" | "canceled" |
                            // "skipped" | "created" | "manual" | "scheduled" |
                            // "waiting_for_resource" | "preparing"
    let ref:       String?
    let webURL:    String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, ref
        case webURL    = "web_url"
        case createdAt = "created_at"
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
