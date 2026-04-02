import SwiftUI

/// Shown on launch while `AuthenticationService.restoreSession()` is running.
/// Matches the LoginView gradient + logo so the transition is seamless.
struct SplashView: View {
    var body: some View {
        ZStack {
            // Background gradient — mirrors LoginView
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

            VStack(spacing: 24) {
                // Logo
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

                ProgressView()
                    .tint(.white.opacity(0.6))
                    .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
    }
}
