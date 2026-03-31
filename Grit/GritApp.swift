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
            .task {
                await notificationService.requestAuthorization()
            }
        }
    }
}
