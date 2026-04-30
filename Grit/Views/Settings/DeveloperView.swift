import SwiftUI

struct DeveloperView: View {
    @Environment(\.dismiss)  private var dismiss
    @Environment(\.openURL)  private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {

                    // MARK: - Avatar + name

                    VStack(spacing: 14) {
                        // Drop in an image asset named "developer_photo" to replace the initials
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 100, height: 100)
                            if let img = UIImage(named: "developer_photo") {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Text("NK")
                                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

                        VStack(spacing: 4) {
                            Text("Nathaniel Knudsen")
                                .font(.system(size: 22, weight: .bold))
                            Text("Senior Software Developer, 7+ years")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 32)

                    // MARK: - Bio

                    Text("A C++ and Java developer by profession, but a Swift and Haskell hobbyist. I'm passionate about building things that make a positive impact on people's lives, and try to learn new things when I have free time. I am a practicing zen and stoic philosopher, love to read, and am an avid enjoyer of games (Death Stranding, Warhammer 40k, Civ, Stellaris, Arcs (board game). I was frustrated that there wasn't a native GitLab client for my phone, so figued...why not make one? Thank you for checking out Grit, and I hope you will find it useful <3")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .padding(.horizontal, 28)

                    // MARK: - Links

                    VStack(spacing: 12) {
                        linkRow(
                            icon:     "bubble.left.and.bubble.right.fill",
                            color:    Color(red: 0.24, green: 0.45, blue: 0.92),
                            title:    "@stoicswe.com",
                            subtitle: "Bluesky",
                            url:      "https://bsky.app/profile/stoicswe.com"
                        )
                        linkRow(
                            icon:     "globe",
                            color:    .teal,
                            title:    "stoicswe.com",
                            subtitle: "Website",
                            url:      "https://stoicswe.com"
                        )
                        linkRow(
                            icon:     "envelope.fill",
                            color:    .secondary,
                            title:    "contact@stoicswe.com",
                            subtitle: "Contact Developer",
                            url:      "mailto:contact@stoicswe.com"
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("About the Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Link Row

    private func linkRow(
        icon:     String,
        color:    Color,
        title:    String,
        subtitle: String,
        url:      String
    ) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
