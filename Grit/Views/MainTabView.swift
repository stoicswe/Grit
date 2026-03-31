import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var notificationService: NotificationService
    @StateObject private var notificationVM = NotificationViewModel()

    var body: some View {
        TabView {
            Tab("Repositories", systemImage: "square.stack.3d.up") {
                RepositoryListView()
            }
            Tab("Profile", systemImage: "person.circle") {
                ProfileView()
            }
            Tab("Notifications", systemImage: "bell") {
                NotificationsView()
                    .environmentObject(notificationVM)
            }
            .badge(notificationService.unreadCount > 0 ? notificationService.unreadCount : 0)
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .task {
            await notificationVM.load()
        }
    }
}
