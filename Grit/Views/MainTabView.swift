import SwiftUI

// MARK: - App Tabs

enum AppTab: Int, CaseIterable {
    case repositories = 0
    case explore      = 1
    case inbox        = 2
    case profile      = 3
    case compose      = 4
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var navState: AppNavigationState
    @EnvironmentObject var composerState: TabBarComposerState
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var inboxVM = InboxViewModel()

    @State private var selectedTab: AppTab = .repositories
    @State private var lastContentTab: AppTab = .repositories
    @State private var showActivitySheet    = false
    @State private var showProfileQR        = false
    @State private var showWIPAlert         = false
    @State private var showCreateIssueSheet = false

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var aiService = AIAssistantService.shared

    // MARK: - Context-sensitive compose appearance

    /// SF Symbol name for the compose tab, driven by which tab is active and
    /// whether a detail view has registered a compose action.
    private var composeIcon: String {
        if composerState.isVisible { return "pencil" }
        switch lastContentTab {
        case .repositories: return "magnifyingglass"
        case .explore:      return "waveform"
        case .inbox:        return "exclamationmark.bubble"
        case .profile:      return "qrcode"
        case .compose:      return "pencil"
        }
    }

    private var composeLabel: String {
        if composerState.isVisible { return "Comment" }
        switch lastContentTab {
        case .repositories: return "Search"
        case .explore:      return "Activity"
        case .inbox:        return "New Issue"
        case .profile:      return "Share"
        case .compose:      return "Compose"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if #available(iOS 18, *) {
                modernTabView
            } else {
                legacyTabView
            }

            // ── AI Slide Drawer — only when AI is user-enabled ───────
            if aiService.isUserEnabled {
                AISlideDrawer()
                    .environmentObject(navState)
                    .zIndex(10)
            }
        }
        // ── Sheets & alerts driven by the compose button ───────────────
        .sheet(isPresented: $showActivitySheet) {
            NavigationStack {
                ActivityView()
                    .environmentObject(navState)
                    .navigationTitle("Activity")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showActivitySheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showProfileQR) {
            if let user = AuthenticationService.shared.currentUser {
                ProfileQRSheet(user: user)
            }
        }
        .sheet(isPresented: $showCreateIssueSheet) {
            CreateIssueView { newIssue in
                // Refresh the inbox so the newly-created issue appears immediately.
                Task { await inboxVM.load() }
            }
        }
        .alert("Work in Progress", isPresented: $showWIPAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature is coming soon.")
        }
        // ── Lifecycle ─────────────────────────────────────────────────
        .task {
            await inboxVM.load()
            inboxVM.startPolling()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await AuthenticationService.shared.refreshOAuthTokenIfNeeded()
                    inboxVM.startPolling()
                }
            } else if phase == .inactive || phase == .background {
                inboxVM.stopPolling()
            }
        }
        .onChange(of: notificationService.pendingDeepLinkNotificationID) { _, notifID in
            guard let id = notifID else { return }
            selectedTab    = .inbox
            lastContentTab = .inbox
            inboxVM.navigateToNotification(id: id)
            notificationService.pendingDeepLinkNotificationID = nil
        }
        // ── Deep-link tab switching ────────────────────────────────────────
        .onChange(of: navState.pendingDeepLinkTab) { _, tab in
            guard let tab else { return }
            selectedTab    = tab
            lastContentTab = tab
            navState.pendingDeepLinkTab = nil
        }
        // ── Compose tab intercept ──────────────────────────────────────────
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .compose {
                selectedTab = lastContentTab
                handleComposeAction()
            } else {
                lastContentTab = newTab
            }
        }
    }

    // MARK: - Tab implementations

    /// iOS 18+ tab view using the structured Tab API.
    /// Tab(role: .search) suppresses the content flash on the compose tab.
    @available(iOS 18, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            Tab(value: AppTab.repositories) {
                RepositoryListView()
            } label: {
                tabLabel("Repos", systemImage: "square.stack.3d.up")
            }

            Tab(value: AppTab.explore) {
                ExploreView()
                    .environmentObject(navState)
            } label: {
                tabLabel("Explore", systemImage: "safari")
            }

            Tab(value: AppTab.inbox) {
                InboxView()
                    .environmentObject(inboxVM)
                    .environmentObject(navState)
            } label: {
                tabLabel("Inbox", systemImage: "tray.and.arrow.down")
            }
            .badge(inboxVM.unreadCount)

            Tab(value: AppTab.profile) {
                ProfileView()
            } label: {
                tabLabel("Profile", systemImage: "person.circle")
            }

            // role: .search suppresses the content view so the onChange
            // intercept fires before anything renders.
            Tab(value: AppTab.compose, role: .search) {
                EmptyView()
            } label: {
                tabLabel(composeLabel, systemImage: composeIcon)
            }
        }
        // Force the UIKit tab bar to re-render its items when the
        // label-visibility setting changes.
        .id(settingsStore.hideTabBarLabels)
    }

    /// iOS 17 fallback using the legacy .tabItem API.
    /// The compose tab still intercepts via onChange (on the outer ZStack) —
    /// there may be a brief flash of EmptyView before snapping back.
    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            RepositoryListView()
                .tabItem { tabLabel("Repos", systemImage: "square.stack.3d.up") }
                .tag(AppTab.repositories)

            ExploreView()
                .environmentObject(navState)
                .tabItem { tabLabel("Explore", systemImage: "safari") }
                .tag(AppTab.explore)

            InboxView()
                .environmentObject(inboxVM)
                .environmentObject(navState)
                .tabItem { tabLabel("Inbox", systemImage: "tray.and.arrow.down") }
                .tag(AppTab.inbox)
                .badge(inboxVM.unreadCount)

            ProfileView()
                .tabItem { tabLabel("Profile", systemImage: "person.circle") }
                .tag(AppTab.profile)

            EmptyView()
                .tabItem { tabLabel(composeLabel, systemImage: composeIcon) }
                .tag(AppTab.compose)
        }
        .id(settingsStore.hideTabBarLabels)
    }

    // MARK: - Compose action dispatch

    private func handleComposeAction() {
        // A detail view (Issue / MR) has registered an action — use it.
        if composerState.isVisible {
            composerState.trigger()
            return
        }
        // Otherwise dispatch based on the active content tab.
        switch lastContentTab {
        case .repositories:
            navState.triggerRepoSearch = true
        case .explore:
            showActivitySheet = true    // global activity feed
        case .inbox:
            showCreateIssueSheet = true
        case .profile:
            showProfileQR = true        // QR code share sheet
        case .compose:
            break
        }
    }

    // MARK: - Tab label helper

    /// Returns a Label that hides its title when the user has enabled icon-only mode.
    /// Using a @ViewBuilder function (rather than .id() on the TabView) means labels
    /// update live without rebuilding the entire tab hierarchy.
    @ViewBuilder
    private func tabLabel(_ title: String, systemImage: String) -> some View {
        if settingsStore.hideTabBarLabels {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

}
