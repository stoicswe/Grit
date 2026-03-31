import SwiftUI

struct AvatarView: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var placeholderView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.7), .accentColor.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: size * 0.35, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
