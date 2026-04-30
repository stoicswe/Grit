import SwiftUI

/// Shown on launch while `AuthenticationService.restoreSession()` is running.
/// Uses the system background so it adapts to light and dark mode, matching
/// the `LoginView` aesthetic.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo — mirrors LoginView
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

                ProgressView()
                    .tint(.secondary)
                    .padding(.top, 8)
            }
        }
    }
}
