import SwiftUI

@main
struct GritApp: App {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var settingsStore = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authService)
            .environmentObject(notificationService)
            .environmentObject(settingsStore)
            .preferredColorScheme(settingsStore.colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didFinishLaunchingNotification)) { _ in
                Task {
                    await notificationService.requestAuthorization()
                }
            }
        }
    }
}
