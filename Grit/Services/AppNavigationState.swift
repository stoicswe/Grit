import Foundation
import SwiftUI

/// Shared navigation context — injected as an @EnvironmentObject so any
/// view can read the current repo / file / branch and so the AI chat + context
/// menu always know what is on screen.
@MainActor
final class AppNavigationState: ObservableObject {
    static let shared = AppNavigationState()
    private init() {}

    @Published var currentRepository: Repository?
    @Published var currentFilePath: String?
    @Published var currentBranch: String?

    func enterRepository(_ repo: Repository, branch: String?) {
        currentRepository = repo
        currentBranch = branch
        currentFilePath = nil
    }

    func leaveRepository() {
        currentRepository = nil
        currentBranch = nil
        currentFilePath = nil
    }

    func enterFile(path: String) {
        currentFilePath = path
    }

    // Human-readable context summary for the AI banner
    var contextSummary: String? {
        if let path = currentFilePath {
            return path
        }
        if let repo = currentRepository {
            return repo.nameWithNamespace
        }
        return nil
    }
}
