import SwiftUI

struct InboxView: View {
    @EnvironmentObject var viewModel: InboxViewModel
    @EnvironmentObject var navState: AppNavigationState

    @State private var showNotificationPanel = false

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)

                Divider()

                if viewModel.isLoading && viewModel.isEmpty && viewModel.error == nil {
                    loadingSkeleton
                } else if viewModel.isEmpty && !viewModel.isLoading {
                    // Always show an error banner if one exists, even over the empty state.
                    if let errorMessage = viewModel.error {
                        ScrollView {
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
                        }
                        .refreshable { await viewModel.load() }
                    } else {
                        ScrollView {
                            emptyState
                        }
                        .refreshable { await viewModel.load() }
                    }
                } else {
                    inboxList
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
                            showNotificationPanel.toggle()
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: showNotificationPanel ? "bell.fill" : "bell")
                                .symbolEffect(.bounce, value: showNotificationPanel)
                            if viewModel.unreadCount > 0 {
                                Text(viewModel.unreadCount < 100 ? "\(viewModel.unreadCount)" : "99+")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 8, y: -6)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: MRNavigation.self) { nav in
                MergeRequestDetailView(projectID: nav.projectID, mr: nav.mr)
                    .environmentObject(navState)
            }
            .navigationDestination(for: GitLabIssue.self) { issue in
                IssueDetailView(issue: issue, projectID: issue.projectID)
                    .environmentObject(navState)
                    .onDisappear { viewModel.refreshAfterDetailDismiss() }
            }
            .navigationDestination(for: GitLabNotification.self) { notification in
                NotificationTargetView(notification: notification)
                    .environmentObject(navState)
                    .environmentObject(viewModel)
            }
        }
        // ── Overlay 1: full-screen dim (behind panel) ─────────────────────
        .overlay {
            if showNotificationPanel {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                            showNotificationPanel = false
                        }
                    }
                    .transition(.opacity)
            }
        }
        // ── Overlay 2: panel (drawn on top of dim) ────────────────────────
        // padding(.top, 52) = 44 pt nav bar + 8 pt gap; the overlay coordinate
        // space starts at the nav bar's top edge (bottom of status bar).
        .overlay(alignment: .top) {
            if showNotificationPanel {
                NotificationPanel(isPresented: $showNotificationPanel)
                    .environmentObject(viewModel)
                    .padding(.top, 52)
                    .transition(
                        .scale(scale: 0.82, anchor: .topTrailing)
                        .combined(with: .opacity)
                    )
            }
        }
        .animation(.spring(duration: 0.38, bounce: 0.12), value: showNotificationPanel)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InboxFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: InboxFilter) -> some View {
        let selected = viewModel.activeFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.activeFilter = filter
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(filter.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
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
        .buttonStyle(.plain)
    }

    // MARK: - Inbox List

    private var inboxList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // ── Incidents ─────────────────────────────────────────────────
            if viewModel.showIncidents {
                Section {
                    ForEach(viewModel.incidentItems) { issue in
                        NavigationLink(value: issue) {
                            InboxIssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.red.opacity(0.05))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await viewModel.closeIssue(issue) }
                            } label: {
                                Label("Close", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    inboxSectionHeader("Incidents", icon: "flame", count: viewModel.incidentItems.count)
                        .foregroundStyle(.red)
                }
            }

            // ── Review Requested ──────────────────────────────────────────
            if viewModel.showReviewerMRs {
                Section {
                    ForEach(viewModel.reviewerMRs) { mr in
                        NavigationLink(value: MRNavigation(projectID: mr.projectID, mr: mr)) {
                            InboxMRRow(mr: mr, role: .reviewer)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } header: {
                    inboxSectionHeader("Review Requested",
                                       icon: "person.crop.circle.badge.checkmark",
                                       count: viewModel.reviewerMRs.count)
                }
            }

            // ── Assigned MRs ──────────────────────────────────────────────
            if viewModel.showAssignedMRs {
                Section {
                    ForEach(viewModel.assignedMRs) { mr in
                        NavigationLink(value: MRNavigation(projectID: mr.projectID, mr: mr)) {
                            InboxMRRow(mr: mr, role: .assignee)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } header: {
                    inboxSectionHeader("Assigned Merge Requests",
                                       icon: "arrow.triangle.merge",
                                       count: viewModel.assignedMRs.count)
                }
            }

            // ── Tasks (issueType == "task") ───────────────────────────────
            if viewModel.showTasks {
                Section {
                    ForEach(viewModel.taskTypeIssues) { issue in
                        NavigationLink(value: issue) {
                            InboxIssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await viewModel.closeIssue(issue) }
                            } label: {
                                Label("Close", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    inboxSectionHeader("Tasks",
                                       icon: "checkmark.square",
                                       count: viewModel.taskTypeIssues.count)
                }
            }

            // ── My Open Issues (standard issues, authored by me) ──────────
            if viewModel.showCreatedIssues {
                let displayIssues = (viewModel.tasks + viewModel.createdIssues)
                    .filter { $0.issueType != "incident" && $0.issueType != "task" }
                Section {
                    ForEach(displayIssues) { issue in
                        NavigationLink(value: issue) {
                            InboxIssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await viewModel.closeIssue(issue) }
                            } label: {
                                Label("Close", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    inboxSectionHeader("My Open Issues",
                                       icon: "pencil.and.list.clipboard",
                                       count: displayIssues.count)
                }
            }

        }
        .listStyle(.plain)
        .refreshable { await viewModel.load() }
    }

    // MARK: - Section Header

    private func inboxSectionHeader(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(count)")
                .font(.system(size: 11))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.top, 4)
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
        case .all:           return "All Caught Up"
        case .mergeRequests: return "No Merge Requests"
        case .tasks:         return "No Tasks"
        case .issues:        return "No Open Issues"
        case .incidents:     return "No Incidents"
        }
    }

    private var emptyIcon: String {
        switch viewModel.activeFilter {
        case .all:           return "tray"
        case .mergeRequests: return "arrow.triangle.merge"
        case .tasks:         return "checkmark.square"
        case .issues:        return "exclamationmark.circle"
        case .incidents:     return "flame"
        }
    }

    private var emptyDescription: String {
        switch viewModel.activeFilter {
        case .all:
            return "No MRs, issues, or tasks are waiting for you."
        case .mergeRequests:
            return "No merge requests are assigned to you or awaiting your review."
        case .tasks:
            return "No open issues are both created and assigned to you."
        case .issues:
            return "You have no open issues that you haven't already assigned to yourself."
        case .incidents:
            return "No incidents are assigned to you or authored by you."
        }
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        List {
            ForEach(0..<10, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    ShimmerView()
                        .frame(width: 10, height: 10)
                        .clipShape(Circle())
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 11).frame(maxWidth: 200)
                        ShimmerView().frame(height: 10).frame(maxWidth: 140)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .allowsHitTesting(false)
    }
}

// MARK: - Inbox MR Row

private enum InboxMRRole { case reviewer, assignee }

private struct InboxMRRow: View {
    let mr:   MergeRequest
    let role: InboxMRRole

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .top, spacing: 8) {
                    MRStateBadge(state: mr.state)

                    if role == .reviewer {
                        Text("Review")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }

                    if mr.isDraft {
                        Text("Draft")
                            .font(.system(size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Text("!\(mr.iid)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(mr.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if let path = mr.projectPath {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    branchTag(mr.sourceBranch)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    branchTag(mr.targetBranch)
                }

                HStack(spacing: 8) {
                    AvatarView(urlString: mr.author.avatarURL, name: mr.author.name, size: 20)
                    Text(mr.author.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mr.updatedAt.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let details = mr.labelDetails, !details.isEmpty {
                    let fallback = SettingsStore.shared.accentColor ?? Color.accentColor
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(details) { detail in
                                let c = detail.swiftUIColor(fallback: fallback)
                                Text(detail.name)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(c.opacity(0.15), in: Capsule())
                                    .foregroundStyle(c)
                            }
                        }
                    }
                }
            }
        }
    }

    private func branchTag(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Inbox Issue Row

private struct InboxIssueRow: View {
    let issue: GitLabIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(issue.isOpen ? Color.green : Color.purple)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let path = issue.projectPath {
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Text("#\(issue.iid)")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                        Text(issue.author.name)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Text("·").foregroundStyle(.quaternary)
                        Text(issue.updatedAt.relativeFormatted)
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }

                    if !issue.labelDetails.isEmpty || issue.userNotesCount > 0 {
                        HStack(spacing: 6) {
                            ForEach(Array(issue.labelDetails.prefix(3))) { labelChip($0) }
                            if issue.labelDetails.count > 3 {
                                Text("+\(issue.labelDetails.count - 3)")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if issue.userNotesCount > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "bubble.right").font(.system(size: 10))
                                    Text("\(issue.userNotesCount)").font(.system(size: 11))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)

            // ── Task completion summary ───────────────────────────────
            // Driven by `task_completion_status` from the API — works for both
            // markdown `- [ ]` items and linked child task-type issues.
            if let tcs = issue.taskCompletionStatus, tcs.count > 0 {
                let allDone = tcs.completedCount == tcs.count
                Divider()
                    .opacity(0.25)
                    .padding(.horizontal, 12)
                HStack(spacing: 5) {
                    Image(systemName: allDone ? "checkmark.square.fill" : "checkmark.square")
                        .font(.system(size: 11))
                        .foregroundStyle(allDone ? .green : .secondary)
                    Text("\(tcs.completedCount) of \(tcs.count) tasks completed")
                        .font(.system(size: 11))
                        .foregroundStyle(allDone ? .green : .secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }

    private func labelChip(_ detail: IssueLabelDetail) -> some View {
        let fallback = SettingsStore.shared.accentColor ?? Color.accentColor
        let c = detail.swiftUIColor(fallback: fallback)
        return Text(detail.name).font(.system(size: 10)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.15), in: Capsule())
            .foregroundStyle(c)
    }
}

// MARK: - Notification Panel

/// A Liquid Glass floating panel that expands from the bell button.
/// Shows all notifications split into unread / earlier sections;
/// each row can be swiped trailing to mark as done and dismiss it.
private struct NotificationPanel: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var viewModel: InboxViewModel
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var userColor: Color { settingsStore.accentColor ?? .accentColor }

    private var unread: [GitLabNotification] { viewModel.notifications.filter {  $0.unread } }
    private var read:   [GitLabNotification] { viewModel.notifications.filter { !$0.unread } }
    private var all:    [GitLabNotification] { viewModel.notifications }

    // ── Height calculation ────────────────────────────────────────────────
    private let panelHeaderH: CGFloat = 58   // top pad + content + bottom pad
    private let emptyStateH:  CGFloat = 110  // empty bell state minimum

    /// Maximum height the list is allowed to grow to.
    private var maxListH: CGFloat {
        UIScreen.main.bounds.height * 0.75 - panelHeaderH
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(userColor)
                Text("Notifications")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                if !unread.isEmpty {
                    Button {
                        Task {
                            for n in unread { await viewModel.markRead(n) }
                        }
                    } label: {
                        Text("Mark All Read")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            // ── Content ───────────────────────────────────────────────────
            if all.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No Notifications")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: emptyStateH)
            } else {
                List {
                    // Unread section
                    if !unread.isEmpty {
                        Section {
                            ForEach(unread) { notification in
                                NotificationRowView(notification: notification)
                                    .listRowBackground(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.07))
                                            .padding(.vertical, 2)
                                            .padding(.horizontal, 4)
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            Task { await viewModel.markRead(notification) }
                                        } label: {
                                            Label("Done", systemImage: "checkmark")
                                        }
                                        .tint(.green)
                                    }
                            }
                        } header: {
                            Label("Unread · \(unread.count)", systemImage: "circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.system(size: 12, weight: .semibold))
                                .textCase(nil)
                        }
                    }

                    // Read / earlier section
                    if !read.isEmpty {
                        Section {
                            ForEach(read) { notification in
                                NotificationRowView(notification: notification)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            // Already read — swipe removes from view
                                            Task { await viewModel.markRead(notification) }
                                        } label: {
                                            Label("Dismiss", systemImage: "xmark")
                                        }
                                    }
                            }
                        } header: {
                            Text("Earlier")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: maxListH)
            }
        }
        .frame(maxWidth: .infinity)
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .regularGlassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 28, x: 0, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 12)
    }
}
