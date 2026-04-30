import Foundation

/// A single Markdown task-list item parsed from an issue description.
struct IssueTask: Identifiable {
    let id:        Int    // position index in the parsed list
    let text:      String
    let isDone:    Bool
    let lineIndex: Int    // which line of the description this occupies
}

extension IssueTask {
    /// Parses all `- [ ]` / `- [x]` lines from a description string.
    static func parse(from description: String) -> [IssueTask] {
        let lines = description.components(separatedBy: "\n")
        var result: [IssueTask] = []
        var taskIndex = 0
        for (lineIndex, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
                let isDone = t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ")
                let text   = String(t.dropFirst(6))
                result.append(IssueTask(id: taskIndex, text: text, isDone: isDone, lineIndex: lineIndex))
                taskIndex += 1
            }
        }
        return result
    }

    /// Toggles the task at `taskIndex` (index within parsed task list, not line index)
    /// in the raw description string and returns the updated string.
    static func toggle(in description: String, at taskIndex: Int) -> String {
        let tasks = parse(from: description)
        guard taskIndex < tasks.count else { return description }
        let lineIndex = tasks[taskIndex].lineIndex
        var lines = description.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return description }
        let line    = lines[lineIndex]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indent  = String(line.prefix(line.count - trimmed.count))
        if trimmed.hasPrefix("- [ ] ") {
            lines[lineIndex] = indent + "- [x] " + trimmed.dropFirst(6)
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            lines[lineIndex] = indent + "- [ ] " + trimmed.dropFirst(6)
        }
        return lines.joined(separator: "\n")
    }
}
