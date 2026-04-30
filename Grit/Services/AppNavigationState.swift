import SwiftUI

/// Tracks the user's current navigation context so that sheets
/// (AI Assistant, Search) can adapt to what the user is viewing
@MainActor
final class AppNavigationState: ObservableObject {
    static let shared = AppNavigationState()

    @Published var currentRepository: Repository?
    @Published var currentBranch: String?
    @Published var currentFilePath: String?

    // MARK: - Navigation Paths (lifted so deep links can drive them)

    /// The NavigationStack path for the Repositories tab.
    /// Owned here so DeepLinkHandler can push destinations from outside the view.
    @Published var repoNavigationPath    = NavigationPath()

    /// The NavigationStack path for the Explore tab.
    @Published var exploreNavigationPath = NavigationPath()

    // MARK: - Deep-Link Dispatch

    /// Set by DeepLinkHandler after resolving a URL. MainTabView observes this
    /// to switch to the correct tab; once consumed it is reset to nil.
    @Published var pendingDeepLinkTab: AppTab?

    // MARK: - Compose / Search triggers

    /// Set to true by MainTabView when the user taps the compose button on the
    /// Repositories tab. RepositoryListView observes this to open its search sheet.
    @Published var triggerRepoSearch: Bool = false

    /// The actual text content currently displayed on screen (file source,
    /// MR description, commit body, etc.) — fed into AI prompts for context.
    @Published var currentScreenContent: String?

    /// README content for the current repository, fetched on entry for AI context.
    @Published var repositoryReadme: String?

    /// Top-level files and directories of the current repository, fetched for AI context.
    @Published var repositoryTopLevel: [RepositoryFile]?

    /// A short human-readable summary of the current context.
    var contextSummary: String? {
        if let path = currentFilePath {
            return path
        }
        if let repo = currentRepository {
            var summary = repo.name
            if let branch = currentBranch {
                summary += " · \(branch)"
            }
            return summary
        }
        return nil
    }

    /// True when any extended AI context has been loaded (README or top-level tree).
    var hasRepositoryAIContext: Bool {
        repositoryReadme != nil || repositoryTopLevel != nil
    }

    func enterFile(path: String, content: String? = nil) {
        currentFilePath = path
        currentScreenContent = content
    }

    func enterRepository(_ repository: Repository, branch: String?) {
        currentRepository = repository
        currentBranch = branch
        currentFilePath = nil
        currentScreenContent = nil
        repositoryReadme = nil
        repositoryTopLevel = nil
    }

    func leaveRepository() {
        currentRepository = nil
        currentBranch = nil
        currentFilePath = nil
        currentScreenContent = nil
        repositoryReadme = nil
        repositoryTopLevel = nil
    }

    func setScreenContent(_ content: String?) {
        currentScreenContent = content
    }

    func setRepositoryAIContext(readme: String?, topLevel: [RepositoryFile]?) {
        repositoryReadme = readme
        repositoryTopLevel = topLevel
    }

    // MARK: - AI Instruction Builder

    /// Builds a rich, context-aware instruction string for the AI model.
    /// Called by all AI panel variants (floating panel, slide drawer, legacy chat).
    ///
    /// - File context: includes the full file content when it fits within the
    ///   token budget, or the most relevant window when the file is large.
    ///   The window is chosen by line-number if the user names one, by keyword
    ///   match if useful terms are found, or falls back to the file header with
    ///   guidance for the user to narrow the scope.
    ///
    /// - Repository context: includes the repo description, top-level file/
    ///   directory listing, and README (all truncated to budget).
    func buildAIInstruction(for question: String) -> String {
        var parts: [String] = []

        if let path = currentFilePath {
            // ── File viewing context ──────────────────────────────────────────
            if let repo = currentRepository {
                parts.append("Repository: \(repo.nameWithNamespace) (\(repo.visibility))")
                if let branch = currentBranch { parts.append("Branch: \(branch)") }
            }
            parts.append("File: \(path)")

            if let content = currentScreenContent, !content.isEmpty {
                parts.append("File contents:\n```\n\(fileContext(content: content, question: question))\n```")
            }

        } else if let repo = currentRepository {
            // ── Repository-level context ──────────────────────────────────────
            parts.append("Repository: \(repo.nameWithNamespace) (\(repo.visibility))")
            if let desc = repo.description, !desc.isEmpty {
                parts.append("Description: \(desc)")
            }
            if let branch = currentBranch { parts.append("Branch: \(branch)") }

            if let topLevel = repositoryTopLevel, !topLevel.isEmpty {
                let listing = topLevel
                    .map { $0.isDirectory ? "\($0.name)/" : $0.name }
                    .joined(separator: "\n")
                parts.append("Top-level contents:\n\(listing)")
            }

            if let readme = repositoryReadme, !readme.isEmpty {
                let truncated = readme.count > 3_000
                    ? String(readme.prefix(3_000)) + "\n…[README truncated]"
                    : readme
                parts.append("README:\n\(truncated)")
            }
        }

        parts.append("User question: \(question)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Smart File Context Extraction

    /// Returns the most relevant portion of `content` for answering `question`,
    /// keeping output within ~8 000 characters to respect the model's token budget.
    private func fileContext(content: String, question: String) -> String {
        let maxChars = 8_000
        if content.count <= maxChars { return content }

        let lines = content.components(separatedBy: "\n")

        // 1. Line-number jump: "line 42", "l.42", "line: 42", etc.
        if let target = lineNumber(from: question) {
            return window(lines: lines, centredOn: target - 1,
                          before: 30, after: 50,
                          note: "line \(target)")
        }

        // 2. Keyword search: find the first region where a key term appears.
        for kw in keywords(from: question) {
            if let hit = lines.firstIndex(where: {
                $0.localizedCaseInsensitiveContains(kw)
            }) {
                return window(lines: lines, centredOn: hit,
                              before: 10, after: 60,
                              note: "'\(kw)'")
            }
        }

        // 3. Fallback: leading content with instructions for narrowing scope.
        return String(content.prefix(maxChars)) +
            "\n\n…[file continues — \(lines.count) lines total. " +
            "Mention a line number (e.g. \"line 42\") or a symbol name " +
            "to jump to a specific section.]"
    }

    /// Returns a numbered slice of `lines` centred on `index`.
    private func window(lines: [String], centredOn index: Int,
                        before: Int, after: Int, note: String) -> String {
        let start = max(0, index - before)
        let end   = min(lines.count - 1, index + after)
        let numbered = lines[start...end].enumerated().map { offset, line in
            "\(start + offset + 1): \(line)"
        }.joined(separator: "\n")
        let header = start > 0
            ? "…[\(start) lines omitted — jumped to \(note)]…\n"
            : ""
        let footer = end < lines.count - 1
            ? "\n…[\(lines.count - end - 1) lines below omitted]…"
            : ""
        return "\(header)\(numbered)\(footer)"
    }

    /// Parses the first "line N" / "l.N" mention in `text`, returning the number.
    private func lineNumber(from text: String) -> Int? {
        let pattern = #"(?:^|[^\w])(?:line|l\.)\s*:?\s*(\d{1,6})"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: text,
                                         range: NSRange(text.startIndex..., in: text)),
            let range  = Range(match.range(at: 1), in: text),
            let number = Int(text[range])
        else { return nil }
        return number
    }

    /// Returns up to 3 content-bearing words from `text` to use as search terms.
    private func keywords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "what", "where", "when", "does", "this", "that", "with", "from",
            "have", "there", "about", "which", "their", "would", "could",
            "should", "explain", "show", "find", "tell", "help", "please",
            "look", "give", "some", "more", "much", "many", "like",
        ]
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { $0.count > 3 && !stopWords.contains($0) }
            .prefix(3)
            .map { $0 }
    }
}
