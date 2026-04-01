import SwiftUI

// MARK: - Public view

/// Renders a GitLab-Flavoured Markdown string using the app's Liquid Glass aesthetic.
///
/// All parsing and `AttributedString` construction happens on a detached background
/// task so the main thread is never blocked. Raw text is shown instantly as a
/// placeholder while the background task runs.
///
/// Supported block elements: H1–H6 headings, fenced code blocks (``` / ~~~),
/// blockquotes, unordered lists, ordered lists, horizontal rules, paragraphs.
/// Supported inline elements (via AttributedString): bold, italic, inline code,
/// strikethrough, and links.
struct MarkdownRendererView: View {
    let source: String

    @State private var rendered: [MDRenderedBlock] = []
    @State private var isReady  = false

    var body: some View {
        Group {
            if isReady {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(rendered.enumerated()), id: \.offset) { _, block in
                        MDRenderedBlockView(block: block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                // Instant zero-cost placeholder — replaced once background parsing finishes
                Text(source)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.15), value: isReady)
        .task(id: source) {
            // All heavy work — block parsing + every AttributedString call — runs
            // on a detached task so it never touches the main thread.
            let result = await Task.detached(priority: .userInitiated) {
                MDParser.parse(source).map { MDBlockRenderer.render($0) }
            }.value
            rendered = result
            isReady  = true
        }
    }
}

// MARK: - Structural block model (parser output)

private enum MDBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, lines: [String])
    case blockquote(lines: [String])
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case rule
}

// MARK: - Render-ready block model (all AttributedStrings pre-computed)

/// Display-ready version of MDBlock. Every inline string has already been converted
/// to `AttributedString` so zero parsing work happens on the main thread.
private enum MDRenderedBlock {
    case heading(level: Int, text: AttributedString)
    case paragraph(text: AttributedString)
    case codeBlock(language: String?, lines: [String])   // plain strings — fast to render
    case blockquote(lines: [AttributedString])
    case unorderedList(items: [AttributedString])
    case orderedList(items: [AttributedString])
    case rule
}

// MARK: - Block renderer  (structural → display-ready, runs off main thread)

private enum MDBlockRenderer {
    static func render(_ block: MDBlock) -> MDRenderedBlock {
        switch block {
        case .heading(let lvl, let txt):
            return .heading(level: lvl, text: inlineAttr(txt))
        case .paragraph(let txt):
            return .paragraph(text: inlineAttr(txt))
        case .codeBlock(let lang, let lines):
            return .codeBlock(language: lang, lines: lines)
        case .blockquote(let lines):
            return .blockquote(lines: lines.map { inlineAttr($0) })
        case .unorderedList(let items):
            return .unorderedList(items: items.map { inlineAttr($0) })
        case .orderedList(let items):
            return .orderedList(items: items.map { inlineAttr($0) })
        case .rule:
            return .rule
        }
    }

    /// Creates an AttributedString from inline-only Markdown, falling back to plain text.
    static func inlineAttr(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }
}

// MARK: - Parser

private enum MDParser {

    static func parse(_ source: String) -> [MDBlock] {
        var result: [MDBlock] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let raw     = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // ── Blank line ────────────────────────────────────────────────────
            if trimmed.isEmpty { i += 1; continue }

            // ── Fenced code block (``` or ~~~) ────────────────────────────────
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let lang  = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count,
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }  // consume closing fence
                result.append(.codeBlock(language: lang.isEmpty ? nil : lang, lines: codeLines))
                continue
            }

            // ── ATX Heading (#, ##, …, ######) ───────────────────────────────
            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed { guard ch == "#" else { break }; level += 1 }
                level = min(level, 6)
                let rest = trimmed.dropFirst(level)
                if rest.isEmpty || rest.hasPrefix(" ") {
                    let text = rest.trimmingCharacters(in: .whitespaces)
                    result.append(.heading(level: level, text: text))
                    i += 1; continue
                }
            }

            // ── Horizontal rule (---, ***, ___) ──────────────────────────────
            if isHRule(trimmed) { result.append(.rule); i += 1; continue }

            // ── Blockquote ────────────────────────────────────────────────────
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var qLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if      t.hasPrefix("> ") { qLines.append(String(t.dropFirst(2))); i += 1 }
                    else if t == ">"          { qLines.append(""); i += 1 }
                    else                      { break }
                }
                result.append(.blockquote(lines: qLines))
                continue
            }

            // ── Unordered list ────────────────────────────────────────────────
            if ulText(trimmed) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let text = ulText(t)    { items.append(text); i += 1 }
                    else if t.isEmpty          { break }
                    else {
                        if !items.isEmpty { items[items.count - 1] += " " + t }
                        i += 1
                    }
                }
                result.append(.unorderedList(items: items))
                continue
            }

            // ── Ordered list ──────────────────────────────────────────────────
            if olText(trimmed) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let (_, text) = olText(t) { items.append(text); i += 1 }
                    else if t.isEmpty             { break }
                    else {
                        if !items.isEmpty { items[items.count - 1] += " " + t }
                        i += 1
                    }
                }
                result.append(.orderedList(items: items))
                continue
            }

            // ── Paragraph ─────────────────────────────────────────────────────
            var paraLines: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if t.hasPrefix("#") || t.hasPrefix(">") ||
                   t.hasPrefix("```") || t.hasPrefix("~~~") ||
                   ulText(t) != nil || olText(t) != nil || isHRule(t) { break }
                paraLines.append(lines[i])
                i += 1
            }
            if !paraLines.isEmpty {
                result.append(.paragraph(text: paraLines.joined(separator: "\n")))
            }
        }
        return result
    }

    // MARK: Helpers

    private static func isHRule(_ t: String) -> Bool {
        guard t.count >= 3 else { return false }
        let dashes    = t.allSatisfy { $0 == "-" || $0 == " " } && t.filter { $0 == "-" }.count >= 3
        let asterisks = t.allSatisfy { $0 == "*" || $0 == " " } && t.filter { $0 == "*" }.count >= 3
        let unders    = t.allSatisfy { $0 == "_" || $0 == " " } && t.filter { $0 == "_" }.count >= 3
        return dashes || asterisks || unders
    }

    private static func ulText(_ t: String) -> String? {
        guard t.count >= 2 else { return nil }
        let p = String(t.prefix(2))
        if p == "- " || p == "* " || p == "+ " { return String(t.dropFirst(2)) }
        return nil
    }

    private static func olText(_ t: String) -> (Int, String)? {
        var digits = ""
        var idx    = t.startIndex
        while idx < t.endIndex, t[idx].isNumber { digits.append(t[idx]); idx = t.index(after: idx) }
        guard !digits.isEmpty, let num = Int(digits), idx < t.endIndex, t[idx] == "." else { return nil }
        idx = t.index(after: idx)
        guard idx < t.endIndex, t[idx] == " " else { return nil }
        return (num, String(t[t.index(after: idx)...]))
    }
}

// MARK: - Block view dispatcher (consumes pre-computed AttributedStrings — zero parsing)

private struct MDRenderedBlockView: View {
    let block: MDRenderedBlock
    var body: some View {
        switch block {
        case .heading(let lvl, let txt):       MDHeadingView(level: lvl, text: txt)
        case .paragraph(let txt):              MDParagraphView(text: txt)
        case .codeBlock(let lang, let lines):  MDCodeBlockView(language: lang, lines: lines)
        case .blockquote(let lines):           MDBlockquoteView(lines: lines)
        case .unorderedList(let items):        MDUnorderedListView(items: items)
        case .orderedList(let items):          MDOrderedListView(items: items)
        case .rule:                            MDRuleView()
        }
    }
}

// MARK: - Heading

private struct MDHeadingView: View {
    let level: Int
    let text:  AttributedString

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(headingFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Gradient separator under H1 and H2
            if level <= 2 {
                LinearGradient(
                    colors: [Color.primary.opacity(level == 1 ? 0.2 : 0.1), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: level == 1 ? 1 : 0.5)
            }
        }
        .padding(.top, level <= 2 ? 4 : 0)
    }

    private var headingFont: Font {
        switch level {
        case 1:  return .system(size: 20, weight: .bold)
        case 2:  return .system(size: 17, weight: .semibold)
        case 3:  return .system(size: 15, weight: .semibold)
        case 4:  return .system(size: 14, weight: .semibold)
        default: return .system(size: 13, weight: .medium)
        }
    }
}

// MARK: - Paragraph

private struct MDParagraphView: View {
    let text: AttributedString
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

// MARK: - Code Block

private struct MDCodeBlockView: View {
    let language: String?
    let lines:    [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Language badge header
            if let lang = language {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: 6, height: 6)
                    Text(lang)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07))

                Divider().opacity(0.5)
            }

            // Horizontally scrollable code lines
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.82))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Blockquote

private struct MDBlockquoteView: View {
    let lines: [AttributedString]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Accent left border
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.characters.isEmpty {
                        Color.clear.frame(height: 4)
                    } else {
                        Text(line)
                            .font(.system(size: 14).italic())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.accentColor.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

// MARK: - Unordered List

private struct MDUnorderedListView: View {
    let items: [AttributedString]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(item)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Ordered List

private struct MDOrderedListView: View {
    let items: [AttributedString]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(idx + 1).")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                        .frame(minWidth: 22, alignment: .trailing)
                    Text(item)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Horizontal Rule

private struct MDRuleView: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, Color.primary.opacity(0.15), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.vertical, 4)
    }
}
