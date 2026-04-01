import UIKit

// MARK: - Language

enum CodeLanguage {
    case swift_, python, javaScript, typeScript
    case css, html, c, cpp, csharp, objc
    case ruby, go, java, json, yaml, shell
    case kotlin, rust, php, unknown

    static func detect(filename: String) -> CodeLanguage {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                    return .swift_
        case "py":                       return .python
        case "js", "jsx", "mjs":        return .javaScript
        case "ts", "tsx":               return .typeScript
        case "css", "scss", "less":     return .css
        case "html", "htm", "xml", "svg": return .html
        case "h", "c":                  return .c
        case "cpp", "cc", "cxx", "hpp": return .cpp
        case "cs":                      return .csharp
        case "m", "mm":                 return .objc
        case "rb":                      return .ruby
        case "go":                      return .go
        case "java":                    return .java
        case "json":                    return .json
        case "yaml", "yml":             return .yaml
        case "sh", "bash", "zsh":       return .shell
        case "kt", "kts":               return .kotlin
        case "rs":                      return .rust
        case "php":                     return .php
        default:                        return .unknown
        }
    }

    // MARK: Keywords

    var keywords: [String] {
        switch self {
        case .swift_:
            return ["import","class","struct","enum","protocol","extension","func","var","let",
                    "if","else","guard","return","switch","case","default","for","while","repeat",
                    "do","try","catch","throw","throws","rethrows","async","await","actor",
                    "public","private","internal","fileprivate","open","static","final","override",
                    "mutating","lazy","weak","unowned","init","deinit","self","Self","super",
                    "nil","true","false","in","is","as","where","associatedtype","typealias",
                    "some","any","inout","subscript","get","set","willSet","didSet","nonisolated",
                    "continue","break","fallthrough","@State","@Binding","@ObservedObject",
                    "@StateObject","@EnvironmentObject","@Environment","@Published","@MainActor"]
        case .python:
            return ["import","from","class","def","if","elif","else","for","while","return",
                    "yield","try","except","finally","raise","with","as","pass","break",
                    "continue","lambda","and","or","not","in","is","None","True","False",
                    "global","nonlocal","del","assert","async","await","print","len","range",
                    "self","super","property","staticmethod","classmethod"]
        case .javaScript, .typeScript:
            return ["import","export","from","default","class","extends","function","const",
                    "let","var","if","else","for","while","do","return","try","catch","finally",
                    "throw","new","this","super","typeof","instanceof","in","of","async","await",
                    "switch","case","break","continue","null","undefined","true","false",
                    "static","get","set","type","interface","enum","namespace","declare",
                    "abstract","implements","public","private","protected","readonly","void"]
        case .csharp:
            return ["using","namespace","class","interface","struct","enum","public","private",
                    "protected","internal","static","readonly","const","virtual","override",
                    "abstract","sealed","new","void","int","string","bool","float","double",
                    "decimal","object","if","else","for","foreach","while","do","return",
                    "try","catch","finally","throw","this","base","null","true","false",
                    "var","async","await","yield","get","set","partial","record","init"]
        case .java:
            return ["import","package","class","interface","extends","implements","public",
                    "private","protected","static","final","abstract","void","new","return",
                    "if","else","for","while","do","try","catch","finally","throw","throws",
                    "this","super","null","true","false","int","long","double","float",
                    "boolean","char","byte","short","String","synchronized","volatile","native"]
        case .kotlin:
            return ["import","package","class","interface","object","companion","data","sealed",
                    "abstract","open","override","fun","val","var","if","else","when","for",
                    "while","do","return","try","catch","finally","throw","this","super",
                    "null","true","false","in","is","as","where","by","get","set","init",
                    "constructor","suspend","coroutine","inline","reified","crossinline",
                    "public","private","protected","internal","lateinit","lazy"]
        case .go:
            return ["package","import","func","type","struct","interface","var","const",
                    "if","else","for","range","return","switch","case","default","select",
                    "chan","go","defer","map","nil","true","false","error","string",
                    "int","int64","float64","bool","byte","rune","make","new","len",
                    "cap","append","copy","delete","close","panic","recover","goroutine"]
        case .rust:
            return ["fn","let","mut","const","struct","enum","trait","impl","pub","use",
                    "mod","crate","super","self","Self","if","else","for","while","loop",
                    "match","return","break","continue","where","type","as","in","ref",
                    "move","async","await","dyn","box","unsafe","extern","true","false",
                    "None","Some","Ok","Err","String","Vec","Option","Result","i32","i64",
                    "u32","u64","f32","f64","bool","str","usize","isize"]
        case .ruby:
            return ["require","require_relative","include","extend","module","class","def",
                    "end","if","elsif","else","unless","while","until","for","do","return",
                    "yield","raise","rescue","ensure","begin","self","super","nil","true",
                    "false","and","or","not","in","then","when","case","attr_reader",
                    "attr_writer","attr_accessor","private","protected","public","new","puts"]
        case .c, .cpp, .objc:
            return ["int","char","float","double","void","short","long","unsigned","signed",
                    "const","static","extern","auto","register","volatile","typedef","struct",
                    "union","enum","if","else","for","while","do","switch","case","default",
                    "break","continue","return","goto","sizeof","nullptr","true","false","NULL",
                    "class","public","private","protected","virtual","override","new","delete",
                    "this","namespace","template","typename","inline","explicit","operator",
                    "@interface","@implementation","@end","@property","@synthesize","@protocol",
                    "@selector","@class","self","super","nil","YES","NO","id","IBOutlet","IBAction"]
        case .php:
            return ["<?php","echo","print","if","else","elseif","for","foreach","while","do",
                    "switch","case","default","break","continue","return","function","class",
                    "interface","extends","implements","public","private","protected","static",
                    "abstract","final","new","null","true","false","array","string","int",
                    "float","bool","void","use","namespace","require","include","$this","parent","self"]
        case .css, .html, .json, .yaml, .shell, .unknown:
            return []
        }
    }

    // MARK: Comment tokens

    var lineCommentPrefix: String? {
        switch self {
        case .swift_, .javaScript, .typeScript, .java, .kotlin, .csharp, .go, .rust, .c, .cpp, .objc, .php:
            return "//"
        case .python, .ruby, .shell, .yaml:
            return "#"
        default:
            return nil
        }
    }

    var hasBlockComments: Bool {
        switch self {
        case .swift_, .javaScript, .typeScript, .java, .kotlin, .csharp, .go, .rust, .c, .cpp, .objc, .css, .php:
            return true
        default:
            return false
        }
    }
}

// MARK: - Highlighter

struct SyntaxHighlighter {

    // MARK: Adaptive token colours (Xcode-inspired)

    private static func adaptive(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? hex(dark) : hex(light) }
    }
    private static func hex(_ v: UInt32) -> UIColor {
        UIColor(
            red:   CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8)  & 0xFF) / 255,
            blue:  CGFloat( v        & 0xFF) / 255,
            alpha: 1
        )
    }

    static let keywordColor = adaptive(dark: 0xFC5FA3, light: 0xAD3DA4) // pink / purple
    static let stringColor  = adaptive(dark: 0xFC6A5D, light: 0xC33620) // salmon / dark-red
    static let commentColor = adaptive(dark: 0x6C7986, light: 0x5D6C79) // blue-grey
    static let numberColor  = adaptive(dark: 0xD9C97C, light: 0x1C00CF) // yellow / dark-blue
    static let typeColor    = adaptive(dark: 0x5DD8FF, light: 0x703DAA) // sky-blue / purple

    // MARK: Public API

    /// Returns one `NSAttributedString` per source line (newlines excluded).
    static func highlight(_ code: String, language: CodeLanguage) -> [NSAttributedString] {
        let font  = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: UIColor.label
        ]
        let full = NSMutableAttributedString(string: code, attributes: attrs)
        let fullRange = NSRange(code.startIndex..., in: code)

        // ── Apply tokens (low → high priority) ──────────────────────────

        // Numbers
        apply(#"\b0x[0-9a-fA-F]+\b"#,               color: numberColor,  to: full, code: code)
        apply(#"\b\d+\.?\d*([eE][+-]?\d+)?\b"#,     color: numberColor,  to: full, code: code)

        // Keywords (whole-word match)
        if !language.keywords.isEmpty {
            let joined = language.keywords
                .sorted { $0.count > $1.count }      // longer first avoids partial matches
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            apply(#"\b("# + joined + #")\b"#,        color: keywordColor, to: full, code: code)
        }

        // Capitalised identifiers → types
        apply(#"\b[A-Z][a-zA-Z0-9_]+\b"#,            color: typeColor,    to: full, code: code)

        // Strings (single + double quoted, skip escaped delimiters)
        apply(#""(?:[^"\\]|\\.)*""#,                  color: stringColor,  to: full, code: code)
        apply(#"'(?:[^'\\]|\\.)*'"#,                  color: stringColor,  to: full, code: code)
        // Template literals (JS/TS)
        apply(#"`(?:[^`\\]|\\.)*`"#,                  color: stringColor,  to: full, code: code)

        // HTML/XML tags
        if language == .html {
            apply(#"</?[a-zA-Z][a-zA-Z0-9]*[^>]*>"#, color: keywordColor, to: full, code: code)
        }

        // Block comments — must come after strings
        if language.hasBlockComments {
            apply(#"/\*[\s\S]*?\*/"#, color: commentColor, to: full, code: code, options: [.dotMatchesLineSeparators])
        }

        // Line comments — highest priority
        if let prefix = language.lineCommentPrefix {
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            apply(escaped + #"[^\n]*"#,               color: commentColor, to: full, code: code)
        }

        // ── Split by source lines ────────────────────────────────────────
        var lines: [NSAttributedString] = []
        code.enumerateSubstrings(in: code.startIndex..., options: .byLines) { _, range, _, _ in
            let nsRange = NSRange(range, in: code)
            lines.append(full.attributedSubstring(from: nsRange))
        }
        // Preserve trailing blank line
        if code.hasSuffix("\n") {
            lines.append(NSAttributedString(string: "", attributes: attrs))
        }
        if lines.isEmpty {
            lines.append(NSAttributedString(string: code, attributes: attrs))
        }
        return lines
    }

    // MARK: Private helpers

    private static func apply(
        _ pattern: String,
        color: UIColor,
        to target: NSMutableAttributedString,
        code: String,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(code.startIndex..., in: code)
        for match in regex.matches(in: code, options: [], range: range) {
            target.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
