import AppIntents

/// Registers Grit's App Intents with Siri and Shortcuts so users can
/// invoke them by voice or add them to automations without any setup.
struct GritShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // ── Open a specific project ──────────────────────────────────────
        AppShortcut(
            intent: OpenProjectIntent(),
            phrases: [
                "Open \(\.$project) in \(.applicationName)",
                "Open project \(\.$project) in \(.applicationName)",
                "Show \(\.$project) in \(.applicationName)",
                "Go to \(\.$project) in \(.applicationName)"
            ],
            shortTitle: "Open Project",
            systemImageName: "folder.fill"
        )

        // ── Search for projects ──────────────────────────────────────────
        AppShortcut(
            intent: SearchProjectsIntent(),
            phrases: [
                "Search projects in \(.applicationName)",
                "Search for a project in \(.applicationName)",
                "Find a project in \(.applicationName)",
                "Look up a project in \(.applicationName)"
            ],
            shortTitle: "Search Projects",
            systemImageName: "magnifyingglass"
        )

        // ── Show merge requests ──────────────────────────────────────────
        AppShortcut(
            intent: ShowMyMergeRequestsIntent(),
            phrases: [
                "Show my merge requests in \(.applicationName)",
                "Show my MRs in \(.applicationName)",
                "Open my merge requests in \(.applicationName)",
                "How many merge requests do I have in \(.applicationName)",
                "Check my merge requests in \(.applicationName)"
            ],
            shortTitle: "My Merge Requests",
            systemImageName: "arrow.triangle.merge"
        )

        // ── Show issues ──────────────────────────────────────────────────
        AppShortcut(
            intent: ShowMyIssuesIntent(),
            phrases: [
                "Show my issues in \(.applicationName)",
                "Open my issues in \(.applicationName)",
                "How many issues do I have in \(.applicationName)",
                "Check my issues in \(.applicationName)"
            ],
            shortTitle: "My Issues",
            systemImageName: "exclamationmark.circle.fill"
        )

        // ── Contribution stats ───────────────────────────────────────────
        AppShortcut(
            intent: GetContributionsIntent(),
            phrases: [
                "Show my contributions in \(.applicationName)",
                "How many contributions do I have in \(.applicationName)",
                "What's my streak in \(.applicationName)",
                "Check my contributions in \(.applicationName)",
                "Get my GitLab contributions in \(.applicationName)"
            ],
            shortTitle: "My Contributions",
            systemImageName: "chart.bar.fill"
        )

        // ── Pipeline status (snippet) ────────────────────────────────────
        AppShortcut(
            intent: GetPipelineStatusIntent(),
            phrases: [
                "Pipeline status for \(\.$project) in \(.applicationName)",
                "Check the pipeline for \(\.$project) in \(.applicationName)",
                "How is the build for \(\.$project) in \(.applicationName)",
                "CI status for \(\.$project) in \(.applicationName)"
            ],
            shortTitle: "Pipeline Status",
            systemImageName: "arrow.triangle.branch"
        )

        // ── MR summary (snippet) ─────────────────────────────────────────
        AppShortcut(
            intent: ShowMRSummaryIntent(),
            phrases: [
                "Summarize my merge requests in \(.applicationName)",
                "Merge request summary in \(.applicationName)",
                "MR overview in \(.applicationName)",
                "Give me a merge request report from \(.applicationName)"
            ],
            shortTitle: "MR Summary",
            systemImageName: "list.bullet.rectangle.fill"
        )
    }
}
