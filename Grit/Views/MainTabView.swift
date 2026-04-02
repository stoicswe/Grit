import SwiftUI

// MARK: - App Tabs

enum AppTab: Int, CaseIterable {
    case repositories = 0
    case explore      = 1
    case inbox        = 2
    case profile      = 3

    var title: String {
        switch self {
        case .repositories: return "Repositories"
        case .explore:      return "Explore"
        case .inbox:        return "Inbox"
        case .profile:      return "Profile"
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var inboxVM = InboxViewModel()

    @State private var selectedTab: AppTab = .repositories
    @State private var showAIChat = false

    @ObservedObject private var aiService = AIAssistantService.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            // ── Native TabView ────────────────────────────────────────
            TabView(selection: $selectedTab) {
                Tab("Repositories", systemImage: "square.stack.3d.up", value: AppTab.repositories) {
                    RepositoryListView()
                }

                Tab("Explore", systemImage: "safari", value: AppTab.explore) {
                    ExploreView()
                        .environmentObject(navState)
                }

                Tab("Inbox", systemImage: "tray.and.arrow.down", value: AppTab.inbox) {
                    InboxView()
                        .environmentObject(inboxVM)
                        .environmentObject(navState)
                }
                .badge(inboxVM.unreadCount)

                Tab("Profile", systemImage: "person.circle", value: AppTab.profile) {
                    ProfileView()
                }
            }

            // ── Floating AI Panel — only when AI is user-enabled ──────
            if aiService.isUserEnabled {
                if showAIChat {
                    AIFloatingPanel(isPresented: $showAIChat)
                        .environmentObject(navState)
                        .zIndex(10)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal:   .move(edge: .bottom).combined(with: .opacity)
                        ))
                }

                // ── AI Circle Button (floats above tab bar, far right) ──
                aiCircleButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)   // clears the native tab bar + home indicator
                    .zIndex(20)
            }
        }
        // Close the panel if the user disables AI while it's open
        .onChange(of: aiService.isUserEnabled) { _, enabled in
            if !enabled { showAIChat = false }
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: showAIChat)
    }

    // MARK: - AI Circle Button

    private var aiCircleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                showAIChat.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                showAIChat
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [.accentColor, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.white.opacity(0.15)),
                                lineWidth: showAIChat ? 1.5 : 0.5
                            )
                    )
                    .shadow(
                        color: Color.accentColor.opacity(showAIChat ? 0.45 : 0.18),
                        radius: 14, y: 4
                    )

                Image(systemName: showAIChat ? "xmark" : "sparkles")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .animation(.spring(duration: 0.25), value: showAIChat)
            }
        }
        .buttonStyle(.plain)
    }
}
