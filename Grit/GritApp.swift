import SwiftUI

@main
struct GritApp: App {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var settingsStore = SettingsStore.shared
    @StateObject private var navState = AppNavigationState.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .environmentObject(authService)
            .environmentObject(notificationService)
            .environmentObject(settingsStore)
            .environmentObject(navState)
            .preferredColorScheme(settingsStore.colorScheme)
            .tint(settingsStore.accentColor ?? Color.accentColor)
            .task {
                await notificationService.requestAuthorization()
            }
        }
    }
}
