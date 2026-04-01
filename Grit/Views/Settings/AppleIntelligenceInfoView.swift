import SwiftUI

struct AppleIntelligenceInfoView: View {

    private let isAvailable = AIAssistantService.shared.isAvailable

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                heroHeader
                availabilityBanner
                whatIsSection
                foundationModelsSection
                privacySection
                howGritUsesItSection
                learnMoreSection
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .navigationTitle("Apple Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 16)

            Text("Apple Intelligence")
                .font(.system(size: 26, weight: .bold))

            Text("Personal intelligence built into Grit.\nPowerful, private, and always on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Availability Banner

    private var availabilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isAvailable ? .green : .orange)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(isAvailable ? "Available on this device" : "Not available on this device")
                    .font(.system(size: 14, weight: .semibold))
                Text(isAvailable
                     ? "Foundation Models framework is active."
                     : "Requires iPhone 16 or later with iOS 18.1+.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            (isAvailable ? Color.green : Color.orange).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder((isAvailable ? Color.green : Color.orange).opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - What Is Apple Intelligence

    private var whatIsSection: some View {
        infoCard(
            icon: "brain.head.profile",
            iconColor: .purple,
            title: "What is Apple Intelligence?",
            content: """
Apple Intelligence is Apple's personal intelligence system, deeply integrated into iOS, iPadOS, and macOS. It combines the power of generative AI with the privacy and security Apple is known for.

Unlike cloud-based AI assistants, Apple Intelligence runs large language models directly on your device. This means requests are processed locally — your data never leaves your iPhone to power AI features.

Apple Intelligence was introduced in iOS 18.1 and requires an Apple Silicon chip (A17 Pro or M-series) to run its on-device models.
"""
        )
    }

    // MARK: - Foundation Models

    private var foundationModelsSection: some View {
        infoCard(
            icon: "cpu",
            iconColor: .blue,
            title: "Foundation Models Framework",
            content: """
Grit uses Apple's **FoundationModels** framework, which provides direct access to the on-device language models powering Apple Intelligence.

The framework exposes a `LanguageModelSession` API that apps can use to send prompts and receive streamed responses — all processed entirely on-device using the Apple Neural Engine.

Key characteristics of Foundation Models:
• Models are downloaded and stored securely on-device
• Inference runs on the Neural Engine, not CPU or GPU
• Sessions are stateless — no conversation history persists between app launches
• The framework enforces strict guardrails aligned with Apple's usage policies
• Models are updated silently alongside iOS system updates
"""
        )
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Privacy & Security")
                    .font(.system(size: 17, weight: .semibold))
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
            }

            VStack(spacing: 10) {
                privacyRow(
                    icon: "iphone.and.arrow.forward",
                    title: "Stays on your device",
                    detail: "All prompts, code, and responses are processed locally by the on-device model. Nothing is sent over the network."
                )
                Divider().padding(.leading, 44)
                privacyRow(
                    icon: "person.slash",
                    title: "Not tied to your identity",
                    detail: "Apple Intelligence models have no knowledge of your Apple ID, GitLab account, or any other personal identifier."
                )
                Divider().padding(.leading, 44)
                privacyRow(
                    icon: "eye.slash",
                    title: "Not used to train models",
                    detail: "Your queries are never collected or used to improve Apple's models. On-device processing means Apple never sees what you ask."
                )
                Divider().padding(.leading, 44)
                privacyRow(
                    icon: "hand.raised.fill",
                    title: "No third-party AI",
                    detail: "Grit does not use OpenAI, Anthropic, Google, or any external AI API. The only model involved is Apple's on-device Foundation Model."
                )
                Divider().padding(.leading, 44)
                privacyRow(
                    icon: "checkmark.seal.fill",
                    title: "Private Compute Core",
                    detail: "For any tasks that do require Apple's servers (not used by Grit), Apple uses Private Cloud Compute — independently verifiable to never log or retain user data."
                )
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
    }

    // MARK: - How Grit Uses It

    private var howGritUsesItSection: some View {
        infoCard(
            icon: "sparkles.rectangle.stack",
            iconColor: .accentColor,
            title: "How Grit Uses Apple Intelligence",
            content: """
Grit uses the Foundation Models framework for the following features:

**AI Assistant (floating panel)**
Ask questions about any repository, branch, file, or merge request you're currently viewing. Grit automatically provides the AI with context from what's on screen — file contents, repo name, branch — so answers are relevant to your actual code.

**File Explanation**
When viewing a source file, the AI can explain what the file does in plain language, summarise its key functions, and highlight anything worth noting.

**Commit & MR Analysis**
The AI can explain what a commit changes or give a plain-language summary of a merge request's diff and description.

**Comment Translation**
When you open an issue, Grit automatically detects the language of each comment using on-device language recognition. If a comment is in a different language than your device, a Translate button appears. Tapping it uses Apple's on-device translation to render the comment in your language — no network request is made.

In every case, your code and questions are processed entirely on-device. Grit sends no data to any external service.
"""
        )
    }

    // MARK: - Learn More

    private var learnMoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Learn More")
                .font(.system(size: 17, weight: .semibold))

            Link(destination: URL(string: "https://developer.apple.com/documentation/foundationmodels")!) {
                linkRow(
                    icon: "doc.text",
                    title: "Foundation Models — Apple Developer Documentation",
                    subtitle: "developer.apple.com"
                )
            }

            Link(destination: URL(string: "https://www.apple.com/privacy/docs/Apple_Intelligence_Privacy_Overview.pdf")!) {
                linkRow(
                    icon: "lock.doc",
                    title: "Apple Intelligence Privacy Overview",
                    subtitle: "apple.com"
                )
            }

            Link(destination: URL(string: "https://security.apple.com/blog/private-cloud-compute/")!) {
                linkRow(
                    icon: "cloud.and.arrow.up",
                    title: "Private Cloud Compute — A new frontier for AI privacy",
                    subtitle: "security.apple.com"
                )
            }
        }
    }

    // MARK: - Helpers

    private func infoCard(icon: String, iconColor: Color, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 18))
            }

            Text(LocalizedStringKey(content))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.system(size: 16))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func linkRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 15))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}
