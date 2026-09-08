import SwiftUI
import WebKit

// MARK: - Public view

/// Renders a GitLab-Flavoured Markdown string using the app's Liquid Glass aesthetic.
///
/// All parsing and `AttributedString` construction happens on a detached background
/// task so the main thread is never blocked. Raw text is shown instantly as a
/// placeholder while the background task runs.
///
/// Supported block elements: ATX and setext headings, fenced code blocks
/// (``` / ~~~), blockquotes, nested and task lists, pipe tables, horizontal
/// rules, paragraphs, images (with light/dark variants), badge/image rows and
/// collapsible `<details>` sections. Common README HTML (`<picture>`, `<img>`,
/// `align="center"`, `<table>`, `<br>`, inline tags) is converted first by
/// `MDHTMLPreprocessor`. SVG images are rendered through WebKit.
/// Supported inline elements (via AttributedString): bold, italic, inline code,
/// strikethrough, and links.
///
/// - Parameter highContrast: When `true`, all body text uses `.primary` instead of
///   `.secondary` so it remains fully legible on a solid coloured bubble background
///   (e.g. the current-user chat bubble). Defaults to `false`.
struct MarkdownRendererView: View {
    let source: String
    var highContrast: Bool = false
    var imageBaseURL: String? = nil

    @State private var rendered: [MDRenderedBlock] = []
    @State private var isReady  = false

    var body: some View {
        Group {
            if isReady {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(rendered.enumerated()), id: \.offset) { _, block in
                        MDRenderedBlockView(block: block, highContrast: highContrast, imageBaseURL: imageBaseURL)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                // Instant zero-cost placeholder — replaced once background parsing finishes
                Text(source)
                    .font(.system(size: 14))
                    .foregroundStyle(highContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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

// MARK: - Shared value types

/// Horizontal alignment of a block (`align="center"` in README HTML, or a
/// table column's `:---:` marker).
enum MDAlign {
    case leading, center, trailing

    var horizontal: HorizontalAlignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    var frameAlignment: Alignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    var textAlignment: TextAlignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
}

/// An image reference with an optional dark-appearance variant
/// (from `<picture><source media="(prefers-color-scheme: dark)">`).
struct MDImageRef: Hashable {
    let alt:     String
    let url:     String
    let darkURL: String?
}

/// One list entry: `level` is the nesting depth (0 = top), `checked` is set
/// for task-list items (`- [ ]` / `- [x]`).
struct MDListItem {
    let text:    String
    let level:   Int
    let checked: Bool?
}

// MARK: - Structural block model (parser output)

private indirect enum MDBlock {
    case heading(level: Int, text: String, align: MDAlign)
    case paragraph(text: String, align: MDAlign)
    case codeBlock(language: String?, lines: [String])
    case blockquote(lines: [String])
    case unorderedList(items: [MDListItem])
    case orderedList(items: [MDListItem])
    case rule
    case image(MDImageRef, align: MDAlign)
    case imageRow(images: [MDImageRef], align: MDAlign)
    case table(header: [String], rows: [[String]], aligns: [MDAlign])
    case details(summary: String, blocks: [MDBlock])
}

// MARK: - Render-ready block model (all AttributedStrings pre-computed)
//
// Built once on a background thread so the view body only assembles Text
// views from ready-made AttributedStrings.

private struct MDRenderedListItem {
    let text:    AttributedString
    let level:   Int
    let checked: Bool?
}

private indirect enum MDRenderedBlock {
    case heading(level: Int, text: AttributedString, align: MDAlign)
    case paragraph(text: AttributedString, align: MDAlign)
    case codeBlock(language: String?, lines: [String])   // plain strings — fast to render
    case blockquote(lines: [AttributedString])
    case unorderedList(items: [MDRenderedListItem])
    case orderedList(items: [MDRenderedListItem])
    case rule
    case image(MDImageRef, align: MDAlign)
    case imageRow(images: [MDImageRef], align: MDAlign)
    case table(header: [AttributedString], rows: [[AttributedString]], aligns: [MDAlign])
    case details(summary: AttributedString, blocks: [MDRenderedBlock])
}

// MARK: - Block renderer  (structural → display-ready, runs off main thread)

private enum MDBlockRenderer {
    static func render(_ block: MDBlock) -> MDRenderedBlock {
        switch block {
        case .heading(let lvl, let txt, let align):
            return .heading(level: lvl, text: inlineAttr(txt), align: align)
        case .paragraph(let txt, let align):
            return .paragraph(text: inlineAttr(txt), align: align)
        case .codeBlock(let lang, let lines):
            return .codeBlock(language: lang, lines: lines)
        case .blockquote(let lines):
            return .blockquote(lines: lines.map { inlineAttr($0) })
        case .unorderedList(let items):
            return .unorderedList(items: items.map {
                MDRenderedListItem(text: inlineAttr($0.text), level: $0.level, checked: $0.checked)
            })
        case .orderedList(let items):
            return .orderedList(items: items.map {
                MDRenderedListItem(text: inlineAttr($0.text), level: $0.level, checked: $0.checked)
            })
        case .rule:
            return .rule
        case .image(let ref, let align):
            return .image(ref, align: align)
        case .imageRow(let images, let align):
            return .imageRow(images: images, align: align)
        case .table(let header, let rows, let aligns):
            return .table(header: header.map { inlineAttr($0) },
                          rows: rows.map { $0.map { inlineAttr($0) } },
                          aligns: aligns)
        case .details(let summary, let blocks):
            return .details(summary: inlineAttr(summary), blocks: blocks.map { render($0) })
        }
    }

    /// Creates an AttributedString from inline-only Markdown, falling back to plain text.
    static func inlineAttr(_ source: String) -> AttributedString {
        // Images mixed into running text can't be drawn inline; show them as links.
        let text = source.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)\s]+)[^)]*\)"#,
            with: "[$1]($2)",
            options: .regularExpression
        )
        return (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - Parser

private enum MDParser {

    static func parse(_ source: String) -> [MDBlock] {
        let lines = MDHTMLPreprocessor.preprocess(source).components(separatedBy: "\n")
        var i = 0
        return parseBlocks(lines, &i, insideDetails: false)
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func parseBlocks(_ lines: [String], _ i: inout Int, insideDetails: Bool) -> [MDBlock] {
        var result: [MDBlock] = []

        while i < lines.count {
            let raw     = lines[i]
            var trimmed = raw.trimmingCharacters(in: .whitespaces)

            // ── Blank line ────────────────────────────────────────────────────
            if trimmed.isEmpty { i += 1; continue }

            // ── <details> boundaries ──────────────────────────────────────────
            if trimmed.hasPrefix(MDMark.detailsClose) {
                i += 1
                if insideDetails { return result }
                continue
            }
            if trimmed.hasPrefix(MDMark.detailsOpen) {
                let summary = String(trimmed.dropFirst(MDMark.detailsOpen.count))
                    .trimmingCharacters(in: .whitespaces)
                i += 1
                let inner = parseBlocks(lines, &i, insideDetails: true)
                result.append(.details(summary: summary.isEmpty ? "Details" : summary, blocks: inner))
                continue
            }

            // ── Alignment marker (from align="center") ────────────────────────
            var align: MDAlign = .leading
            if trimmed.hasPrefix(MDMark.center) {
                align   = .center
                trimmed = String(trimmed.dropFirst(MDMark.center.count)).trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { i += 1; continue }
            }

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
                    var text = rest.trimmingCharacters(in: .whitespaces)
                    // Optional closing hashes: "## Title ##"
                    while text.hasSuffix("#") { text.removeLast() }
                    result.append(.heading(level: level, text: text.trimmingCharacters(in: .whitespaces),
                                           align: align))
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

            // ── Pipe table ────────────────────────────────────────────────────
            if trimmed.contains("|"), i + 1 < lines.count,
               let aligns = tableDelimiter(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let header = tableCells(trimmed)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, t.contains("|") else { break }
                    var cells = tableCells(t)
                    // Normalise row width to the header
                    if cells.count < header.count { cells += Array(repeating: "", count: header.count - cells.count) }
                    rows.append(Array(cells.prefix(header.count)))
                    i += 1
                }
                var colAligns = aligns
                if colAligns.count < header.count {
                    colAligns += Array(repeating: MDAlign.leading, count: header.count - colAligns.count)
                }
                result.append(.table(header: header, rows: rows, aligns: Array(colAligns.prefix(header.count))))
                continue
            }

            // ── Lists (unordered / ordered, nested, task items) ──────────────
            if listItem(raw) != nil {
                let ordered = listItem(raw)?.ordered ?? false
                var items: [MDListItem] = []
                while i < lines.count {
                    let line = lines[i]
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if let item = listItem(line) {
                        items.append(MDListItem(text: item.text, level: item.level, checked: item.checked))
                        i += 1
                    } else if t.isEmpty {
                        // A blank line ends the list unless another item follows directly.
                        if i + 1 < lines.count, listItem(lines[i + 1]) != nil { i += 1; continue }
                        break
                    } else if !items.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("```"), !isHRule(t) {
                        // Lazy continuation of the previous item
                        let last = items.removeLast()
                        items.append(MDListItem(text: last.text + " " + t, level: last.level, checked: last.checked))
                        i += 1
                    } else {
                        break
                    }
                }
                result.append(ordered ? .orderedList(items: items) : .unorderedList(items: items))
                continue
            }

            // ── Setext heading (text underlined with === or ---) ─────────────
            if i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.count >= 1,
                   next.allSatisfy({ $0 == "=" }) || (next.count >= 3 && next.allSatisfy({ $0 == "-" })),
                   imageTokens(trimmed) == nil {
                    result.append(.heading(level: next.first == "=" ? 1 : 2, text: trimmed, align: align))
                    i += 2; continue
                }
            }

            // ── Paragraph ─────────────────────────────────────────────────────
            var paraLines: [String] = []
            var paraAlign = align
            while i < lines.count {
                var t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix(MDMark.center) {
                    paraAlign = .center
                    t = String(t.dropFirst(MDMark.center.count)).trimmingCharacters(in: .whitespaces)
                }
                if t.isEmpty { break }
                if t.hasPrefix(MDMark.detailsOpen) || t.hasPrefix(MDMark.detailsClose) { break }
                if !paraLines.isEmpty {
                    if t.hasPrefix("#") || t.hasPrefix(">") ||
                       t.hasPrefix("```") || t.hasPrefix("~~~") ||
                       listItem(lines[i]) != nil || isHRule(t) { break }
                    // Setext underline closes the paragraph as a heading
                    if t.allSatisfy({ $0 == "=" }) || (t.count >= 3 && t.allSatisfy({ $0 == "-" })) {
                        let text = paraLines.joined(separator: " ")
                        result.append(.heading(level: t.first == "=" ? 1 : 2, text: text, align: paraAlign))
                        paraLines.removeAll()
                        i += 1
                        break
                    }
                }
                paraLines.append(t)
                i += 1
            }
            guard !paraLines.isEmpty else { continue }

            // A paragraph made only of images (logo, badge rows) becomes an image block.
            let joined = paraLines.joined(separator: "\n")
            if let images = imageTokens(joined) {
                if images.count == 1 {
                    result.append(.image(images[0], align: paraAlign))
                } else {
                    result.append(.imageRow(images: images, align: paraAlign))
                }
            } else {
                result.append(.paragraph(text: joined, align: paraAlign))
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

    /// Parses `- item`, `* item`, `+ item`, `1. item`, `1) item`, with optional
    /// `[ ]` / `[x]` task markers. Nesting depth comes from leading indentation
    /// (two spaces or one tab per level).
    private static func listItem(_ raw: String) -> (text: String, level: Int, ordered: Bool, checked: Bool?)? {
        var indent = 0
        var idx = raw.startIndex
        while idx < raw.endIndex {
            if raw[idx] == " " { indent += 1 } else if raw[idx] == "\t" { indent += 4 } else { break }
            idx = raw.index(after: idx)
        }
        let t = String(raw[idx...])
        var ordered = false
        var body: String
        if t.count >= 2, let first = t.first, "-*+".contains(first), t.dropFirst().first == " " {
            body = String(t.dropFirst(2))
        } else {
            var digits = ""
            var j = t.startIndex
            while j < t.endIndex, t[j].isNumber { digits.append(t[j]); j = t.index(after: j) }
            guard !digits.isEmpty, j < t.endIndex, t[j] == "." || t[j] == ")" else { return nil }
            j = t.index(after: j)
            guard j < t.endIndex, t[j] == " " else { return nil }
            ordered = true
            body = String(t[t.index(after: j)...])
        }
        var checked: Bool? = nil
        if body.hasPrefix("[ ] ")                          { checked = false; body = String(body.dropFirst(4)) }
        else if body.hasPrefix("[x] ") || body.hasPrefix("[X] ") { checked = true;  body = String(body.dropFirst(4)) }
        return (body.trimmingCharacters(in: .whitespaces), min(indent / 2, 4), ordered, checked)
    }

    /// Recognises a table delimiter row like `| --- | :---: | ---: |` and
    /// returns the per-column alignments.
    private static func tableDelimiter(_ t: String) -> [MDAlign]? {
        guard t.contains("-") else { return nil }
        let cells = tableCells(t)
        guard !cells.isEmpty else { return nil }
        var aligns: [MDAlign] = []
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard c.count >= 1, c.allSatisfy({ $0 == "-" || $0 == ":" }), c.contains("-") else { return nil }
            let left = c.hasPrefix(":"), right = c.hasSuffix(":")
            aligns.append(left && right ? .center : right ? .trailing : .leading)
        }
        return aligns
    }

    private static func tableCells(_ t: String) -> [String] {
        var line = t
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }
        // Split on unescaped pipes
        var cells: [String] = []
        var current = ""
        var escape = false
        for ch in line {
            if escape { current.append(ch); escape = false; continue }
            if ch == "\\" { escape = true; continue }
            if ch == "|" { cells.append(current); current = "" } else { current.append(ch) }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static let imageTokenRegex = try? NSRegularExpression(
        pattern: #"\[?!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)(?:\]\([^)]*\))?"#
    )

    /// If `text` consists only of images (optionally link-wrapped) and
    /// whitespace, returns them; otherwise `nil`.
    private static func imageTokens(_ text: String) -> [MDImageRef]? {
        guard text.contains("!["), let re = imageTokenRegex else { return nil }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        var rest = text
        var refs: [MDImageRef] = []
        for m in matches.reversed() {
            let alt = ns.substring(with: m.range(at: 1))
            let url = ns.substring(with: m.range(at: 2))
            let parts = url.components(separatedBy: MDMark.darkVariant)
            refs.insert(MDImageRef(alt: alt, url: parts[0], darkURL: parts.count > 1 ? parts[1] : nil), at: 0)
            rest = (rest as NSString).replacingCharacters(in: m.range, with: "")
        }
        guard rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return refs
    }
}

// MARK: - Block view dispatcher (consumes pre-computed AttributedStrings — zero parsing)

private struct MDRenderedBlockView: View {
    let block:        MDRenderedBlock
    let highContrast: Bool
    var imageBaseURL: String? = nil

    var body: some View {
        switch block {
        case .heading(let lvl, let txt, let align):  MDHeadingView(level: lvl, text: txt, align: align)
        case .paragraph(let txt, let align):         MDParagraphView(text: txt, highContrast: highContrast, align: align)
        case .codeBlock(let lang, let lines):        MDCodeBlockView(language: lang, lines: lines, highContrast: highContrast)
        case .blockquote(let lines):                 MDBlockquoteView(lines: lines, highContrast: highContrast)
        case .unorderedList(let items):              MDListView(items: items, ordered: false, style: .compact, highContrast: highContrast)
        case .orderedList(let items):                MDListView(items: items, ordered: true, style: .compact, highContrast: highContrast)
        case .rule:                                  MDRuleView()
        case .image(let ref, let align):             MDImageView(ref: ref, align: align, baseURL: imageBaseURL)
        case .imageRow(let images, let align):       MDImageRowView(images: images, align: align, baseURL: imageBaseURL, style: .compact)
        case .table(let header, let rows, let aligns):
            MDTableView(header: header, rows: rows, aligns: aligns, style: .compact, highContrast: highContrast)
        case .details(let summary, let blocks):
            MDDetailsView(summary: summary, style: .compact) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, inner in
                    MDRenderedBlockView(block: inner, highContrast: highContrast, imageBaseURL: imageBaseURL)
                }
            }
        }
    }
}

// MARK: - Heading

private struct MDHeadingView: View {
    let level: Int
    let text:  AttributedString
    var align: MDAlign = .leading

    var body: some View {
        VStack(alignment: align.horizontal, spacing: 5) {
            Text(text)
                .font(headingFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(align.textAlignment)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: align.frameAlignment)

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
    let text:         AttributedString
    let highContrast: Bool
    var align:        MDAlign = .leading

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(highContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .multilineTextAlignment(align.textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: align.frameAlignment)
    }
}

// MARK: - Code Block

private struct MDCodeBlockView: View {
    let language:     String?
    let lines:        [String]
    let highContrast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Language badge header
            if let lang = language {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accentColor.opacity(highContrast ? 0.9 : 0.65))
                        .frame(width: 6, height: 6)
                    Text(lang)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(highContrast ? AnyShapeStyle(.primary.opacity(0.8)) : AnyShapeStyle(.secondary))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(highContrast ? 0.14 : 0.07))

                Divider().opacity(highContrast ? 0.3 : 0.5)
            }

            // Horizontally scrollable code lines
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(highContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.82)))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color.primary.opacity(highContrast ? 0.12 : 0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(highContrast ? 0.22 : 0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Blockquote

private struct MDBlockquoteView: View {
    let lines:        [AttributedString]
    let highContrast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Accent left border
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(highContrast ? 1.0 : 0.7))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.characters.isEmpty {
                        Color.clear.frame(height: 4)
                    } else {
                        Text(line)
                            .font(.system(size: 14).italic())
                            .foregroundStyle(highContrast ? AnyShapeStyle(.primary.opacity(0.85)) : AnyShapeStyle(.secondary))
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
            Color.primary.opacity(highContrast ? 0.12 : 0.07),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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

// MARK: - Authenticated image loader (shared by compact + reader image views)

/// Fetches an image with the GitLab token attached (needed for images hosted in
/// private repositories), then renders it either as a bitmap or — for SVG,
/// which `UIImage` cannot decode — through a transparent web view.
///
/// `naturalSize` keeps small images (badges, icons ≤ 60 pt tall) at their
/// intrinsic size instead of stretching them to the container width.
private struct MDAuthenticatedImage: View {
    let url:          URL
    let cornerRadius: CGFloat
    let placeholder:  CGFloat   // shimmer height
    var naturalSize:  Bool = false
    var alt:          String = ""

    private enum Loaded { case bitmap(UIImage), svg(Data), failed }

    @State private var loaded: Loaded? = nil

    var body: some View {
        Group {
            switch loaded {
            case nil:
                ShimmerView()
                    .frame(width: naturalSize ? 96 : nil, height: naturalSize ? 20 : placeholder)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            case .bitmap(let img):
                if naturalSize, img.size.height <= 60 {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: img.size.width, height: img.size.height)
                } else {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            case .svg(let data):
                MDSVGView(data: data, naturalSize: naturalSize)
            case .failed:
                MDImageFallback(alt: alt)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        loaded = nil
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        if let token = await AuthenticationService.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status == 200 else { loaded = .failed; return }
            if let img = UIImage(data: data) {
                loaded = .bitmap(img)
            } else if Self.looksLikeSVG(data, url: url) {
                loaded = .svg(data)
            } else {
                loaded = .failed
            }
        } catch {
            loaded = .failed
        }
    }

    private static func looksLikeSVG(_ data: Data, url: URL) -> Bool {
        if url.pathExtension.lowercased() == "svg" { return true }
        let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
        return head.contains("<svg")
    }
}

/// Alt-text chip shown when an image can't be loaded or decoded.
private struct MDImageFallback: View {
    let alt: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(alt.isEmpty ? "Image" : alt)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Image

private struct MDImageView: View {
    let ref:     MDImageRef
    var align:   MDAlign = .leading
    let baseURL: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let url = MDImageURL.resolve(ref, colorScheme: colorScheme, baseURL: baseURL) {
                MDAuthenticatedImage(url: url, cornerRadius: 8, placeholder: 120, naturalSize: true, alt: ref.alt)
            } else {
                MDImageFallback(alt: ref.alt)
            }
        }
        .frame(maxWidth: .infinity, alignment: align.frameAlignment)
    }
}

/// Resolves relative README image paths against the repository's raw-file
/// base URL and picks the light/dark variant.
private enum MDImageURL {
    static func resolve(_ ref: MDImageRef, colorScheme: ColorScheme, baseURL: String?) -> URL? {
        let raw = (colorScheme == .dark ? ref.darkURL : nil) ?? ref.url
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        guard let base = baseURL else { return nil }
        // Ensure base ends with "/" so relative resolution works correctly for
        // paths like "./image.png", "../assets/logo.png", or bare "image.png".
        let baseWithSlash = base.hasSuffix("/") ? base : base + "/"
        guard let baseURL = URL(string: baseWithSlash) else { return nil }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }
}

// MARK: - Reader View

/// A full-document reader presentation of markdown, optimised for comfortable
/// long-form reading. Uses the same parser / renderer pipeline as
/// `MarkdownRendererView` but applies larger, higher-contrast typography and
/// a generous document layout. Intended to be placed directly inside a parent
/// `ScrollView` (e.g. `FileContentView`).
struct MarkdownReaderView: View {
    let source: String
    var imageBaseURL: String? = nil

    @State private var rendered: [MDRenderedBlock] = []
    @State private var isReady  = false

    var body: some View {
        Group {
            if isReady {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(rendered.enumerated()), id: \.offset) { _, block in
                        MDReaderBlockView(block: block, imageBaseURL: imageBaseURL)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    // Shimmer placeholders while parsing
                    ShimmerView().frame(height: 26).frame(maxWidth: .infinity)
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerView().frame(height: 14).frame(maxWidth: .infinity)
                    }
                    ShimmerView().frame(height: 14).frame(maxWidth: 220, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.15), value: isReady)
        .task(id: source) {
            let result = await Task.detached(priority: .userInitiated) {
                MDParser.parse(source).map { MDBlockRenderer.render($0) }
            }.value
            rendered = result
            isReady  = true
        }
    }
}

// MARK: - Reader block dispatcher

private struct MDReaderBlockView: View {
    let block: MDRenderedBlock
    var imageBaseURL: String? = nil

    var body: some View {
        switch block {
        case .heading(let lvl, let txt, let align): MDReaderHeadingView(level: lvl, text: txt, align: align)
        case .paragraph(let txt, let align):        MDReaderParagraphView(text: txt, align: align)
        case .codeBlock(let lang, let lines):       MDReaderCodeBlockView(language: lang, lines: lines)
        case .blockquote(let lines):                MDReaderBlockquoteView(lines: lines)
        case .unorderedList(let items):             MDListView(items: items, ordered: false, style: .reader, highContrast: true)
        case .orderedList(let items):               MDListView(items: items, ordered: true, style: .reader, highContrast: true)
        case .rule:                                 MDReaderRuleView()
        case .image(let ref, let align):            MDReaderImageView(ref: ref, align: align, baseURL: imageBaseURL)
        case .imageRow(let images, let align):      MDImageRowView(images: images, align: align, baseURL: imageBaseURL, style: .reader)
        case .table(let header, let rows, let aligns):
            MDTableView(header: header, rows: rows, aligns: aligns, style: .reader, highContrast: true)
        case .details(let summary, let blocks):
            MDDetailsView(summary: summary, style: .reader) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, inner in
                    MDReaderBlockView(block: inner, imageBaseURL: imageBaseURL)
                }
            }
        }
    }
}

// MARK: - Reader: Heading

private struct MDReaderHeadingView: View {
    let level: Int
    let text:  AttributedString
    var align: MDAlign = .leading

    var body: some View {
        VStack(alignment: align.horizontal, spacing: 7) {
            Text(text)
                .font(headingFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(align.textAlignment)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: align.frameAlignment)

            if level <= 2 {
                LinearGradient(
                    colors: [Color.primary.opacity(level == 1 ? 0.15 : 0.08), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: level == 1 ? 1 : 0.5)
            }
        }
        .padding(.top, level <= 2 ? 8 : level == 3 ? 4 : 0)
    }

    private var headingFont: Font {
        switch level {
        case 1:  return .system(size: 26, weight: .bold)
        case 2:  return .system(size: 21, weight: .semibold)
        case 3:  return .system(size: 18, weight: .semibold)
        case 4:  return .system(size: 16, weight: .semibold)
        default: return .system(size: 15, weight: .medium)
        }
    }
}

// MARK: - Reader: Paragraph

private struct MDReaderParagraphView: View {
    let text:  AttributedString
    var align: MDAlign = .leading

    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .lineSpacing(5)
            .multilineTextAlignment(align.textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: align.frameAlignment)
    }
}

// MARK: - Reader: Code Block

private struct MDReaderCodeBlockView: View {
    let language: String?
    let lines:    [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = language {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: 6, height: 6)
                    Text(lang)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))

                Divider().opacity(0.3)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Reader: Blockquote

private struct MDReaderBlockquoteView: View {
    let lines: [AttributedString]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.characters.isEmpty {
                        Color.clear.frame(height: 4)
                    } else {
                        Text(line)
                            .font(.system(size: 16).italic())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color.accentColor.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Reader: Horizontal Rule

private struct MDReaderRuleView: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, Color.primary.opacity(0.12), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.vertical, 6)
    }
}

// MARK: - Reader: Image

private struct MDReaderImageView: View {
    let ref:     MDImageRef
    var align:   MDAlign = .leading
    let baseURL: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let url = MDImageURL.resolve(ref, colorScheme: colorScheme, baseURL: baseURL) {
                MDAuthenticatedImage(url: url, cornerRadius: 10, placeholder: 180, naturalSize: true, alt: ref.alt)
            } else {
                MDImageFallback(alt: ref.alt)
            }
        }
        .frame(maxWidth: .infinity, alignment: align.frameAlignment)
    }
}

// MARK: - Shared: style

/// Typography scale shared by the new block views.
enum MDStyle {
    case compact, reader

    var bodySize: CGFloat { self == .compact ? 14 : 16 }
    var itemSpacing: CGFloat { self == .compact ? 6 : 8 }
}

// MARK: - Shared: Lists (nested, ordered, task items)

private struct MDListView: View {
    let items:        [MDRenderedListItem]
    let ordered:      Bool
    let style:        MDStyle
    let highContrast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: style.itemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: style == .compact ? 10 : 12) {
                    marker(for: item, index: ordinal(at: idx))
                    Text(item.text)
                        .font(.system(size: style.bodySize))
                        .foregroundStyle(textStyle)
                        .strikethrough(item.checked == true, color: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.leading, CGFloat(item.level) * (style == .compact ? 18 : 22))
            }
        }
    }

    private var textStyle: AnyShapeStyle {
        highContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    /// 1-based position among siblings at the same nesting level; numbering
    /// restarts after a shallower item.
    private func ordinal(at index: Int) -> Int {
        let level = items[index].level
        var count = 0
        var i = index
        while i >= 0, items[i].level >= level {
            if items[i].level == level { count += 1 }
            i -= 1
        }
        return count
    }

    @ViewBuilder
    private func marker(for item: MDRenderedListItem, index: Int) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: style.bodySize + 1))
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                .padding(.top, 1)
        } else if ordered {
            Text("\(index).")
                .font(.system(size: style.bodySize - 1, weight: .medium, design: .monospaced))
                .foregroundStyle(highContrast
                    ? AnyShapeStyle(.primary.opacity(0.9))
                    : AnyShapeStyle(Color.accentColor.opacity(0.8)))
                .frame(minWidth: style == .compact ? 22 : 24, alignment: .trailing)
        } else {
            Circle()
                .fill(item.level == 0 ? Color.accentColor : Color.secondary.opacity(0.6))
                .frame(width: 5, height: 5)
                .padding(.top, style == .compact ? 6 : 7)
        }
    }
}

// MARK: - Shared: Image row (badges, side-by-side logos)

private struct MDImageRowView: View {
    let images:  [MDImageRef]
    let align:   MDAlign
    let baseURL: String?
    let style:   MDStyle

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MDFlowLayout(spacing: 6, align: align) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, ref in
                if let url = MDImageURL.resolve(ref, colorScheme: colorScheme, baseURL: baseURL) {
                    MDAuthenticatedImage(url: url, cornerRadius: 4,
                                         placeholder: style == .compact ? 20 : 24,
                                         naturalSize: true, alt: ref.alt)
                } else {
                    MDImageFallback(alt: ref.alt)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: align.frameAlignment)
    }
}

/// Minimal wrapping row layout: places children left-to-right and wraps to
/// the next line when the width is exhausted. Rows are aligned per `align`.
private struct MDFlowLayout: Layout {
    var spacing: CGFloat = 6
    var align:   MDAlign = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for row in result.rows {
            let leftover = max(0, bounds.width - row.width)
            let offset: CGFloat = align == .center ? leftover / 2 : align == .trailing ? leftover : 0
            for (index, x) in row.positions {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + offset + x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
            }
        }
    }

    private struct Row { var y: CGFloat; var width: CGFloat; var positions: [(Int, CGFloat)] }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, rows: [Row]) {
        var rows: [Row] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var current = Row(y: 0, width: 0, positions: [])
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                current.width = x - spacing
                rows.append(current)
                y += rowHeight + spacing
                x = 0; rowHeight = 0
                current = Row(y: y, width: 0, positions: [])
            }
            current.positions.append((index, x))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        current.width = max(0, x - spacing)
        rows.append(current)
        let totalWidth = rows.map(\.width).max() ?? 0
        return (CGSize(width: width.isFinite ? width : totalWidth, height: y + rowHeight), rows)
    }
}

// MARK: - Shared: Table

private struct MDTableView: View {
    let header:       [AttributedString]
    let rows:         [[AttributedString]]
    let aligns:       [MDAlign]
    let style:        MDStyle
    let highContrast: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { col, cell in
                        cellView(cell, column: col, isHeader: true)
                    }
                }
                .background(Color.primary.opacity(0.06))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { col, cell in
                            cellView(cell, column: col, isHeader: false)
                        }
                    }
                    .background(rowIndex % 2 == 1 ? Color.primary.opacity(0.025) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private func cellView(_ text: AttributedString, column: Int, isHeader: Bool) -> some View {
        let align = column < aligns.count ? aligns[column] : .leading
        return Text(text)
            .font(.system(size: style.bodySize - 1, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(isHeader || highContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .multilineTextAlignment(align.textAlignment)
            .frame(maxWidth: .infinity, alignment: align.frameAlignment)
            .frame(minWidth: 72, maxWidth: 260, alignment: align.frameAlignment)
            .padding(.horizontal, 10)
            .padding(.vertical, style == .compact ? 6 : 8)
            .textSelection(.enabled)
            .gridColumnAlignment(align.horizontal)
    }
}

// MARK: - Shared: <details> / <summary>

private struct MDDetailsView<Content: View>: View {
    let summary: AttributedString
    let style:   MDStyle
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: style.bodySize - 3, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.system(size: style.bodySize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: style == .compact ? 12 : 16) {
                    content()
                }
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Shared: SVG (via WebKit)

/// Renders SVG data in a transparent, non-scrolling web view. `UIImage` has no
/// SVG decoder, and almost every README badge and logo is SVG.
///
/// The web view measures the graphic's intrinsic size once loaded and then
/// sizes itself like an image would: at its natural size when it fits, scaled
/// down to the available width (aspect preserved) when it doesn't.
private struct MDSVGView: View {
    let data:        Data
    let naturalSize: Bool

    @State private var natural: CGSize? = nil

    var body: some View {
        MDSVGWebView(data: data, natural: natural) { measured in
            if natural != measured { natural = measured }
        }
        .opacity(natural == nil ? 0 : 1)
        .animation(.easeIn(duration: 0.15), value: natural == nil)
    }
}

private struct MDSVGWebView: UIViewRepresentable {
    let data:      Data
    let natural:   CGSize?
    let onMeasure: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMeasure: onMeasure) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.isUserInteractionEnabled = false
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onMeasure = onMeasure
        guard context.coordinator.loadedHash != data.hashValue else { return }
        context.coordinator.loadedHash = data.hashValue
        // Inline the SVG as a data URI so no follow-up request (and no auth) is needed.
        // The <img> fills the web view; SwiftUI sizes the web view to the aspect ratio.
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}
        img{display:block;width:100%;height:auto}</style></head>
        <body><img id="svg" src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    /// Natural size when it fits the proposal, otherwise scaled to the proposed
    /// width with the aspect ratio preserved. A small placeholder before the
    /// graphic has been measured.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        guard let n = natural, n.width > 0, n.height > 0 else {
            return CGSize(width: 96, height: 20)
        }
        let available = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? n.width
        let width = min(n.width, available)
        return CGSize(width: width, height: (width * n.height / n.width).rounded(.up))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onMeasure: (CGSize) -> Void
        var loadedHash: Int?
        init(onMeasure: @escaping (CGSize) -> Void) { self.onMeasure = onMeasure }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait for the image to decode, then read its intrinsic size
            // (independent of the web view's current frame).
            let js = """
            const i = document.getElementById('svg');
            try { await i.decode(); } catch (e) {}
            const r = i.getBoundingClientRect();
            return [i.naturalWidth || r.width, i.naturalHeight || r.height];
            """
            webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                guard case .success(let value) = result,
                      let arr = value as? [Double], arr.count == 2, arr[0] > 0, arr[1] > 0
                else { return }
                self.onMeasure(CGSize(width: arr[0], height: arr[1]))
            }
        }
    }
}
