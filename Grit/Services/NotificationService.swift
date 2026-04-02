import Foundation
import UserNotifications
import SwiftUI

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized = false
    @Published var unreadCount: Int = 0

    /// Set by the UNUserNotificationCenterDelegate when the user taps a system banner.
    /// MainTabView observes this to switch to the Inbox tab and deep-link to the item.
    @Published var pendingDeepLinkNotificationID: Int?

    private override init() {
        super.init()
        // Register as delegate so iOS delivers banners while the app is foregrounded.
        UNUserNotificationCenter.current().delegate = self
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

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Called when a notification arrives while the app is in the foreground.
    /// Returning [.banner, .sound, .badge] makes it behave the same as a background delivery.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when the user taps a notification banner or lock-screen notification.
    /// Extracts the Grit notification ID from userInfo and publishes it so
    /// MainTabView can switch to the Inbox tab and deep-link to the correct item.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let notifID = userInfo["grit.notificationId"] as? Int {
            Task { @MainActor in
                self.pendingDeepLinkNotificationID = notifID
            }
        }
        completionHandler()
    }
}
