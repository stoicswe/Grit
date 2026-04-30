import AppIntents
import SwiftUI

// MARK: - Pipeline Status Snippet

/// Returns a rich inline view showing the latest pipeline status for a project.
struct GetPipelineStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Pipeline Status"
    static var description = IntentDescription(
        "Shows the latest CI/CD pipeline status for a GitLab project."
    )

    @Parameter(title: "Project")
    var project: ProjectEntity

    init() {}
    init(project: ProjectEntity) { self.project = project }

    func perform() async throws -> some IntentResult & ShowsSnippetView & ProvidesDialog {
        guard let token = await AuthenticationService.shared.accessToken else {
            throw IntentError.notAuthenticated
        }
        let baseURL = await AuthenticationService.shared.baseURL

        // Fetch the most recent pipeline (any ref) for this project.
        let pipelines = try await GitLabAPIService.shared.fetchProjectPipelines(
            projectID: project.id, baseURL: baseURL, token: token
        )
        let pipeline = pipelines.first

        // If we got a pipeline, fetch its full detail for duration / source info.
        let detail: PipelineDetail?
        if let pipeline {
            detail = try? await GitLabAPIService.shared.fetchPipelineDetail(
                projectID: project.id, pipelineID: pipeline.id,
                baseURL: baseURL, token: token
            )
        } else {
            detail = nil
        }

        let status = detail?.status ?? pipeline?.status
        let dialog: IntentDialog

        if let status {
            let label = pipelineLabel(for: status)
            dialog = "The latest pipeline for \(project.name) \(label)."
        } else {
            dialog = "No pipelines found for \(project.name)."
        }

        return .result(
            dialog: dialog,
            view: PipelineSnippetView(
                projectName: project.name,
                detail: detail,
                pipeline: pipeline
            )
        )
    }

    private func pipelineLabel(for status: String) -> String {
        switch status.lowercased() {
        case "success":  return "passed"
        case "failed":   return "failed"
        case "running":  return "is running"
        case "pending":  return "is pending"
        case "canceled": return "was canceled"
        case "skipped":  return "was skipped"
        case "manual":   return "is waiting for manual action"
        default:         return "has status: \(status)"
        }
    }
}

// MARK: - MR Summary Snippet

/// Returns a rich inline view summarizing the user's open merge requests.
struct ShowMRSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Merge Request Summary"
    static var description = IntentDescription(
        "Shows a visual summary of your open merge requests."
    )

    func perform() async throws -> some IntentResult & ShowsSnippetView & ProvidesDialog {
        guard let token = await AuthenticationService.shared.accessToken else {
            throw IntentError.notAuthenticated
        }
        let baseURL = await AuthenticationService.shared.baseURL
        guard let user = await AuthenticationService.shared.currentUser else {
            throw IntentError.notAuthenticated
        }

        async let assigned = GitLabAPIService.shared.fetchAssignedMRs(
            userID: user.id, baseURL: baseURL, token: token
        )
        async let reviewing = GitLabAPIService.shared.fetchReviewerMRs(
            userID: user.id, baseURL: baseURL, token: token
        )

        let assignedMRs = try await assigned
        let reviewMRs   = try await reviewing

        // Deduplicate.
        var seen = Set<Int>()
        let all = (assignedMRs + reviewMRs).filter { seen.insert($0.id).inserted }

        let dialog: IntentDialog
        if all.isEmpty {
            dialog = "You have no open merge requests."
        } else {
            dialog = "You have \(all.count) open merge requests."
        }

        return .result(
            dialog: dialog,
            view: MRSummarySnippetView(
                assignedCount: assignedMRs.count,
                reviewCount: reviewMRs.count,
                totalCount: all.count,
                topMRs: Array(all.prefix(3))
            )
        )
    }
}

// MARK: - Pipeline Snippet View

/// A compact SwiftUI view rendered inline in Siri's response showing pipeline status.
struct PipelineSnippetView: View {
    let projectName: String
    let detail: PipelineDetail?
    let pipeline: Pipeline?

    private var status: String? { detail?.status ?? pipeline?.status }

    private var icon: String {
        guard let s = status?.lowercased() else { return "questionmark.circle" }
        switch s {
        case "success":                return "checkmark.circle.fill"
        case "failed":                 return "xmark.circle.fill"
        case "running":                return "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
        case "pending", "created",
             "waiting_for_resource",
             "preparing":              return "clock.fill"
        case "canceled":               return "slash.circle.fill"
        case "manual":                 return "hand.tap.fill"
        case "scheduled":              return "calendar.badge.clock"
        default:                       return "questionmark.circle"
        }
    }

    private var color: Color {
        guard let s = status?.lowercased() else { return .secondary }
        switch s {
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

    private var label: String {
        guard let s = status?.lowercased() else { return "Unknown" }
        switch s {
        case "success":  return "Passed"
        case "failed":   return "Failed"
        case "running":  return "Running"
        case "pending":  return "Pending"
        case "canceled": return "Canceled"
        case "skipped":  return "Skipped"
        case "manual":   return "Manual"
        default:         return s.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: project name + status badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.headline)
                    if let ref = detail?.ref ?? pipeline?.ref {
                        Label(ref, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Status pill
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15), in: Capsule())
            }

            // Details row
            if detail != nil || pipeline != nil {
                HStack(spacing: 16) {
                    if let id = detail?.id ?? pipeline?.id {
                        Label("#\(id)", systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let duration = detail?.durationFormatted {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let source = detail?.sourceLabel {
                        Label(source, systemImage: detail?.sourceIcon ?? "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - MR Summary Snippet View

/// A compact SwiftUI view rendered inline in Siri's response showing MR stats.
struct MRSummarySnippetView: View {
    let assignedCount: Int
    let reviewCount: Int
    let totalCount: Int
    let topMRs: [MergeRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Stats row
            HStack(spacing: 16) {
                statPill(count: totalCount, label: "Open", color: .blue)
                statPill(count: assignedCount, label: "Assigned", color: .green)
                statPill(count: reviewCount, label: "To Review", color: .orange)
                Spacer()
            }

            // Top MRs
            if !topMRs.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(topMRs.prefix(3)) { mr in
                        HStack(spacing: 8) {
                            Image(systemName: mr.isDraft ? "pencil.circle" : "arrow.triangle.merge")
                                .font(.system(size: 12))
                                .foregroundStyle(stateColor(mr.state))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mr.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                if let path = mr.projectPath {
                                    Text("\(path)!\(mr.iid)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func statPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func stateColor(_ state: MergeRequest.MRState) -> Color {
        switch state {
        case .opened: return .green
        case .merged: return .purple
        case .closed: return .red
        case .locked: return .orange
        }
    }
}
