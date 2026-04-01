import SwiftUI
import BackgroundTasks

@main
struct GritApp: App {
    @StateObject private var authService        = AuthenticationService.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var settingsStore      = SettingsStore.shared
    @StateObject private var navState           = AppNavigationState.shared

    @Environment(\.scenePhase) private var scenePhase

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
                // Queue the first background refresh as soon as the app is running.
                BackgroundRefreshService.shared.scheduleNextRefresh()
            }
        }
        // Re-schedule whenever the app moves to the background.
        // iOS requires this to keep the task queue alive after each run.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundRefreshService.shared.scheduleNextRefresh()
            }
        }
        // Register the background refresh handler with the system.
        // The .backgroundTask modifier handles BGTaskScheduler registration automatically.
        .backgroundTask(.appRefresh(BackgroundRefreshService.taskIdentifier)) {
            await BackgroundRefreshService.shared.performRefresh()
        }
    }
}
