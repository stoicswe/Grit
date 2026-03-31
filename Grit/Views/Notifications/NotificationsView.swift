import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var viewModel: NotificationViewModel
    @EnvironmentObject var notificationService: NotificationService

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    loadingView
                } else if viewModel.notifications.isEmpty {
                    emptyView
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    // MARK: - List

    private var notificationList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            let unread = viewModel.notifications.filter { $0.unread }
            let read = viewModel.notifications.filter { !$0.unread }

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
                        .foregroundStyle(.accentColor)
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty

    private var emptyView: some View {
        ContentUnavailableView {
            Label("All Caught Up", systemImage: "bell.badge.slash")
        } description: {
            Text("No notifications right now.")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView().frame(width: 36, height: 36).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerView().frame(height: 13).frame(maxWidth: .infinity)
                        ShimmerView().frame(height: 10).frame(maxWidth: 160)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Row

struct NotificationRowView: View {
    let notification: GitLabNotification

    var icon: String {
        switch notification.targetType?.lowercased() {
        case "mergerequest": return "arrow.triangle.merge"
        case "issue": return "exclamationmark.circle"
        case "commit": return "clock.arrow.circlepath"
        case "pipeline": return "gearshape.2"
        case "note": return "bubble.left"
        default: return "bell"
        }
    }

    var iconColor: Color {
        switch notification.targetType?.lowercased() {
        case "mergerequest": return .purple
        case "issue": return .orange
        case "commit": return .blue
        case "pipeline": return notification.body.lowercased().contains("fail") ? .red : .green
        case "note": return .teal
        default: return .accentColor
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.body)
                    .font(.system(size: 14, weight: notification.unread ? .semibold : .regular))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if let project = notification.project {
                        Text(project.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                    }
                    Text(notification.createdAt.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if notification.unread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 2)
    }
}
