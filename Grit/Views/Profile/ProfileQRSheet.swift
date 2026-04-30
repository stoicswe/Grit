import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - Profile QR Sheet

struct ProfileQRSheet: View {
    let user: GitLabUser

    @Environment(\.dismiss) private var dismiss

    /// Captured before we boost brightness so we can restore it exactly.
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness

    private var profileURL: URL {
        URL(string: user.webURL) ?? URL(string: "https://gitlab.com")!
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {

                // ── Card ─────────────────────────────────────────────
                VStack(spacing: 20) {
                    StyledQRCodeView(url: user.webURL, avatarURL: user.avatarURL)
                        .frame(width: 230, height: 230)

                    Rectangle()
                        .fill(Color.black.opacity(0.07))
                        .frame(height: 0.5)

                    VStack(spacing: 5) {
                        Text(user.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.black)
                        Text("@\(user.username)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.09), radius: 28, y: 8)
                )
                .padding(.horizontal, 28)

                // URL hint
                Text(user.webURL.replacingOccurrences(of: "https://", with: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // ── Share ─────────────────────────────────────────────────
            ShareLink(
                item: profileURL,
                subject: Text("\(user.name) on GitLab"),
                message: Text(user.webURL)
            ) {
                Label("Share Profile", systemImage: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
        }
        .onDisappear {
            UIScreen.main.brightness = originalBrightness
        }
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

// MARK: - Styled QR Code View

/// Custom QR renderer that draws rounded-square modules, styled finder patterns,
/// and overlays the user's avatar in the quiet center zone.
private struct StyledQRCodeView: View {

    private let modules: [[Bool]]
    private let avatarURL: String?

    /// Half-width (in modules) of the blank zone reserved for the avatar.
    /// A 7×7 blank area = 49 modules — well within H-level error recovery.
    private static let avatarHalf = 3

    init(url: String, avatarURL: String?) {
        self.modules   = Self.buildMatrix(from: url)
        self.avatarURL = avatarURL
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let n    = modules.count
            if n > 0 {
                let ms      = side / CGFloat(n)                     // points per module
                let half    = Self.avatarHalf
                let avatarD = ms * CGFloat(half * 2 + 1)           // avatar diameter

                ZStack {
                    Canvas { ctx, _ in
                        var c = ctx
                        renderAll(&c, moduleSize: ms, count: n, avatarHalf: half)
                    }
                    .frame(width: side, height: side)

                    // Avatar overlay, centred in the blank zone
                    if let urlStr = avatarURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Circle().fill(Color.gray.opacity(0.15))
                            }
                        }
                        .frame(width: avatarD, height: avatarD)
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(Color.white, lineWidth: ms * 0.5)
                        )
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                    }
                }
                .frame(width: side, height: side)
            }
        }
    }

    // MARK: - Canvas rendering

    private func renderAll(
        _ ctx: inout GraphicsContext,
        moduleSize ms: CGFloat,
        count n: Int,
        avatarHalf half: Int
    ) {
        let center = n / 2
        let pad    = ms * 0.09           // breathing room between modules
        let dR     = ms * 0.32           // corner radius for data modules

        // ── Data modules ─────────────────────────────────────────────
        for row in 0..<n {
            for col in 0..<n {
                guard modules[row][col]                               else { continue }
                guard !isFinderZone(row: row, col: col, size: n)     else { continue }
                guard !(abs(row - center) <= half &&
                        abs(col - center) <= half)                    else { continue }

                let rect = CGRect(
                    x: CGFloat(col) * ms + pad,
                    y: CGFloat(row) * ms + pad,
                    width:  ms - pad * 2,
                    height: ms - pad * 2
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: dR), with: .color(.black))
            }
        }

        // ── Finder patterns ──────────────────────────────────────────
        drawFinder(&ctx, topRow: 0,     leftCol: 0,     ms: ms)   // top-left
        drawFinder(&ctx, topRow: 0,     leftCol: n - 7, ms: ms)   // top-right
        drawFinder(&ctx, topRow: n - 7, leftCol: 0,     ms: ms)   // bottom-left
    }

    /// True for the 7×7 zones occupied by the finder patterns.
    private func isFinderZone(row: Int, col: Int, size: Int) -> Bool {
        if row < 7 && col < 7         { return true }   // top-left
        if row < 7 && col >= size - 7 { return true }   // top-right
        if row >= size - 7 && col < 7 { return true }   // bottom-left
        return false
    }

    /// Draws a three-layer finder pattern: outer rounded square → white ring → inner dot.
    private func drawFinder(
        _ ctx: inout GraphicsContext,
        topRow: Int,
        leftCol: Int,
        ms: CGFloat
    ) {
        let pad = ms * 0.09
        let x   = CGFloat(leftCol) * ms
        let y   = CGFloat(topRow) * ms
        let s7  = 7 * ms

        // Outer black (7×7)
        ctx.fill(
            Path(roundedRect: CGRect(x: x + pad,      y: y + pad,
                                     width: s7 - pad*2, height: s7 - pad*2),
                 cornerRadius: ms * 1.3),
            with: .color(.black)
        )
        // White ring (5×5, inset 1 module)
        ctx.fill(
            Path(roundedRect: CGRect(x: x + ms + pad,          y: y + ms + pad,
                                     width: 5*ms - pad*2,        height: 5*ms - pad*2),
                 cornerRadius: ms * 0.9),
            with: .color(.white)
        )
        // Inner black dot (3×3, inset 2 modules)
        ctx.fill(
            Path(roundedRect: CGRect(x: x + 2*ms + pad*2,     y: y + 2*ms + pad*2,
                                     width: 3*ms - pad*4,       height: 3*ms - pad*4),
                 cornerRadius: ms * 0.6),
            with: .color(.black)
        )
    }

    // MARK: - Matrix parsing

    /// Decodes a string into a boolean module matrix (top = row 0).
    private static func buildMatrix(from string: String) -> [[Bool]] {
        let filter = CIFilter.qrCodeGenerator()
        filter.message         = Data(string.utf8)
        filter.correctionLevel = "H"   // high redundancy so avatar overlap is safe

        guard let output = filter.outputImage else { return [] }

        let w = Int(output.extent.width)
        let h = Int(output.extent.height)
        let ctx = CIContext()

        var raw = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(output,
                   toBitmap: &raw,
                   rowBytes: w * 4,
                   bounds: output.extent,
                   format: .RGBA8,
                   colorSpace: CGColorSpaceCreateDeviceRGB())

        // CIImage y = 0 is at the bottom; flip rows so row 0 = visual top.
        var matrix = [[Bool]](repeating: [Bool](repeating: false, count: w), count: h)
        for row in 0..<h {
            let src = (h - 1 - row) * w   // source row index in raw (bottom-up)
            for col in 0..<w {
                matrix[row][col] = raw[(src + col) * 4] < 128
            }
        }
        return matrix
    }
}
