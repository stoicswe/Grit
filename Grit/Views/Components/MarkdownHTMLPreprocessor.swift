import Foundation

// MARK: - Extended-markdown markers
//
// The HTML preprocessor rewrites README HTML into Markdown the block parser
// understands. A few constructs have no Markdown equivalent (centering,
// collapsible sections, light/dark image pairs), so they are encoded with
// private-use Unicode characters that never appear in real documents.

enum MDMark {
    /// Line prefix: the block on this line is centred (`align="center"`).
    static let center       = "\u{E000}"
    /// Line prefix: start of a `<details>` block; the rest of the line is the summary.
    static let detailsOpen  = "\u{E001}"
    /// Whole line: end of a `<details>` block.
    static let detailsClose = "\u{E002}"
    /// Separates a light-scheme image URL from its dark-scheme variant inside `![alt](…)`.
    static let darkVariant  = "\u{E003}"
}

// MARK: - Preprocessor

/// Converts the HTML that GitHub/GitLab READMEs commonly embed into Markdown.
///
/// Handles `<picture>`/`<source>`/`<img>` (including light/dark variants),
/// `align="center"` on `<p>`, `<div>`, `<h1>`…`<h6>` and `<center>`,
/// `<details>`/`<summary>`, `<table>`, `<br>`, `<hr>`, lists, blockquotes and
/// the usual inline tags (`<strong>`, `<em>`, `<code>`, `<a>`, `<kbd>`…).
/// Anything inside fenced code blocks or inline code spans is left untouched.
enum MDHTMLPreprocessor {

    static func preprocess(_ source: String) -> String {
        // Fast path: nothing that looks like a tag or entity.
        guard source.contains("<") || source.contains("&") else { return source }

        // Split into fenced-code and prose segments; only prose is rewritten.
        var output = ""
        var inFence = false
        var fenceMarker = ""
        var prose: [String] = []

        func flushProse() {
            guard !prose.isEmpty else { return }
            output += rewrite(prose.joined(separator: "\n"))
            output += "\n"
            prose.removeAll()
        }

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inFence {
                output += line + "\n"
                if trimmed.hasPrefix(fenceMarker) { inFence = false }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushProse()
                inFence = true
                fenceMarker = trimmed.hasPrefix("```") ? "```" : "~~~"
                output += line + "\n"
                continue
            }
            prose.append(line)
        }
        flushProse()
        return output
    }

    // MARK: - Prose rewriting

    private static func rewrite(_ text: String) -> String {
        var s = text

        // Protect inline code spans so `<div>` inside backticks survives.
        var codeSpans: [String] = []
        s = replace(s, #"`[^`\n]+`"#) { m in
            codeSpans.append(m[0])
            return "\u{E010}\(codeSpans.count - 1)\u{E011}"
        }

        s = replace(s, #"<!--[\s\S]*?-->"#) { _ in "" }

        // Autolinks <https://…> → [url](url) before tag stripping eats them.
        s = replace(s, #"<(https?://[^>\s]+)>"#) { m in "[\(m[1])](\(m[1]))" }

        s = convertPictures(s)
        s = convertDetails(s)
        s = convertTables(s)
        s = convertBlockWrappers(s)
        s = convertLists(s)
        s = convertInline(s)

        // Any tag we didn't understand: drop the tag, keep its text.
        s = replace(s, #"</?[a-zA-Z][a-zA-Z0-9-]*(\s[^<>]*)?/?>"#) { _ in "" }
        s = decodeEntities(s)

        // Restore code spans.
        s = replace(s, "\u{E010}(\\d+)\u{E011}") { m in codeSpans[Int(m[1]) ?? 0] }
        return s
    }

    // MARK: <picture> / <img>

    private static func convertPictures(_ s: String) -> String {
        replace(s, #"<picture\b[^>]*>([\s\S]*?)</picture>"#) { m in
            let inner = m[1]
            let dark  = firstMatch(inner, #"<source\b[^>]*prefers-color-scheme:\s*dark[^>]*>"#)
                .flatMap { attr($0, "srcset") }
            guard let img = firstMatch(inner, #"<img\b[^>]*>"#) else { return "" }
            return imageMarkdown(imgTag: img, dark: dark)
        }
    }

    private static func imageMarkdown(imgTag: String, dark: String?) -> String {
        guard var src = attr(imgTag, "src") else { return "" }
        let alt = attr(imgTag, "alt") ?? ""
        // srcset may hold a comma list with descriptors; keep the first URL.
        src = src.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? src
        if let dark, !dark.isEmpty, dark != src {
            let darkURL = dark.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ").first ?? dark
            return "![\(alt)](\(src)\(MDMark.darkVariant)\(darkURL))"
        }
        return "![\(alt)](\(src))"
    }

    // MARK: <details>

    private static func convertDetails(_ s: String) -> String {
        var out = replace(s, #"<details\b[^>]*>\s*<summary\b[^>]*>([\s\S]*?)</summary>"#) { m in
            "\n\(MDMark.detailsOpen)\(m[1].trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }
        out = replace(out, #"<details\b[^>]*>"#) { _ in "\n\(MDMark.detailsOpen)Details\n" }
        out = replace(out, #"</details>"#) { _ in "\n\(MDMark.detailsClose)\n" }
        return out
    }

    // MARK: <table>

    private static func convertTables(_ s: String) -> String {
        replace(s, #"<table\b[^>]*>([\s\S]*?)</table>"#) { m in
            let rows = allMatches(m[1], #"<tr\b[^>]*>([\s\S]*?)</tr>"#).map { $0[1] }
            guard !rows.isEmpty else { return "" }
            var lines: [String] = []
            var headerDone = false
            for (index, row) in rows.enumerated() {
                let cells = allMatches(row, #"<(th|td)\b[^>]*>([\s\S]*?)</\1>"#).map { cell -> String in
                    convertInline(cell[2])
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "|", with: "\\|")
                        .trimmingCharacters(in: .whitespaces)
                }
                guard !cells.isEmpty else { continue }
                lines.append("| " + cells.joined(separator: " | ") + " |")
                if index == 0 && !headerDone {
                    lines.append("|" + Array(repeating: " --- |", count: cells.count).joined())
                    headerDone = true
                }
            }
            return "\n" + lines.joined(separator: "\n") + "\n"
        }
    }

    // MARK: <p align>, <div align>, <center>, <h1..6>

    private static func convertBlockWrappers(_ s: String) -> String {
        var out = s
        // Outer wrappers first (div), then p, so nesting keeps its alignment.
        for tag in ["div", "section", "p", "center"] {
            out = replace(out, "<\(tag)\\b([^>]*)>([\\s\\S]*?)</\(tag)>") { m in
                let centered = tag == "center" || isCentered(m[1])
                let inner = m[2].trimmingCharacters(in: .whitespacesAndNewlines)
                return "\n" + (centered ? centerLines(inner) : inner) + "\n"
            }
        }
        out = replace(out, #"<h([1-6])\b([^>]*)>([\s\S]*?)</h\1>"#) { m in
            let level = Int(m[1]) ?? 1
            let text  = m[3].replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let prefix = isCentered(m[2]) ? MDMark.center : ""
            return "\n\(prefix)\(String(repeating: "#", count: level)) \(text)\n"
        }
        out = replace(out, #"<hr\b[^>]*/?>"#) { _ in "\n---\n" }
        out = replace(out, #"<blockquote\b[^>]*>([\s\S]*?)</blockquote>"#) { m in
            "\n" + m[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n") + "\n"
        }
        return out
    }

    private static func isCentered(_ attrs: String) -> Bool {
        attrs.range(of: #"align\s*=\s*["']?center"#, options: [.regularExpression, .caseInsensitive]) != nil ||
        attrs.range(of: #"text-align\s*:\s*center"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func centerLines(_ block: String) -> String {
        block.components(separatedBy: "\n").map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix(MDMark.center),
                  !t.hasPrefix(MDMark.detailsOpen), !t.hasPrefix(MDMark.detailsClose)
            else { return line }
            return MDMark.center + t
        }.joined(separator: "\n")
    }

    // MARK: <ul>/<ol>/<li>

    private static func convertLists(_ s: String) -> String {
        var out = replace(s, #"<ol\b[^>]*>([\s\S]*?)</ol>"#) { m in
            let items = allMatches(m[1], #"<li\b[^>]*>([\s\S]*?)</li>"#).map { $0[1] }
            return "\n" + items.enumerated().map { "\($0.offset + 1). \(oneLine($0.element))" }
                .joined(separator: "\n") + "\n"
        }
        out = replace(out, #"<ul\b[^>]*>([\s\S]*?)</ul>"#) { m in
            let items = allMatches(m[1], #"<li\b[^>]*>([\s\S]*?)</li>"#).map { $0[1] }
            return "\n" + items.map { "- \(oneLine($0))" }.joined(separator: "\n") + "\n"
        }
        return out
    }

    private static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Inline tags

    private static func convertInline(_ s: String) -> String {
        var out = s
        out = replace(out, #"<img\b[^>]*>"#) { m in imageMarkdown(imgTag: m[0], dark: nil) }
        out = replace(out, #"<a\b[^>]*href\s*=\s*["']([^"']*)["'][^>]*>([\s\S]*?)</a>"#) { m in
            let label = m[2].trimmingCharacters(in: .whitespacesAndNewlines)
            // Linked image (badge) → keep the image; the link isn't tappable in a badge row anyway.
            if label.hasPrefix("![") { return label }
            return "[\(label.isEmpty ? m[1] : label)](\(m[1]))"
        }
        out = replace(out, #"<(strong|b)\b[^>]*>([\s\S]*?)</\1>"#) { m in "**\(m[2])**" }
        out = replace(out, #"<(em|i)\b[^>]*>([\s\S]*?)</\1>"#)     { m in "*\(m[2])*" }
        out = replace(out, #"<(code|kbd|samp)\b[^>]*>([\s\S]*?)</\1>"#) { m in "`\(m[2])`" }
        out = replace(out, #"<(s|del|strike)\b[^>]*>([\s\S]*?)</\1>"#) { m in "~~\(m[2])~~" }
        // <br> becomes a line break. Inside a blockquote line the break must
        // carry the "> " prefix or the quote would split in two.
        out = out.components(separatedBy: "\n").map { line -> String in
            guard line.range(of: #"<br\s*/?>"#, options: [.regularExpression, .caseInsensitive]) != nil
            else { return line }
            let quoted = line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
            return replace(line, #"<br\s*/?>"#) { _ in quoted ? "\n> " : "\n" }
        }.joined(separator: "\n")
        return out
    }

    // MARK: Entities

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let map: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&copy;", "©"), ("&reg;", "®"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&amp;", "&")
        ]
        for (entity, char) in map { out = out.replacingOccurrences(of: entity, with: char) }
        return out
    }

    // MARK: Regex helpers

    private static var cache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let r = cache[pattern] { return r }
        let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        cache[pattern] = r
        return r
    }

    /// Replaces every match of `pattern`; the closure receives the capture groups
    /// (index 0 = whole match).
    private static func replace(_ s: String, _ pattern: String,
                                _ transform: ([String]) -> String) -> String {
        guard let re = regex(pattern) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var result = ""
        var cursor = 0
        for m in matches {
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result += transform(groups)
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func firstMatch(_ s: String, _ pattern: String) -> String? {
        guard let re = regex(pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }

    private static func allMatches(_ s: String, _ pattern: String) -> [[String]] {
        guard let re = regex(pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    /// Value of an HTML attribute (quoted or bare) on a single tag string.
    private static func attr(_ tag: String, _ name: String) -> String? {
        if let m = allMatches(tag, "\\b\(name)\\s*=\\s*\"([^\"]*)\"").first { return m[1] }
        if let m = allMatches(tag, "\\b\(name)\\s*=\\s*'([^']*)'").first   { return m[1] }
        if let m = allMatches(tag, "\\b\(name)\\s*=\\s*([^\\s>\"']+)").first { return m[1] }
        return nil
    }
}
