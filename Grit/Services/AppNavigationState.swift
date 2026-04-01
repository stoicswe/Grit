import SwiftUI

/// Tracks the user's current navigation context so that sheets
/// (AI Assistant, Search) can adapt to what the user is viewing
@MainActor
final class AppNavigationState: ObservableObject {
    static let shared = AppNavigationState()

    @Published var currentRepository: Repository?
    @Published var currentBranch: String?
    @Published var currentFilePath: String?

    /// The actual text content currently displayed on screen (file source,
    /// MR description, commit body, etc.) — fed into AI prompts for context.
    @Published var currentScreenContent: String?

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

    func enterFile(path: String, content: String? = nil) {
        currentFilePath = path
        currentScreenContent = content
    }

    func enterRepository(_ repository: Repository, branch: String?) {
        currentRepository = repository
        currentBranch = branch
        currentFilePath = nil
        currentScreenContent = nil
    }

    func leaveRepository() {
        currentRepository = nil
        currentBranch = nil
        currentFilePath = nil
        currentScreenContent = nil
    }

    func setScreenContent(_ content: String?) {
        currentScreenContent = content
    }
}
