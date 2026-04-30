import SafariServices
import SwiftUI
import UIKit

// MARK: - Login View (Landing)

struct LoginView: View {
    @EnvironmentObject var authService: AuthenticationService

    @State private var isLoggingIn        = false
    @State private var errorMessage:      String?
    @State private var navigateToAdvanced = false
    @State private var showGitLabInfo     = false
    @State private var showAdvancedInfo   = false

    private var gitLabComOAuthReady: Bool {
        !OAuthService.gitLabComClientID.hasPrefix("YOUR_")
    }

    var body: some View {
        // ── Transition ZStack — safe-area-aware layout root ─────────────────
        // Background views live as stable bottom siblings of the same ZStack
        // (rather than inside `.background { ... }`).  On iOS 26 real devices,
        // a `GeometryReader` + `.task` placed inside a `.background` closure can
        // be deferred or never fire, leaving HelloWorldBackground frozen with
        // zero bubbles.  Keeping it as a normal sibling guarantees its lifecycle
        // hooks run, while `.ignoresSafeArea()` on each background layer keeps
        // the safe-area geometry seen by the foreground content unaffected.
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            HelloWorldBackground()
                .ignoresSafeArea()

            if navigateToAdvanced {
                AdvancedLoginView(onBack: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        navigateToAdvanced = false
                    }
                })
                    // Slides in from the right; slides back out to the right.
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                landingContent
                    // Fades in/out — "fades back" as the advanced view slides in.
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.3), value: errorMessage)
        .sheet(isPresented: $showGitLabInfo) {
            GitLabLoginInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAdvancedInfo) {
            AdvancedLoginInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // The parent ZStack lives in a safe-area-ignored context (GritApp applies
    // .ignoresSafeArea() at the root), so safe area insets are reported as zero
    // to children.  Read the actual device insets from UIKit for reliable placement.
    private var deviceSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets ?? .zero
    }

    // MARK: - Landing content (extracted so it can carry its own transition)

    private var landingContent: some View {
        VStack(spacing: 0) {
            Spacer()

            logoSection

            Spacer()

            VStack(spacing: 14) {
                if let error = errorMessage {
                    ErrorBanner(message: error) { errorMessage = nil }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                gitlabLoginRow
                advancedLoginRow
            }
            .padding(.horizontal, 24)
            // Ensure buttons clear the home indicator on all device sizes.
            .padding(.bottom, max(48, deviceSafeAreaInsets.bottom + 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 90, height: 90)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                Image("GritIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 90, height: 90)
                    .clipShape(Circle())
            }
            .shadow(color: .accentColor.opacity(0.22), radius: 20)

            VStack(spacing: 5) {
                Text("Grit")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("GitLab for iPhone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Login with GitLab

    private var gitlabLoginRow: some View {
        HStack(spacing: 10) {
            // Primary action card
            Button {
                Task {
                    await signInWithOAuth(
                        baseURL:  "https://gitlab.com",
                        clientID: OAuthService.gitLabComClientID
                    )
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.91, green: 0.37, blue: 0.20),
                                        Color(red: 0.97, green: 0.55, blue: 0.15),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                        Image(systemName: "diamond.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Login with GitLab")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(gitLabComOAuthReady
                             ? "Sign in via OAuth · gitlab.com"
                             : "OAuth not configured — see OAuthService.swift")
                            .font(.caption)
                            .foregroundStyle(gitLabComOAuthReady ? Color.secondary : Color.orange)
                    }

                    Spacer()

                    if isLoggingIn {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .regularGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
                        .opacity(gitLabComOAuthReady ? 0 : 1)
                )
                // Declare the full card shape as the hit-test area so the entire
                // surface is tappable, not just the visually-filled content pixels.
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoggingIn || !gitLabComOAuthReady)

            // Info button
            Button { showGitLabInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 21))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Login another way

    private var advancedLoginRow: some View {
        HStack(spacing: 10) {
            // Navigation card
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    navigateToAdvanced = true
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: "ellipsis.rectangle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 18, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Login another way")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Custom instance or access token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .regularGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                // Declare the full card shape as the hit-test area so the entire
                // surface is tappable, not just the visually-filled content pixels.
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            // Info button
            Button { showAdvancedInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 21))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - OAuth action

    private func signInWithOAuth(baseURL: String, clientID: String) async {
        isLoggingIn  = true
        errorMessage = nil
        defer { isLoggingIn = false }
        do {
            try await authService.loginWithOAuth(baseURL: baseURL, clientID: clientID)
        } catch {
            if case OAuthError.cancelled = error { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Advanced Login View

struct AdvancedLoginView: View {
    @EnvironmentObject var authService: AuthenticationService

    /// Called when the user taps the back button.
    var onBack: () -> Void = {}

    // Shared
    @State private var isLoggingIn    = false
    @State private var errorMessage:  String?

    // Self-managed OAuth
    @State private var customURL      = ""
    @State private var customClientID = ""
    @State private var showClientIDField = false
    @State private var showOAuthInfo  = false

    // PAT
    @State private var patURL         = "https://gitlab.com"
    @State private var accessToken    = ""
    @State private var showToken      = false
    @State private var showPATInfo    = false

    @FocusState private var focused: Field?
    private enum Field { case customURL, customClientID, patURL, token }

    private var canConnectCustom: Bool {
        !customURL.isEmpty
            && !customClientID.isEmpty
            && !customClientID.hasPrefix("YOUR_")
    }

    // The parent ZStack lives in a safe-area-ignored context (GritApp applies
    // .ignoresSafeArea() at the root), so safe area insets are reported as zero
    // to all children.  Read the actual device top inset directly from UIKit so
    // the nav bar is always positioned below the status bar.
    private var topSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.top ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Custom nav bar (replaces the now-absent system navigation bar) ──
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Other Sign-In Options")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // Mirror-width spacer keeps the title visually centred.
                Color.clear.frame(width: 66, height: 1)
            }
            .padding(.horizontal, 16)
            // Top padding = device safe area inset (status bar height) + visual gap.
            // Bottom padding matches the original symmetric value.
            .padding(.top, topSafeAreaInset + 14)
            .padding(.bottom, 14)

            Divider().opacity(0.4)

            // ── Scrollable cards ─────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 20) {
                    if let error = errorMessage {
                        ErrorBanner(message: error) { errorMessage = nil }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    selfManagedCard
                    orDivider
                    patCard

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No background here — the persistent ZStack background in LoginView
        // shows through, keeping the HelloWorldBackground visible.
        .animation(.spring(duration: 0.3),  value: errorMessage)
        .animation(.spring(duration: 0.25), value: showClientIDField)
        .sheet(isPresented: $showOAuthInfo) {
            SelfManagedOAuthInfoSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPATInfo) {
            PATInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Self-Managed OAuth card

    private var selfManagedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header + info button
            HStack(spacing: 10) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Self-Managed Instance")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { showOAuthInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Instance URL
            inputField(
                icon: "globe",
                placeholder: "https://gitlab.example.com",
                text: $customURL,
                field: .customURL,
                contentType: .URL,
                keyboard: .URL
            )

            // Client ID disclosure toggle
            Button {
                withAnimation { showClientIDField.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showClientIDField ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("OAuth Application Client ID")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !customClientID.isEmpty && !customClientID.hasPrefix("YOUR_") {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                }
            }
            .buttonStyle(.plain)

            if showClientIDField {
                VStack(alignment: .leading, spacing: 8) {
                    inputField(
                        icon: "app.badge",
                        placeholder: "Application ID from GitLab OAuth app",
                        text: $customClientID,
                        field: .customClientID,
                        contentType: .none,
                        keyboard: .default
                    )
                    Text("Register a non-confidential OAuth app on your instance under User Settings → Applications. Redirect URI: grit://oauth/callback  •  Scopes: api, read_user")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Connect button
            Button {
                Task { await signInWithOAuth(baseURL: customURL, clientID: customClientID) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Connect with OAuth").fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    canConnectCustom ? Color.accentColor : Color.secondary.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canConnectCustom || isLoggingIn)
            .animation(.easeInOut(duration: 0.2), value: canConnectCustom)
        }
        .padding(16)
        .regularGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - PAT card

    private var patCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header + info button
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Personal Access Token")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { showPATInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Instance URL
            VStack(alignment: .leading, spacing: 6) {
                Text("GitLab Instance")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                inputField(
                    icon: "globe",
                    placeholder: "https://gitlab.com",
                    text: $patURL,
                    field: .patURL,
                    contentType: .URL,
                    keyboard: .URL,
                    submitLabel: .next,
                    onSubmit: { focused = .token }
                )
            }

            // Token field
            VStack(alignment: .leading, spacing: 6) {
                Text("Token")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Group {
                        SecureField("glpat-xxxxxxxxxxxxxxxxxxxx", text: $accessToken)
                    }
                    .textContentType(.none)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .token)
                    .submitLabel(.go)
                    .onSubmit { Task { await loginWithPAT() } }

                    if accessToken.isEmpty {
                        Button {
                            if let s = UIPasteboard.general.string, !s.isEmpty {
                                accessToken = s
                                showToken   = false
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .regularGlassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                        .opacity(focused == .token ? 1 : 0)
                )
            }

            // Sign-in button
            Button { Task { await loginWithPAT() } } label: {
                ZStack {
                    if isLoggingIn {
                        ProgressView()
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Sign In").fontWeight(.semibold)
                        }
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .background(
                LinearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.75)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .shadow(color: .accentColor.opacity(0.3), radius: 8, y: 3)
            .disabled(isLoggingIn || patURL.isEmpty || accessToken.isEmpty)
            .opacity(patURL.isEmpty || accessToken.isEmpty ? 0.55 : 1)
        }
        .padding(16)
        .regularGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Shared input field

    @ViewBuilder
    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType?,
        keyboard: UIKeyboardType,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .if(contentType != nil) { $0.textContentType(contentType!) }
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .focused($focused, equals: field)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
        }
        .padding(12)
        .regularGlassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                .opacity(focused == field ? 1 : 0)
        )
    }

    // MARK: - Or divider

    private var orDivider: some View {
        HStack {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
        }
    }

    // MARK: - Actions

    private func signInWithOAuth(baseURL: String, clientID: String) async {
        focused      = nil
        isLoggingIn  = true
        errorMessage = nil
        defer { isLoggingIn = false }
        do {
            try await authService.loginWithOAuth(baseURL: baseURL, clientID: clientID)
        } catch {
            if case OAuthError.cancelled = error { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loginWithPAT() async {
        focused      = nil
        isLoggingIn  = true
        errorMessage = nil
        defer { isLoggingIn = false }
        do {
            try await authService.login(baseURL: patURL, token: accessToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View modifier helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool,
                              transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Info Sheet: GitLab.com OAuth

struct GitLabLoginInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Grit uses GitLab's OAuth 2.0 flow to sign you in securely — no password is ever stored in the app.")
                        Text("Tapping **Login with GitLab** opens a secure in-app browser where you sign in to gitlab.com and approve Grit's access. You are returned to the app automatically once approved.")
                        Text("This is the recommended option for anyone with a gitlab.com account.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: { Text("How it works") }

                Section {
                    Label("api — Full API access (read & write)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("read_user — Profile & identity info", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } header: { Text("Permissions requested") }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On a self-hosted GitLab server, or prefer not to use the browser flow?")
                        Text("Use **Login another way** on the previous screen instead.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: { Text("Not on gitlab.com?") }
            }
            .navigationTitle("Login with GitLab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Info Sheet: Advanced Login overview

struct AdvancedLoginInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use this option if you are on a **self-hosted GitLab instance** (e.g. gitlab.yourcompany.com), or if you prefer to authenticate with a personal token rather than the browser flow.")
                    }
                    .padding(.vertical, 4)
                } header: { Text("When to use this") }

                Section {
                    infoRow(
                        icon: "building.2.fill",
                        title: "Self-Managed OAuth",
                        detail: "Sign in via OAuth on your own GitLab server. Requires a one-time setup to register Grit as an OAuth app on your instance."
                    )
                    infoRow(
                        icon: "key.fill",
                        title: "Personal Access Token",
                        detail: "Paste a GitLab API token directly. Works on any instance with no OAuth app setup required — great for quick access or CI environments."
                    )
                } header: { Text("Available options") }

                Section {
                    Text("Each option on the next screen has its own **ⓘ** button with step-by-step setup instructions.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: { Text("Tip") }
            }
            .navigationTitle("Login Another Way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Info Sheet: Self-Managed OAuth

struct SelfManagedOAuthInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("To use OAuth on a self-managed GitLab instance, you register Grit as an OAuth application on your server once, then paste the Application ID into Grit.")
                        .padding(.vertical, 4)
                } header: { Text("Overview") }

                Section {
                    stepRow("1", text: "Sign in to your GitLab instance in a browser")
                    stepRow("2", text: "Go to **User Settings → Applications**")
                    stepRow("3", text: "Tap **Add new application** and fill in:")
                    VStack(alignment: .leading, spacing: 4) {
                        monoLine("Name:         Grit (or any name)")
                        monoLine("Redirect URI: grit://oauth/callback")
                        monoLine("Confidential: off")
                        monoLine("Scopes:       api, read_user")
                    }
                    .padding(.leading, 30)
                    stepRow("4", text: "Save and copy the **Application ID** shown")
                    stepRow("5", text: "Paste it into the **Client ID** field in Grit and tap Connect")
                } header: { Text("Setup steps") }

                Section {
                    Text("The Application ID is a long hex string shown once immediately after saving the application. Treat it like a password and store it somewhere safe.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: { Text("Finding the Application ID") }
            }
            .navigationTitle("Self-Managed OAuth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepRow(_ number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func monoLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Info Sheet: Personal Access Token

struct PATInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A Personal Access Token lets you authenticate with any GitLab instance directly — no OAuth app registration needed. It's the simplest option for most self-hosted setups.")
                        .padding(.vertical, 4)
                } header: { Text("Overview") }

                Section {
                    stepRow("1", text: "Sign in to your GitLab instance in a browser")
                    stepRow("2", text: "Go to **User Settings → Access Tokens**")
                    stepRow("3", text: "Tap **Add new token**, give it a name (e.g. Grit), set an expiry if desired, and enable the **api** scope")
                    stepRow("4", text: "Tap **Create personal access token** and copy the value shown")
                    stepRow("5", text: "Paste it into the **Token** field in Grit and tap Sign In")
                } header: { Text("Creating a token") }

                Section {
                    Label("api — Full API access (required)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } header: { Text("Required scope") }

                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("GitLab only shows the token value once. Copy it before leaving the page — if lost, you must create a new token.")
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                } header: { Text("Important") }
            }
            .navigationTitle("Personal Access Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepRow(_ number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
