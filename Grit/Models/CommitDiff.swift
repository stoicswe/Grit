import Foundation

// MARK: - API model

struct CommitDiff: Codable, Identifiable {
    var id: String { newPath ?? oldPath ?? String(diff.prefix(32)) }

    let diff:        String
    let newPath:     String?
    let oldPath:     String?
    let newFile:     Bool
    let renamedFile: Bool
    let deletedFile: Bool
    let tooLarge:    Bool?

    var displayPath: String { newPath ?? oldPath ?? "Unknown" }
    var fileName:    String { (displayPath as NSString).lastPathComponent }

    var statusBadge: String? {
        if newFile     { return "new" }
        if deletedFile { return "deleted" }
        if renamedFile { return "renamed" }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case diff
        case newPath     = "new_path"
        case oldPath     = "old_path"
        case newFile     = "new_file"
        case renamedFile = "renamed_file"
        case deletedFile = "deleted_file"
        case tooLarge    = "too_large"
    }
}

// MARK: - Parsed diff line

struct DiffLine: Identifiable {
    let id = UUID()

    enum Kind {
        case hunkHeader   // @@ -x,y +a,b @@
        case added        // + line
        case removed      // - line
        case context      //   line (unchanged)
        case meta         // +++ --- \ No newline
    }

    let kind:      Kind
    let content:   String   // text without the leading +/- / space
    let oldNumber: Int?     // nil for added lines and hunk headers
    let newNumber: Int?     // nil for removed lines and hunk headers
}

// MARK: - Pre-parsed file diff (computed once by the view model)

struct ParsedFileDiff: Identifiable {
    let id:        String          // == CommitDiff.id
    let meta:      CommitDiff
    let lines:     [DiffLine]
    let additions: Int
    let deletions: Int

    var isBinaryOrEmpty: Bool { meta.diff.isEmpty }
    var isTooLarge:      Bool { meta.tooLarge == true }
}

// MARK: - Diff parser

enum DiffParser {
    private static let hunkRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#)

    static func parse(_ raw: String) -> [DiffLine] {
        var result:  [DiffLine] = []
        var oldNum   = 0
        var newNum   = 0

        for rawLine in raw.components(separatedBy: "\n") {
            guard !rawLine.isEmpty else { continue }

            if rawLine.hasPrefix("@@") {
                // Extract old/new start line numbers from hunk header
                if let regex = hunkRegex {
                    let range = NSRange(rawLine.startIndex..., in: rawLine)
                    if let match = regex.firstMatch(in: rawLine, options: [], range: range),
                       let oldR = Range(match.range(at: 1), in: rawLine),
                       let newR = Range(match.range(at: 2), in: rawLine) {
                        oldNum = Int(rawLine[oldR]) ?? 0
                        newNum = Int(rawLine[newR]) ?? 0
                    }
                }
                result.append(DiffLine(kind: .hunkHeader, content: rawLine,
                                       oldNumber: nil, newNumber: nil))

            } else if rawLine.hasPrefix("+++") || rawLine.hasPrefix("---")
                        || rawLine.hasPrefix("\\") {
                result.append(DiffLine(kind: .meta, content: rawLine,
                                       oldNumber: nil, newNumber: nil))

            } else if rawLine.hasPrefix("+") {
                result.append(DiffLine(kind: .added,
                                       content: String(rawLine.dropFirst()),
                                       oldNumber: nil, newNumber: newNum))
                newNum += 1

            } else if rawLine.hasPrefix("-") {
                result.append(DiffLine(kind: .removed,
                                       content: String(rawLine.dropFirst()),
                                       oldNumber: oldNum, newNumber: nil))
                oldNum += 1

            } else {
                // Context line — may start with a space or sometimes nothing
                let content = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
                result.append(DiffLine(kind: .context, content: content,
                                       oldNumber: oldNum, newNumber: newNum))
                oldNum += 1
                newNum += 1
            }
        }
        return result
    }

    static func build(_ diffs: [CommitDiff]) -> [ParsedFileDiff] {
        diffs.map { d in
            let lines = d.diff.isEmpty ? [] : parse(d.diff)
            let adds  = lines.filter { if case .added   = $0.kind { return true }; return false }.count
            let dels  = lines.filter { if case .removed = $0.kind { return true }; return false }.count
            return ParsedFileDiff(id: d.id, meta: d, lines: lines,
                                  additions: adds, deletions: dels)
        }
    }
}
