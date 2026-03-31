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
            // Hide the system-generated tab bar — we draw our own below
            .ignoresSafeArea(edges: .bottom)
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
}
