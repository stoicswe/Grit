import SwiftUI

struct ActivityView: View {
    @StateObject private var viewModel = ActivityViewModel()
    @EnvironmentObject var navState: AppNavigationState

    // Navigation targets
    @State private var pendingIssue:       GitLabIssue?
    @State private var pendingIssueProjectID: Int = 0
    @State private var pendingMR:          MergeRequest?
    @State private var pendingMRProjectID: Int = 0

    // Per-row loading indicator
    @State private var loadingEventID: Int?

    @Environment(\.openURL) private var openURL

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, viewModel.activeFilter == .starredProjects ? 4 : 10)
                .background(.bar)

            // Type sub-filter — only visible for Starred
            if viewModel.activeFilter == .starredProjects {
                typeFilterBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .background(.bar)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            Group {
                if viewModel.isLoading && viewModel.isEmpty && viewModel.error == nil {
                    loadingSkeleton
                } else if viewModel.isEmpty && !viewModel.isLoading {
                    if let errorMessage = viewModel.error {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "Failed to Load",
                                systemImage: "exclamationmark.triangle",
                                description: Text(errorMessage)
                            )
                            Button("Retry") {
                                Task { await viewModel.load() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    } else {
                        emptyState
                    }
                } else {
                    activityList
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        // Issue navigation
        .navigationDestination(item: $pendingIssue) { issue in
            IssueDetailView(issue: issue, projectID: pendingIssueProjectID)
                .environmentObject(navState)
        }
        // MR navigation
        .navigationDestination(item: $pendingMR) { mr in
            MergeRequestDetailView(projectID: pendingMRProjectID, mr: mr)
                .environmentObject(navState)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilter.allCases) { filter in
                    primaryChip(filter)
                }
            }
        }
    }

    private func primaryChip(_ filter: ActivityFilter) -> some View {
        let selected = viewModel.activeFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.activeFilter = filter
            }
        } label: {
            chipLabel(icon: filter.icon, title: filter.rawValue, selected: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type Sub-filter Bar (Starred only)

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ActivityTypeFilter.allCases) { typeFilter in
                    typeChip(typeFilter)
                }
            }
        }
    }

    private func typeChip(_ typeFilter: ActivityTypeFilter) -> some View {
        let selected = viewModel.activeTypeFilter == typeFilter
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.activeTypeFilter = typeFilter
            }
        } label: {
            chipLabel(icon: typeFilter.icon, title: typeFilter.rawValue, selected: selected,
                      small: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared chip label

    private func chipLabel(icon: String, title: String, selected: Bool,
                           small: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: small ? 10 : 11, weight: .semibold))
            Text(title)
                .font(.system(size: small ? 12 : 13, weight: selected ? .semibold : .regular))
        }
        .padding(.horizontal, small ? 10 : 13)
        .padding(.vertical, small ? 6 : 8)
        .background(
            selected ? Color.accentColor.opacity(0.18) : Color.clear,
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                selected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.28),
                lineWidth: 0.5
            )
        )
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
    }

    // MARK: - Activity List

    private var activityList: some View {
        List {
            if let errorMessage = viewModel.error {
                Section {
                    ErrorBanner(message: errorMessage) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(viewModel.filteredEvents) { event in
                Button {
                    Task { await handleTap(event) }
                } label: {
                    ActivityEventRow(
                        event: event,
                        projectName: viewModel.projectName(for: event.projectID),
                        isLoading: loadingEventID == event.id
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Tap Handler

    private func handleTap(_ event: ActivityEvent) async {
        guard loadingEventID == nil else { return }

        let token   = auth.accessToken ?? ""
        let baseURL = auth.baseURL
        let pid     = event.projectID

        let targetTypeLower = event.targetType?.lowercased() ?? ""
        let projectWebURL   = viewModel.projectURL(for: pid) ?? event.resourceParent?.url ?? ""

        // ── Note / comment events ─────────────────────────────────────────────
        // GitLab sets target_type = "Note"/"DiffNote"/"DiscussionNote" for comments.
        // target_id = the note's DB id — useless for API calls.
        // The parent issue/MR IID lives in note.noteable_iid.
        if targetTypeLower == "note"
            || targetTypeLower == "diffnote"
            || targetTypeLower == "discussionnote",
           let note = event.note,
           let pid  = pid {

            let noteableType = note.noteableType?.lowercased() ?? ""

            if noteableType == "issue", let iid = note.noteableIID {
                await navigate(eventID: event.id) {
                    try await api.fetchIssue(projectID: pid, issueIID: iid,
                                              baseURL: baseURL, token: token)
                } onSuccess: { issue in
                    pendingIssueProjectID = pid
                    pendingIssue = issue
                }
                return
            }

            if (noteableType == "mergerequest" || noteableType == "merge_request"),
               let iid = note.noteableIID {
                await navigate(eventID: event.id) {
                    try await api.fetchMergeRequest(projectID: pid, mrIID: iid,
                                                    baseURL: baseURL, token: token)
                } onSuccess: { mr in
                    pendingMRProjectID = pid
                    pendingMR = mr
                }
                return
            }

            // Commit diff note or unknown noteable — open direct note URL in Safari.
            if let urlStr = note.url, let url = URL(string: urlStr) {
                openURL(url); return
            }
        }

        // ── Issue events (opened, closed, reopened, etc.) ─────────────────────
        // Tier 1: direct IID fetch (fast, exact).
        // Tier 2: title search within project (handles nil target_iid on some
        //         self-hosted GitLab versions, including close events).
        // Tier 3: Safari fallback (last resort).
        if targetTypeLower == "issue" {
            if let pid = pid, let iid = event.targetIID {
                await navigate(eventID: event.id) {
                    try await api.fetchIssue(projectID: pid, issueIID: iid,
                                              baseURL: baseURL, token: token)
                } onSuccess: { issue in
                    pendingIssueProjectID = pid
                    pendingIssue = issue
                }
            } else if let pid = pid, let title = event.targetTitle, !title.isEmpty {
                await navigate(eventID: event.id) {
                    guard let issue = try await api.fetchIssueByTitle(
                        projectID: pid, title: title, baseURL: baseURL, token: token
                    ) else { throw URLError(.cannotFindHost) }
                    return issue
                } onSuccess: { issue in
                    pendingIssueProjectID = pid
                    pendingIssue = issue
                }
            } else {
                let base   = projectWebURL.isEmpty ? baseURL : projectWebURL
                if let url = URL(string: "\(base)/-/issues") { openURL(url) }
            }
            return
        }

        // ── MR events (opened, merged, approved, closed, etc.) ────────────────
        // Same three-tier strategy as issues above.
        if targetTypeLower == "mergerequest" {
            if let pid = pid, let iid = event.targetIID {
                await navigate(eventID: event.id) {
                    try await api.fetchMergeRequest(projectID: pid, mrIID: iid,
                                                    baseURL: baseURL, token: token)
                } onSuccess: { mr in
                    pendingMRProjectID = pid
                    pendingMR = mr
                }
            } else if let pid = pid, let title = event.targetTitle, !title.isEmpty {
                await navigate(eventID: event.id) {
                    guard let mr = try await api.fetchMRByTitle(
                        projectID: pid, title: title, baseURL: baseURL, token: token
                    ) else { throw URLError(.cannotFindHost) }
                    return mr
                } onSuccess: { mr in
                    pendingMRProjectID = pid
                    pendingMR = mr
                }
            } else {
                let base   = projectWebURL.isEmpty ? baseURL : projectWebURL
                if let url = URL(string: "\(base)/-/merge_requests") { openURL(url) }
            }
            return
        }

        // ── Push events: open the branch commits page ─────────────────────────
        if event.actionName.lowercased().contains("push") {
            let branch = event.pushData?.ref ?? event.pushData?.branch ?? ""
            let urlStr = branch.isEmpty
                ? projectWebURL
                : "\(projectWebURL)/-/commits/\(branch)"
            if let url = URL(string: urlStr) { openURL(url); return }
        }

        // ── Generic fallback: project web URL ────────────────────────────────
        if let url = URL(string: projectWebURL), !projectWebURL.isEmpty {
            openURL(url)
        }
    }

    /// Shows a per-row spinner, awaits the fetch, delivers the result on MainActor.
    /// Errors are swallowed silently — the spinner disappearing is the only feedback
    /// since the source data (title, type) visible in the row gives sufficient context.
    private func navigate<T>(
        eventID: Int,
        fetch: @escaping () async throws -> T,
        onSuccess: @MainActor @escaping (T) -> Void
    ) async {
        loadingEventID = eventID
        defer { loadingEventID = nil }
        if let value = try? await fetch() {
            await MainActor.run { onSuccess(value) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            emptyTitle,
            systemImage: emptyIcon,
            description: Text(emptyDescription)
        )
    }

    private var emptyTitle: String {
        switch viewModel.activeFilter {
        case .all:             return "No Activity"
        case .yourActivity:    return "No Activity Yet"
        case .yourProjects:    return "No Project Activity"
        case .starredProjects: return "No Starred Activity"
        case .followedUsers:   return "No Following Activity"
        }
    }

    private var emptyIcon: String {
        switch viewModel.activeFilter {
        case .all:             return "waveform"
        case .yourActivity:    return "person.fill"
        case .yourProjects:    return "folder"
        case .starredProjects: return "star"
        case .followedUsers:   return "person.2"
        }
    }

    private var emptyDescription: String {
        switch viewModel.activeFilter {
        case .all:
            return "No recent activity is visible on your feed."
        case .yourActivity:
            return "You haven't pushed, commented, or opened anything recently."
        case .yourProjects:
            return "No recent activity in your projects."
        case .starredProjects:
            return "No recent activity in your starred repositories."
        case .followedUsers:
            return "No recent activity from users you follow."
        }
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        List {
            ForEach(0..<12, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10) {
                    ShimmerView()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 13).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 11).frame(maxWidth: 200)
                        ShimmerView().frame(height: 10).frame(maxWidth: 120)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .allowsHitTesting(false)
    }
}

// MARK: - Activity Event Row

struct ActivityEventRow: View {
    let event:       ActivityEvent
    let projectName: String?
    var isLoading:   Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {

            // Left — avatar with action badge
            ZStack(alignment: .bottomTrailing) {
                AvatarView(
                    urlString: event.author?.avatarURL,
                    name: event.author?.name ?? "?",
                    size: 36
                )

                ZStack {
                    Circle()
                        .fill(event.typeColor)
                        .frame(width: 16, height: 16)
                    Image(systemName: event.typeIcon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 4, y: 4)
            }
            .padding(.bottom, 4)

            // Right — content
            VStack(alignment: .leading, spacing: 3) {

                // Author + action summary
                Group {
                    Text(event.author?.name ?? event.author?.username ?? "GitLab")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    + Text(" ")
                    + Text(event.summaryLine)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

                // Push commit preview
                if let commit = event.pushData?.commitTitle, !commit.isEmpty {
                    Text(commit)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }

                // Footer — project + time
                HStack(spacing: 4) {
                    if let name = projectName ?? event.resourceParent?.fullName ?? event.resourceParent?.name {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(.quaternary)
                    }
                    Text(event.createdAt.relativeFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            // Per-row loading spinner
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
