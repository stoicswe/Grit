import SwiftUI

// MARK: - Highlight ViewModel

@MainActor
final class HighlightViewModel: ObservableObject {
    @Published var lines: [AttributedString] = []
    @Published var isComputing = true

    func compute(content: String, language: CodeLanguage) async {
        isComputing = true
        // Run regex work off the main thread, converting to Sendable AttributedString
        let result = await Task.detached(priority: .userInitiated) {
            let nsStrings = SyntaxHighlighter.highlight(content, language: language)
            return nsStrings.map { nsStr in
                (try? AttributedString(nsStr, including: \.uiKit)) ?? AttributedString(nsStr.string)
            }
        }.value
        lines = result
        isComputing = false
    }
}

// MARK: - Code Editor View

struct CodeEditorView: View {
    let content: String
    let fileName: String

    @StateObject private var vm = HighlightViewModel()

    private var language: CodeLanguage { CodeLanguage.detect(filename: fileName) }

    // Gutter width scales with line-count digit length
    private var gutterWidth: CGFloat {
        let digits = max(2, String(vm.lines.count).count)
        return CGFloat(digits) * 9 + 24   // ~9 pt per digit + padding
    }

    var body: some View {
        ZStack {
            if vm.isComputing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorBody
            }
        }
        .task(id: content) {
            await vm.compute(content: content, language: language)
        }
    }

    // MARK: - Editor layout

    private var editorBody: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {

                // ── Line-number gutter ────────────────────────────────
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(vm.lines.indices, id: \.self) { i in
                        Text("\(i + 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .frame(width: gutterWidth, height: 18, alignment: .trailing)
                    }
                }
                .padding(.vertical, 14)

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                // ── Code lines ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.lines.indices, id: \.self) { i in
                        codeLine(vm.lines[i])
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Line renderer

    private func codeLine(_ attributed: AttributedString) -> some View {
        Text(attributed)
            .textSelection(.enabled)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 18, alignment: .leading)
    }
}
