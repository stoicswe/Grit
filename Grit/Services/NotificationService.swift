import Foundation
import UserNotifications
import SwiftUI

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized = false
    @Published var unreadCount: Int = 0

    private init() {
        Task { await checkAuthorizationStatus() }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func scheduleLocalNotification(title: String, body: String, identifier: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func setBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
