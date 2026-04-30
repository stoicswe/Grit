import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var notificationService: NotificationService
    @Environment(\.openURL) private var openURL
    @State private var showLogoutAlert = false
    @State private var notificationSettings: NotificationSettings = NotificationSettings()
    @State private var selectedAccentColor: Color = .accentColor
    @State private var showDeveloperBio = false
    @State private var showTipJar       = false
    @State private var showReportIssue  = false
    @State private var showLicense      = false

    var body: some View {
        NavigationStack {
            List {
                // Account section
                accountSection

                // Appearance section
                appearanceSection

                // Accent color section
                colorSection

                // Accessibility section
                accessibilitySection

                // Notifications section
                notificationsSection

                // Files section
                filesSection

                // Translation section (standalone, always visible)
                translationSection

                // AI Assistant section
                aiSection

                // About section
                aboutSection

                // Support / developer section
                supportSection

                // Danger zone
                dangerSection

                // GitLab account management (delete account, etc.)
                gitlabAccountSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                notificationSettings = settingsStore.notificationSettings
                selectedAccentColor = settingsStore.accentColor ?? .accentColor
            }
            .onChange(of: selectedAccentColor) { _, newColor in
                settingsStore.setAccentColor(newColor)
            }
            .sheet(isPresented: $showDeveloperBio) { DeveloperView() }
            .sheet(isPresented: $showTipJar)       { TipJarView() }
            .sheet(isPresented: $showReportIssue)  { ReportIssueView() }
            .sheet(isPresented: $showLicense)      { LicenseView() }
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

            Toggle(isOn: $settingsStore.hideTabBarLabels) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide Tab Bar Labels")
                            .font(.system(size: 15))
                        Text("Show icons only in the navigation bar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "dock.rectangle")
                }
            }

        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your device's appearance settings.")
        }
    }

    // MARK: - Accessibility

    private var accessibilitySection: some View {
        Section {
            // ── Font style ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Font Style")
                        .font(.system(size: 15))
                } icon: {
                    Image(systemName: "textformat")
                }

                HStack(spacing: 8) {
                    ForEach(FontStyle.allCases) { style in
                        let isSelected = settingsStore.fontStyle == style
                        Button {
                            settingsStore.fontStyle = style
                        } label: {
                            VStack(spacing: 6) {
                                Text("Aa")
                                    .font(style.previewFont(size: 20))
                                    .fontWeight(.medium)
                                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                Text(style.displayName)
                                    .font(style.previewFont(size: 11))
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected
                                          ? Color.accentColor.opacity(0.12)
                                          : Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(settingsStore.fontStyle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 4)

            // ── Text size slider ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label {
                        Text("Text Size")
                            .font(.system(size: 15))
                    } icon: {
                        Image(systemName: "textformat.size")
                    }
                    Spacer()
                    Text(settingsStore.fontSizeStep.fontSizeLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .animation(.easeInOut(duration: 0.15), value: settingsStore.fontSizeStep)
                }

                // Slider — snaps to whole steps via step: 1
                HStack(spacing: 8) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: $settingsStore.fontSizeStep, in: 0...4, step: 1)
                        .tint(Color.accentColor)
                    Image(systemName: "textformat.size")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }

                // Step labels beneath the slider
                HStack(spacing: 0) {
                    ForEach(["XS", "S", "Default", "L", "XL"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(
                                settingsStore.fontSizeStep.fontSizeLabel == label
                                    ? Color.accentColor : Color.secondary.opacity(0.4)
                            )
                            .frame(maxWidth: .infinity)
                    }
                }

                // Live preview sentence
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("The quick brown fox jumps over the lazy dog")
                        .font(settingsStore.fontStyle.previewFont(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)

        } header: {
            Text("Accessibility")
        } footer: {
            Text("Font style and text size apply throughout the app. 'Default' size honours your iOS Accessibility text setting.")
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Markdown Default View")
                            .font(.system(size: 15))
                        Text("How .md files open by default")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.richtext")
                }
                Spacer()
                Picker("Markdown Default View", selection: $settingsStore.markdownDefaultViewRaw) {
                    ForEach(MarkdownDefaultView.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        } header: {
            Text("Files")
        } footer: {
            Text("Source shows raw text with syntax highlighting. Reader renders the document with formatted typography. You can switch between them using the \(Image(systemName: "doc.richtext")) button in any markdown file.")
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
                Text("Push notifications are sent for repositories you're watching on GitLab. Toggle watch status from the ••• menu in any repository.")
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

    // MARK: - Accent Color

    private var colorSection: some View {
        Section {
            HStack {
                Label("Highlight Color", systemImage: "paintpalette.fill")
                Spacer()
                ColorPicker("", selection: $selectedAccentColor, supportsOpacity: false)
                    .labelsHidden()
            }

            if settingsStore.accentColor != nil {
                Button(role: .destructive) {
                    settingsStore.setAccentColor(nil)
                    selectedAccentColor = .accentColor
                } label: {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Accent Color")
        } footer: {
            Text("Sets the highlight color used throughout the app for buttons, links, and interactive elements.")
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            Toggle(isOn: $settingsStore.appleIntelligenceEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence")
                            .font(.system(size: 15))
                        Text(AIAssistantService.shared.isAvailable
                             ? "On-device · Private"
                             : "Not available on this device")
                            .font(.caption)
                            .foregroundStyle(AIAssistantService.shared.isAvailable ? .green : .secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
            .disabled(!AIAssistantService.shared.isAvailable)

            NavigationLink { AppleIntelligenceInfoView() } label: {
                Label("About Apple Intelligence", systemImage: "info.circle")
            }
        } header: {
            Text("Intelligence")
        } footer: {
            if !AIAssistantService.shared.isAvailable {
                Text("Apple Intelligence requires iPhone 16 or later running iOS 18.1 or later.")
            } else if settingsStore.appleIntelligenceEnabled {
                Text("AI-powered features — commit explanations, code review, and the AI chat panel — are active. All processing runs entirely on-device.")
            } else {
                Text("When enabled, AI-powered features like commit explanations, code review, and the AI assistant panel will appear throughout the app. All processing is done on-device.")
            }
        }
    }

    // MARK: - Translation

    private var translationSection: some View {
        Section {
            Toggle(isOn: $settingsStore.translateCommentsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Translate Comments")
                            .font(.system(size: 15))
                        Text("Detect & translate foreign-language comments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "translate")
                }
            }
        } header: {
            Text("Translation")
        } footer: {
            Text("When enabled, issue comments written in a different language than your device will show a Translate button. Translation runs on-device using Apple's Translation framework — completely private, no text is ever sent to a server.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            Button { showLicense = true } label: {
                HStack {
                    Text("License")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("MIT / Apache 2.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
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

    // MARK: - Support

    private var supportSection: some View {
        Section {
            // Developer bio
            Button { showDeveloperBio = true } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Made by Nathaniel Knudsen")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Text("About the developer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.fill")
                }
            }

            // Report an issue
            Button { showReportIssue = true } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Report an Issue")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Text("Send logs to the developer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.bubble")
                }
            }

            // Tip jar
            Button { showTipJar = true } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Buy a Coffee")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Text("Support development")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cup.and.saucer.fill")
                }
            }
        } header: {
            Text("Support")
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

    // MARK: - GitLab Account

    private var gitlabAccountSection: some View {
        Section {
            Button {
                let trimmed = authService.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let url = URL(string: "\(trimmed)/-/profile/account") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage GitLab Account")
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Text("Open account settings to delete your account")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("GitLab Account")
        } footer: {
            Text("Account deletion is handled on the GitLab website. This will open your account settings in the browser.")
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
