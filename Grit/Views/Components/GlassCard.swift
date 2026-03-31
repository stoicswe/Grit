import SwiftUI

// MARK: - Liquid Glass Card

struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20

    init(padding: CGFloat = 16, cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Section Header

struct GlassSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Loading Shimmer

struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.quaternary)
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.3), .clear],
                    startPoint: .init(x: phase, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.red.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - MR State Badge

struct MRStateBadge: View {
    let state: MergeRequest.MRState

    var color: Color {
        switch state {
        case .opened: return .green
        case .merged: return .purple
        case .closed: return .red
        case .locked: return .orange
        }
    }

    var icon: String {
        switch state {
        case .opened: return "arrow.triangle.merge"
        case .merged: return "checkmark.circle.fill"
        case .closed: return "xmark.circle.fill"
        case .locked: return "lock.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(state.displayName)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Visibility Badge

struct VisibilityBadge: View {
    let visibility: String

    var icon: String {
        switch visibility {
        case "public": return "globe"
        case "internal": return "building.2"
        default: return "lock.fill"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(visibility.capitalized)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .foregroundStyle(.secondary)
    }
}
