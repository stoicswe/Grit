import SwiftUI

/// Resolves a `GitLabNotification` to its underlying Issue or MR and pushes
/// the appropriate detail view. Handles "Note" type notifications by inspecting
/// the target URL path when `targetType` alone is insufficient.
struct NotificationTargetView: View {

    let notification: GitLabNotification

    @EnvironmentObject private var navState: AppNavigationState
    @EnvironmentObject private var inboxViewModel: InboxViewModel

    @State private var state: LoadState = .loading

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - State

    private enum LoadState {
        case loading
        case issue(GitLabIssue)
        case mr(MergeRequest)
        case unsupported(URL?)   // show "Open in Browser" fallback
        case error(String)
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .issue(let issue):
                IssueDetailView(issue: issue, projectID: issue.projectID)
                    .environmentObject(navState)

            case .mr(let mr):
                MergeRequestDetailView(projectID: mr.projectID, mr: mr)
                    .environmentObject(navState)

            case .unsupported(let url):
                unsupportedView(url: url)

            case .error(let message):
                ContentUnavailableView(
                    "Could Not Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .task { await resolve() }
    }

    // MARK: - Resolution

    private func resolve() async {
        guard let token = auth.accessToken else {
            state = .error("Not signed in.")
            return
        }

        // Parse the target IID and type from the notification.
        guard let target = parseTarget() else {
            // No project ID or unparseable URL — fall back to opening in browser.
            let fallback = notification.targetURL.flatMap { URL(string: $0) }
            state = .unsupported(fallback)
            return
        }

        do {
            switch target.type {
            case .issue:
                let issue = try await api.fetchIssue(
                    projectID: target.projectID,
                    issueIID:  target.iid,
                    baseURL:   auth.baseURL,
                    token:     token
                )
                state = .issue(issue)

            case .mergeRequest:
                let mr = try await api.fetchMergeRequest(
                    projectID: target.projectID,
                    mrIID:     target.iid,
                    baseURL:   auth.baseURL,
                    token:     token
                )
                state = .mr(mr)
            }

            // Target resolved successfully — dismiss the notification so it
            // no longer appears in the unread list.
            if notification.unread {
                await inboxViewModel.markRead(notification)
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - URL Parsing

    private struct Target {
        let projectID: Int
        let iid: Int
        enum Kind { case issue, mergeRequest }
        let type: Kind
    }

    private func parseTarget() -> Target? {
        guard let projectID = notification.project?.id,
              let urlString = notification.targetURL,
              let url = URL(string: urlString),
              let iid = Int(url.lastPathComponent) else { return nil }

        // Prefer explicit targetType; fall back to inspecting the URL path
        // (needed for "Note" notifications that link to an issue/MR comment).
        let path = url.path
        let rawType = notification.targetType?.lowercased() ?? ""

        if rawType == "issue" || (rawType == "note" && path.contains("/issues/")) {
            return Target(projectID: projectID, iid: iid, type: .issue)
        }
        if rawType == "mergerequest" || (rawType == "note" && path.contains("/merge_requests/")) {
            return Target(projectID: projectID, iid: iid, type: .mergeRequest)
        }

        return nil  // commit, pipeline, etc. — handled as unsupported
    }

    // MARK: - Unsupported Fallback

    private func unsupportedView(url: URL?) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Open in Browser")
                .font(.title3.weight(.semibold))

            Text("This notification type can't be shown in-app yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let url {
                Link("Open GitLab", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }
}
