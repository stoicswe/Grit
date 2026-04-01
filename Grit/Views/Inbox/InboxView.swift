import SwiftUI

struct InboxView: View {
    @EnvironmentObject var viewModel: InboxViewModel
    @EnvironmentObject var navState: AppNavigationState

    var body: some View {
        NavigationStack {
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
            .task { await viewModel.load() }
            .navigationDestination(for: MRNavigation.self) { nav in
                MergeRequestDetailView(projectID: nav.projectID, mr: nav.mr)
                    .environmentObject(navState)
            }
            .navigationDestination(for: GitLabIssue.self) { issue in
                IssueDetailView(issue: issue, projectID: issue.projectID)
                    .environmentObject(navState)
            }
        }
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

            // ── Tasks (authored AND assigned to me) ───────────────────────
            if viewModel.showTasks {
                Section {
                    ForEach(viewModel.tasks) { issue in
                        NavigationLink(value: issue) {
                            InboxIssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await viewModel.closeTask(issue) }
                            } label: {
                                Label("Close", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    inboxSectionHeader("Tasks",
                                       icon: "checkmark.square",
                                       count: viewModel.tasks.count)
                }
            }

            // ── My Open Issues (authored by me, not assigned to me) ───────
            if viewModel.showCreatedIssues {
                Section {
                    ForEach(viewModel.createdIssues) { issue in
                        NavigationLink(value: issue) {
                            InboxIssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } header: {
                    inboxSectionHeader("My Open Issues",
                                       icon: "pencil.and.list.clipboard",
                                       count: viewModel.createdIssues.count)
                }
            }

            // ── Notifications ─────────────────────────────────────────────
            if viewModel.showNotifications {
                let unread = viewModel.notifications.filter { $0.unread }
                let read   = viewModel.notifications.filter { !$0.unread }

                if !unread.isEmpty {
                    Section {
                        ForEach(unread) { notification in
                            NotificationRowView(notification: notification)
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.06))
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 4)
                                )
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
                            .font(.system(size: 13, weight: .semibold))
                            .textCase(nil)
                    }
                }

                if !read.isEmpty {
                    Section {
                        ForEach(read) { notification in
                            NotificationRowView(notification: notification)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("Earlier")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
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
        case .notifications: return "No Notifications"
        }
    }

    private var emptyIcon: String {
        switch viewModel.activeFilter {
        case .all:           return "tray"
        case .mergeRequests: return "arrow.triangle.merge"
        case .tasks:         return "checkmark.square"
        case .issues:        return "exclamationmark.circle"
        case .notifications: return "bell.slash"
        }
    }

    private var emptyDescription: String {
        switch viewModel.activeFilter {
        case .all:
            return "No MRs, issues, tasks, or notifications are waiting for you."
        case .mergeRequests:
            return "No merge requests are assigned to you or awaiting your review."
        case .tasks:
            return "No open issues are both created and assigned to you."
        case .issues:
            return "You have no open issues that you haven't already assigned to yourself."
        case .notifications:
            return "You have no pending notifications right now."
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

                if let labels = mr.labels, !labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                                    .foregroundStyle(.secondary)
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

                    if !issue.labels.isEmpty || issue.userNotesCount > 0 {
                        HStack(spacing: 6) {
                            ForEach(issue.labels.prefix(3), id: \.self) { labelChip($0) }
                            if issue.labels.count > 3 {
                                Text("+\(issue.labels.count - 3)")
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
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }

    private func labelChip(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(.tint)
    }
}
