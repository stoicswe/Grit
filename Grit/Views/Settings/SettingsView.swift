import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var notificationService: NotificationService
    @State private var showLogoutAlert = false
    @State private var notificationSettings: NotificationSettings = NotificationSettings()

    var body: some View {
        NavigationStack {
            List {
                // Account section
                accountSection

                // Appearance section
                appearanceSection

                // Notifications section
                notificationsSection

                // AI Assistant section
                aiSection

                // About section
                aboutSection

                // Danger zone
                dangerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                notificationSettings = settingsStore.notificationSettings
            }
            .alert("Sign Out", isPresented: $showLogoutAlert) {
                Button("Sign Out", role: .destructive) {
                    authService.logout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter your access token again to sign back in.")
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            if let user = authService.currentUser {
                HStack(spacing: 14) {
                    AvatarView(urlString: user.avatarURL, name: user.name, size: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name)
                            .font(.system(size: 16, weight: .semibold))
                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(authService.baseURL)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            HStack {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                Spacer()
                Picker("Appearance", selection: $settingsStore.appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your device's appearance settings.")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            if !notificationService.isAuthorized {
                Button {
                    Task { await notificationService.requestAuthorization() }
                } label: {
                    Label("Enable Push Notifications", systemImage: "bell.badge")
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                notificationToggle(
                    title: "Merge Requests",
                    subtitle: "New and updated MRs",
                    icon: "arrow.triangle.merge",
                    isOn: Binding(
                        get: { notificationSettings.mergeRequestEvents },
                        set: { notificationSettings.mergeRequestEvents = $0; save() }
                    )
                )
                notificationToggle(
                    title: "Issues",
                    subtitle: "New issues and assignments",
                    icon: "exclamationmark.circle",
                    isOn: Binding(
                        get: { notificationSettings.issueEvents },
                        set: { notificationSettings.issueEvents = $0; save() }
                    )
                )
                notificationToggle(
                    title: "Pipelines",
                    subtitle: "Build success and failures",
                    icon: "gearshape.2",
                    isOn: Binding(
                        get: { notificationSettings.pipelineEvents },
                        set: { notificationSettings.pipelineEvents = $0; save() }
                    )
                )
                notificationToggle(
                    title: "Comments",
                    subtitle: "New comments on your work",
                    icon: "bubble.left",
                    isOn: Binding(
                        get: { notificationSettings.noteEvents },
                        set: { notificationSettings.noteEvents = $0; save() }
                    )
                )
                notificationToggle(
                    title: "Push Events",
                    subtitle: "New commits pushed",
                    icon: "arrow.up.circle",
                    isOn: Binding(
                        get: { notificationSettings.pushEvents },
                        set: { notificationSettings.pushEvents = $0; save() }
                    )
                )
            }
        } header: {
            Text("Notifications")
        } footer: {
            if notificationService.isAuthorized {
                Text("Only repositories you've subscribed to will send notifications. Toggle subscriptions in each repository's detail view.")
            }
        }
    }

    private func notificationToggle(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            NavigationLink {
                AIAssistantChatView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Assistant")
                            .font(.system(size: 15))
                        Text(AIAssistantService.shared.isAvailable
                             ? "Apple Intelligence · On-device"
                             : "Not available on this device")
                            .font(.caption)
                            .foregroundStyle(AIAssistantService.shared.isAvailable ? .green : .secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
        } header: {
            Text("Intelligence")
        } footer: {
            Text("AI features use Apple Intelligence on-device models. No data is sent to external servers.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("GitLab API") {
                Text("v4")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Instance") {
                Text(authService.baseURL)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Danger Zone

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showLogoutAlert = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func save() {
        settingsStore.notificationSettings = notificationSettings
    }
}
