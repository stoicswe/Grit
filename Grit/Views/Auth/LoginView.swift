import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var instanceURL = "https://gitlab.com"
    @State private var accessToken = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showTokenHelp = false
    @State private var showToken = false
    @FocusState private var focusedField: Field?

    enum Field { case url, token }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear.ignoresSafeArea()
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.07, blue: 0.12),
                        Color(red: 0.04, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Glow orbs
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 300)
                    .blur(radius: 80)
                    .offset(x: -80, y: -120)

                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 250)
                    .blur(radius: 80)
                    .offset(x: 80, y: 200)

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer().frame(height: geo.size.height * 0.08)

                        // Logo + Title
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 88, height: 88)
                                    .overlay(
                                        Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                                    )
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

                        // Login form
                        VStack(spacing: 16) {
                            if let error = errorMessage {
                                ErrorBanner(message: error) {
                                    errorMessage = nil
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            // Instance URL
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GitLab Instance")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                HStack(spacing: 10) {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.white.opacity(0.4))
                                        .frame(width: 20)
                                    TextField("https://gitlab.com", text: $instanceURL)
                                        .textContentType(.URL)
                                        .keyboardType(.URL)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .foregroundStyle(.white)
                                        .focused($focusedField, equals: .url)
                                        .submitLabel(.next)
                                        .onSubmit { focusedField = .token }
                                }
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            focusedField == .url ? Color.accentColor.opacity(0.6) : .white.opacity(0.12),
                                            lineWidth: 1
                                        )
                                )
                            }

                            // Access Token
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Personal Access Token")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Spacer()
                                    Button {
                                        showTokenHelp = true
                                    } label: {
                                        Image(systemName: "questionmark.circle")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                                HStack(spacing: 10) {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(.white.opacity(0.4))
                                        .frame(width: 20)
                                    Group {
                                        if showToken {
                                            TextField("glpat-xxxxxxxxxxxxxxxxxxxx", text: $accessToken)
                                        } else {
                                            SecureField("glpat-xxxxxxxxxxxxxxxxxxxx", text: $accessToken)
                                        }
                                    }
                                    .textContentType(.none)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(.white)
                                    .focused($focusedField, equals: .token)
                                    .submitLabel(.go)
                                    .onSubmit { Task { await login() } }

                                    Button {
                                        showToken.toggle()
                                    } label: {
                                        Image(systemName: showToken ? "eye.slash" : "eye")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            focusedField == .token ? Color.accentColor.opacity(0.6) : .white.opacity(0.12),
                                            lineWidth: 1
                                        )
                                )
                            }

                            // Sign In Button
                            Button {
                                Task { await login() }
                            } label: {
                                ZStack {
                                    if isLoggingIn {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.right.circle.fill")
                                            Text("Sign In")
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                            }
                            .background(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .shadow(color: .accentColor.opacity(0.4), radius: 12, y: 4)
                            .disabled(isLoggingIn || instanceURL.isEmpty || accessToken.isEmpty)
                            .opacity(instanceURL.isEmpty || accessToken.isEmpty ? 0.5 : 1)
                        }
                        .padding(.horizontal, 24)

                        // Help text
                        VStack(spacing: 4) {
                            Text("Requires a GitLab Personal Access Token")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("with api scope")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.25))
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.3), value: errorMessage)
        .sheet(isPresented: $showTokenHelp) {
            TokenHelpView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func login() async {
        focusedField = nil
        isLoggingIn = true
        errorMessage = nil
        defer { isLoggingIn = false }
        do {
            try await authService.login(baseURL: instanceURL, token: accessToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TokenHelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to create a Personal Access Token")
                            .font(.headline)
                        Text("1. Go to your GitLab instance")
                        Text("2. Navigate to User Settings → Access Tokens")
                        Text("3. Create a token with the **api** scope")
                        Text("4. Copy the token and paste it here")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Setup Instructions")
                }

                Section {
                    Label("api — Full access to the API", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } header: {
                    Text("Required Scopes")
                }
            }
            .navigationTitle("Access Token Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
