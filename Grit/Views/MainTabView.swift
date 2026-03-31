import SwiftUI

// MARK: - App Tabs

enum AppTab: Int, CaseIterable {
    case repositories = 0
    case notifications = 1
    case profile = 2

    var title: String {
        switch self {
        case .repositories: return "Repositories"
        case .notifications: return "Notifications"
        case .profile:       return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .repositories: return "square.stack.3d.up"
        case .notifications: return "bell"
        case .profile:       return "person.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .repositories: return "square.stack.3d.up.fill"
        case .notifications: return "bell.fill"
        case .profile:       return "person.circle.fill"
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var notificationVM = NotificationViewModel()

    @State private var selectedTab: AppTab = .repositories
    @State private var showAIChat = false
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Content ──────────────────────────────────────────────
            TabView(selection: $selectedTab) {
                RepositoryListView(showSearch: $showSearch)
                    .tag(AppTab.repositories)

                NotificationsView()
                    .environmentObject(notificationVM)
                    .tag(AppTab.notifications)

                ProfileView()
                    .tag(AppTab.profile)
            }
            // Hide the system-generated tab bar — we draw our own below
            .toolbar(.hidden, for: .tabBar)
            .ignoresSafeArea(edges: .bottom)

            // ── Custom Bottom Bar ────────────────────────────────────
            customBottomBar
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
        .ignoresSafeArea(edges: .bottom)
        .task { await notificationVM.load() }
        // Search sheet — context-aware via AppNavigationState
        .sheet(isPresented: $showSearch) {
            SearchView()
                .environmentObject(navState)
        }
        // AI Assistant sheet
        .sheet(isPresented: $showAIChat) {
            AIAssistantChatView()
                .environmentObject(navState)
        }
    }

    // MARK: - Custom Bottom Bar

    private var customBottomBar: some View {
        HStack(spacing: 12) {

            // ── 3-together pill ──────────────────────────────────────
            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Button {
                        withAnimation(.spring(duration: 0.22)) {
                            selectedTab = tab
                        }
                    } label: {
                        ZStack {
                            // Active indicator capsule
                            if selectedTab == tab {
                                Capsule()
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 46, height: 32)
                                    .transition(.scale.combined(with: .opacity))
                            }

                            Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                                .font(.system(size: 17, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .frame(width: 46, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        // Notification badge dot
                        if tab == .notifications, notificationService.unreadCount > 0 {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1))
                                .offset(x: 4, y: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 56)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)

            Spacer()

            // ── AI Sparkle button ────────────────────────────────────
            Button {
                showAIChat = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                        .shadow(color: .accentColor.opacity(0.25), radius: 10, y: 4)

                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .buttonStyle(.plain)
        }
    }
}
