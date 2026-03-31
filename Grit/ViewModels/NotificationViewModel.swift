import Foundation
import SwiftUI

@MainActor
final class NotificationViewModel: ObservableObject {
    @Published var notifications: [GitLabNotification] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared
    private let notificationService = NotificationService.shared

    var unreadCount: Int {
        notifications.filter { $0.unread }.count
    }

    func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            notifications = try await api.fetchNotifications(baseURL: auth.baseURL, token: token)
            notificationService.unreadCount = unreadCount
            notificationService.setBadgeCount(unreadCount)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markRead(_ notification: GitLabNotification) async {
        guard let token = auth.accessToken else { return }
        do {
            try await api.markNotificationRead(id: notification.id, baseURL: auth.baseURL, token: token)
            if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications.remove(at: idx)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
