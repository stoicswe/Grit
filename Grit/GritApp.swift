import AppIntents
import BackgroundTasks
import SwiftUI

// Conditionally applies a transform only when the optional value is non-nil.
// Used to apply `.environment(\.dynamicTypeSize)` only when the user has
// explicitly chosen a size (non-System), preserving the OS setting otherwise.
private extension View {
    @ViewBuilder
    func ifLet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

@main
struct GritApp: App {
    @StateObject private var authService        = AuthenticationService.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var settingsStore      = SettingsStore.shared
    @StateObject private var navState           = AppNavigationState.shared
    @StateObject private var composerState      = TabBarComposerState.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isRestoringSession {
                    SplashView()
                } else if authService.isAuthenticated {
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
            .environmentObject(composerState)
            .preferredColorScheme(settingsStore.colorScheme)
            .tint(settingsStore.accentColor ?? Color.accentColor)
            // Handle grit:// deep links (Option 1 custom URL scheme) and
            // https:// links forwarded by the Grit Share Extension (Option 2).
            .onOpenURL { url in
                DeepLinkHandler.shared.handle(url: url)
            }
            // Accessibility — font propagates to Text views without an explicit font;
            // dynamicTypeSize scales every text in the app (skipped at Default so
            // the user's iOS accessibility setting is preserved).
            .environment(\.font, settingsStore.fontStyle.environmentFont)
            .ifLet(settingsStore.fontSizeStep.asDynamicTypeSize) { view, size in
                view.environment(\.dynamicTypeSize, size)
            }
            .task {
                await notificationService.requestAuthorization()
                // Queue both background tasks as soon as the app is running.
                BackgroundRefreshService.shared.scheduleNextRefresh()
                WatchedRepoNotificationService.shared.scheduleNextPoll()
                // Update Siri / Shortcuts with the latest App Intents metadata.
                GritShortcutsProvider.updateAppShortcutParameters()
            }
        }
        // Scene-phase transitions.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Re-schedule both background tasks — iOS requires re-submission
                // every time the app enters the background to keep the queue alive.
                BackgroundRefreshService.shared.scheduleNextRefresh()
                WatchedRepoNotificationService.shared.scheduleNextPoll()

            case .active:
                // App has returned to the foreground (from background suspension
                // or after iOS killed and relaunched it).  Silently refresh the
                // OAuth token if it expired while the app was away, then do a
                // lightweight session ping.  The user is only sent to the login
                // screen if the session is genuinely unrecoverable; a brief
                // network outage will never log them out.
                Task { await authService.refreshSessionOnForeground() }
                // Warm the cache for the repos the ML model predicts the user
                // will open this session, so tapping them feels instant.
                Task(priority: .background) {
                    await RepoPrefetchService.shared.prefetchOnForeground()
                }

            default:
                break
            }
        }
        // Register background task handlers.
        // The .backgroundTask modifier handles BGTaskScheduler registration automatically.
        .backgroundTask(.appRefresh(BackgroundRefreshService.taskIdentifier)) {
            await BackgroundRefreshService.shared.performRefresh()
        }
        // Polls watched-repo project events every ~30 minutes and delivers
        // local notifications filtered by the user's notification settings.
        .backgroundTask(.appRefresh(WatchedRepoNotificationService.taskIdentifier)) {
            await WatchedRepoNotificationService.shared.performPoll()
        }
    }
}
