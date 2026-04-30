import SwiftUI

/// Allows pushed detail views (IssueDetailView, MergeRequestDetailView) to
/// register a compose action that MainTabView renders as a liquid-glass button
/// inline with the bottom navigation bar — mirroring the GitHub iOS app pattern.
final class TabBarComposerState: ObservableObject {
    static let shared = TabBarComposerState()
    private init() {}

    @Published private(set) var isVisible = false
    private var action: (() -> Void)?

    func register(_ action: @escaping () -> Void) {
        self.action = action
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isVisible = true }
    }

    func unregister() {
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isVisible = false }
        // Clear the closure after the exit animation finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.action = nil
        }
    }

    func trigger() { action?() }
}
