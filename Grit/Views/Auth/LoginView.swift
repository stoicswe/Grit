import SafariServices
import SwiftUI
import UIKit

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var authService: AuthenticationService

    // Shared
    @State private var isLoggingIn   = false
    @State private var errorMessage: String?

    // Custom instance fields
    @State private var customURL      = ""
    @State private var customClientID = ""
    @State private var showClientIDField = false

    // PAT section
    @State private var showPATForm    = false
    @State private var patURL         = "https://gitlab.com"
    @State private var accessToken    = ""
    @State private var showToken      = false
    @State private var showTokenHelp  = false

    @FocusState private var focused: Field?
    enum Field { case customURL, customClientID, patURL, token }

    /// True when the GitLab.com client ID placeholder hasn't been replaced yet.
    private var gitLabComOAuthReady: Bool {
        !OAuthService.gitLabComClientID.hasPrefix("YOUR_")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear.ignoresSafeArea()

                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.07, blue: 0.12),
                        Color(red: 0.04, green: 0.04, blue: 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Glow orbs
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 300).blur(radius: 80)
                    .offset(x: -80, y: -120)
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 250).blur(radius: 80)
                    .offset(x: 80, y: 200)

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer().frame(height: geo.size.height * 0.08)

                        logoSection

                        VStack(spacing: 16) {
                            if let error = errorMessage {
                                ErrorBanner(message: error) { errorMessage = nil }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            gitlabComCard
                            orDivider
                            customInstanceCard
                            orDivider
                            patCard
                        }
                        .padding(.horizontal, 24)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .animation(.spring(duration: 0.3),  value: errorMessage)
        .animation(.spring(duration: 0.35), value: showPATForm)
        .animation(.spring(duration: 0.25), value: showClientIDField)
        .sheet(isPresented: $showTokenHelp) {
            TokenHelpView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                Image(systemName: "diamond.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: .accentColor.opacity(0.3), radius: 20)

            VStack(spacing: 6) {
                Text("Grit")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("GitLab for iPhone")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Option 1: GitLab.com OAuth

    private var gitlabComCard: some View {
        Button {
            Task { await signInWithOAuth(baseURL: "https://gitlab.com",
                                        clientID: OAuthService.gitLabComClientID) }
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
                        .frame(width: 44, height: 44)
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 20, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue with GitLab.com")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(gitLabComOAuthReady
                         ? "Sign in via OAuth 2.0 browser flow"
                         : "Client ID not configured — see OAuthService.swift")
                        .font(.caption)
                        .foregroundStyle(gitLabComOAuthReady
                                         ? .white.opacity(0.55)
                                         : Color.orange.opacity(0.85))
                }

                Spacer()

                if isLoggingIn {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(16)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        gitLabComOAuthReady
                            ? .white.opacity(0.15)
                            : Color.orange.opacity(0.35),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoggingIn)
    }

    // MARK: - Option 2: Self-managed OAuth

    private var customInstanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                Text("Self-Managed Instance")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
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

            // Client ID disclosure
            Button {
                withAnimation { showClientIDField.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showClientIDField ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("OAuth Application Client ID")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    if !customClientID.isEmpty && !customClientID.hasPrefix("YOUR_") {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                }
            }
            .buttonStyle(.plain)

            if showClientIDField {
                VStack(alignment: .leading, spacing: 6) {
                    inputField(
                        icon: "app.badge",
                        placeholder: "Application ID from GitLab OAuth app",
                        text: $customClientID,
                        field: .customClientID,
                        contentType: .none,
                        keyboard: .default
                    )
                    // Contextual help
                    Text("Register a non-confidential OAuth app on your instance under\nUser Settings → Applications → Add new application.\nRedirect URI: grit://oauth/callback  •  Scope: api, read_user")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                Task { await signInWithOAuth(baseURL: customURL, clientID: customClientID) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Connect with OAuth")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    canConnectCustom
                        ? Color.accentColor
                        : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canConnectCustom || isLoggingIn)
            .animation(.easeInOut(duration: 0.2), value: canConnectCustom)
        }
        .padding(16)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var canConnectCustom: Bool {
        !customURL.isEmpty
            && !customClientID.isEmpty
            && !customClientID.hasPrefix("YOUR_")
    }

    // MARK: - Option 3: Personal Access Token

    private var patCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.35)) { showPATForm.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("Personal Access Token")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: showPATForm ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if showPATForm {
                Divider().background(.white.opacity(0.12)).padding(.horizontal, 16)

                VStack(spacing: 14) {
                    // Instance URL
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GitLab Instance")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
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

                    // Token
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Token")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Button { showTokenHelp = true } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 20)
                            Group {
                                if showToken {
                                    TextField("glpat-xxxxxxxxxxxxxxxxxxxx",
                                              text: $accessToken)
                                } else {
                                    SecureField("glpat-xxxxxxxxxxxxxxxxxxxx",
                                                text: $accessToken)
                                }
                            }
                            .textContentType(.none)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .focused($focused, equals: .token)
                            .submitLabel(.go)
                            .onSubmit { Task { await loginWithPAT() } }

                            if accessToken.isEmpty {
                                Button {
                                    if let s = UIPasteboard.general.string, !s.isEmpty {
                                        accessToken = s; showToken = false
                                    }
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            Button { showToken.toggle() } label: {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    focused == .token
                                        ? Color.accentColor.opacity(0.6)
                                        : .white.opacity(0.12),
                                    lineWidth: 1
                                )
                        )
                    }

                    Button { Task { await loginWithPAT() } } label: {
                        ZStack {
                            if isLoggingIn {
                                ProgressView().tint(.white)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text("Sign In").fontWeight(.semibold)
                                }
                                .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 46)
                    }
                    .background(
                        LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .shadow(color: .accentColor.opacity(0.4), radius: 8, y: 3)
                    .disabled(isLoggingIn || patURL.isEmpty || accessToken.isEmpty)
                    .opacity(patURL.isEmpty || accessToken.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
        }
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Shared input field builder

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
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)
            TextField(placeholder, text: text)
                .if(contentType != nil) { $0.textContentType(contentType!) }
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .focused($focused, equals: field)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
        }
        .padding(12)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    focused == field
                        ? Color.accentColor.opacity(0.6)
                        : .white.opacity(0.12),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Divider

    private var orDivider: some View {
        HStack {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
            Text("or").font(.caption).foregroundStyle(.white.opacity(0.3)).padding(.horizontal, 12)
            Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
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

// MARK: - Token Help Sheet

struct TokenHelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GitLab.com (OAuth)")
                            .font(.headline)
                        Text("Tap 'Continue with GitLab.com'. An in-app browser opens, you sign in to GitLab, approve the Grit app, and are returned here automatically.")
                        Text("Requires the developer to register Grit as an OAuth app on GitLab.com and fill in the Application ID in OAuthService.swift.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: { Text("Browser Sign-In") }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Self-Managed (OAuth)")
                            .font(.headline)
                        Text("1. On your GitLab instance, go to **User Settings → Applications**")
                        Text("2. Add a new application:")
                        Group {
                            Text("   • Name: Grit")
                            Text("   • Redirect URI: grit://oauth/callback")
                            Text("   • Confidential: off")
                            Text("   • Scopes: api, read_user")
                        }
                        .font(.footnote.monospaced())
                        Text("3. Copy the Application ID and paste it in the Client ID field here.")
                    }
                    .padding(.vertical, 4)
                } header: { Text("Self-Managed OAuth Setup") }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personal Access Token is available as an alternative for any GitLab instance — no OAuth app registration required.")
                        Text("Create one at **User Settings → Access Tokens** with the **api** scope.")
                    }
                    .padding(.vertical, 4)
                } header: { Text("Personal Access Token") }

                Section {
                    Label("api — Full API access", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("read_user — Profile info (OAuth only)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } header: { Text("Required Scopes") }
            }
            .navigationTitle("Sign-In Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
