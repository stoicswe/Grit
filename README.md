![Xcode Cloud](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/stoicswe/8fc6bd69237f5d505ced66c91f95dc14/raw/grit-build.json) [![CodeQL](https://github.com/stoicswe/Grit/actions/workflows/codeql.yml/badge.svg)](https://github.com/stoicswe/Grit/actions/workflows/codeql.yml)


<p align="left">
  <a href="https://apps.apple.com/us/app/grit-for-gitlab/id6761450099">
    <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1787875200" alt="Download on the Mac App Store" height="56" />
  </a>
  &nbsp;&nbsp;
</p>

# Grit

A native iOS GitLab client built with SwiftUI. Grit aims to provide a way to browse repositories, review merge requests, track pipelines, and monitor your GitLab workflow from an iPhone. Issues can be created and commented on as well, bringing together a collective set of management features to help in a pinch for when you're out and about.

---

## Features
Just some of the features of this application, with more to come as the project matures.

### Repositories
- Browse all your personal and group repositories with group filtering and three sort orders (Recently Edited, Alphabetical, Newest First)
- Star / unstar repositories directly from the list or detail view
- Switch branches and view the default-branch pipeline status at a glance
- Copy clone URLs, open repos in Safari, or jump to group namespaces

### File Browser
- Navigate directory trees and view file contents with syntax-aware display

### Commits
- Full commit history per branch with author, timestamp, and short message
- Commit detail view with unified diff and metadata

### Branches
- List all branches; protected and default branches are visually distinguished
- Navigate directly into a branch detail view to observe commit history for commits

### Merge Requests
- Embedded MR list inside the repository detail view, plus a standalone sheet
- MR detail with description, labels, assignees, and milestone
- **Pipeline browser** — all pipelines triggered for the MR, each tappable to open a full pipeline detail sheet

### Pipelines & CI/CD
- Per-job status with stage grouping
- Live status badges (Passed, Failed, Running, Pending, Canceled, etc.)
- Pipeline source labels (Push, Schedule, API, Web IDE, DAST Scan, etc.)
- Background polling refreshes pipeline status while the view is open

---

## Join the Test Flight!

The public test flight for this app can be joined at this link: https://testflight.apple.com/join/4VWmabkT


## Architecture
Grit follows **MVVM** with a unidirectional data flow:

```
Views  ──▶  ViewModels  ──▶  Services  ──▶  GitLab API / Cache
  ▲               │
  └───────────────┘  (@Published / ObservableObject)
```

### Directory Structure

```
Grit/
├── App/
│   ├── GritApp.swift                  # @main entry point, background task registration
│   └── AppNavigationState.swift       # Global navigation state (current repo, branch)
├── Models/
│   ├── Repository.swift
│   └── ...
├── ViewModels/
│   ├── RepositoryViewModel.swift      # List VM + Detail VM
│   └── ...
├── Views/
│   ├── Repositories/
│   ├── Files/
│   ├── Commits/
│   ├── Branches/
│   ├── MergeRequests/
│   ├── Pipelines/
│   ├── Issues/
│   ├── Forks/
│   ├── Search/
│   ├── Settings/
│   └── Components/
├── Services/
└── Resources/
```

## Network & Caching

Grit is deliberately frugal with the GitLab API so the app stays fast on a phone and never trips the rate limiter.

**Transport layer** (`GitLabAPIService`)
- **ETag revalidation** — every `GET` response carrying an `ETag` is kept in memory; the next identical request sends `If-None-Match` and an unchanged resource comes back as a bodiless `304`. All polling loops rely on this, so an idle screen costs bytes, not kilobytes.
- **In-flight coalescing** — concurrent requests for the same URL share one network call.
- **Concurrency gate** — at most 8 requests run at once; large fan-outs queue instead of bursting.
- **429 handling** — `Retry-After` is honoured once.
- **Membership list fallback** — GitLab.com's 15 s statement timeout can make `GET /projects?membership=true&order_by=last_activity_at` answer HTTP 500 for some accounts. The fetch falls through to cheaper query variants (`order_by=id`, then `min_access_level`) and remembers the working one per host for a day. List endpoints never request `statistics=true`; only single-project fetches do, with a fallback.
- **Debug tracing** — in Debug builds every request is logged under subsystem `com.stoicswe.grit`, category `api` (`→` request, `←` status/bytes/latency; a `304` means the ETag revalidation saved a download).

**Cache layer** (`RepoCacheStore`, memory + disk, per-entry TTL)
- Repository detail bundles, branches, commits, MR lists, groups, starred and watched lists, root trees, READMEs, contributors, project labels, member access levels and notification levels.
- Views serve stale data instantly and revalidate in the background (stale-while-revalidate). A detail bundle written in the last two minutes skips the metadata refetch entirely and only refreshes the live pipeline badge.
- Cache-first helpers live in `RepoContentLoader` / `ProjectAccessCache`; avatars go through `ImageLoader` (`CachedAsyncImage`).
- Everything is cleared on logout.

**Apple Intelligence routing** (`AIAssistantService`)
- Callers describe a task as `.quick` or `.intricate`; the service picks the model. Quick tasks (README summary, short snippets) run on the on-device model. Intricate tasks (MR review, commit explanations with diffs, large files, repo-context questions, squash-commit drafts) use Apple's Private Cloud Compute model on iOS 27+ when available, otherwise on-device. Each path falls back to the other on failure, and prompts are trimmed to the chosen model's context via `contextBudget(for:)`.
- The cloud model only exists in the iOS 27 SDK, so that code is behind `#if compiler(>=6.4)`; the project still builds with Xcode 26. The on-device "Core Advanced" variant is chosen by the system automatically; there is no API to request it.
- Cloud routing is **off until the app is entitled**. `PrivateCloudComputeLanguageModel` aborts the process (not a thrown error) without Apple's managed `com.apple.developer.private-cloud-compute` entitlement. Request it at https://developer.apple.com/contact/request/private-cloud-compute/, add it to `Grit/Grit.entitlements`, then set `GritPrivateCloudComputeEnabled` to `true` in `project.yml`. Until then every task runs on-device.

**Polling cadence** (foreground only; all requests ETag-revalidated)

| Screen | What | Interval |
|---|---|---|
| Repository detail | pipeline badge | 15 s while running, 30 s idle |
| Repository detail | open MRs | 60 s |
| Repository detail | branches | 3 min |
| Inbox (visible) | MRs, issues, tasks, todos | 60 s |
| Inbox (hidden) | todos only (badge + banners) | 60 s |
| Repository list | page 1 | 90 s |
| Starred | list | 2 min |

Tab re-appearances reuse fresh cache (60 s for the repo list, 5 min for Explore/Profile); pull-to-refresh always hits the network.

---

## Requirements

| Requirement | Version |
|---|---|
| iOS | 26.0+ |
| Xcode | 16.3+ |
| XcodeGen | 2.x (`brew install xcodegen`) |
| GitLab | Any self-hosted or GitLab.com instance with API v4 |

---

## Getting Started

### 1. Clone

```bash
git clone https://gitlab.com/stoicswe/grit.git
cd grit
```

### 2. Generate the Xcode project

```bash
xcodegen generate
```

### 3. Open in Xcode

```bash
open Grit.xcodeproj
```

### 4. Configure signing

In Xcode, select the **Grit** target → **Signing & Capabilities** → set your Team and Bundle Identifier.

### 5. Configure GitLab OAuth

1. In your GitLab instance go to **User Settings → Applications**.
2. Create a new application with the redirect URI `grit://oauth/callback`.
3. Grant scopes: `read_api`, `read_user`, `read_repository`.
4. Copy the Application ID and Secret.
5. Add them to `Grit/Resources/Config.xcconfig` (or the appropriate secrets file in your setup).

### 6. Build and run

Select a simulator or device and press **⌘R**.

---

## Localisation

Grit uses the **Xcode 15+ String Catalog** approach (`Localizable.xcstrings`):

- SwiftUI `Text("literal")` calls are automatically localised — no code changes needed.
- Non-UI strings (model labels, error descriptions) use `String(localized: "…", comment: "…")`.
- `SWIFT_EMIT_LOC_STRINGS = YES` is set in the build configuration; the Swift compiler extracts all localisable strings into the catalog automatically on each build.
- To add a new language: open `Localizable.xcstrings` in Xcode, click **+**, select the language, and provide translations — no code changes required.

Currently ships with English. The infrastructure is fully ready for additional languages.

---

## Contributing

1. Fork the repository on GitLab.
2. Create a feature branch: `git checkout -b feature/my-feature`.
3. Commit your changes following the existing code style.
4. Open a Merge Request against `main`.

Note: There are multiple Swift format checks made against the PRs in this repository. Please make note of suggested changes and warnings generated by the tooling to ensure that we can keep the source code maintainable.

Please ensure:
- New UI strings use `String(localized:comment:)` or `Text("literal")` (not string variables).
- New API calls are added to `GitLabAPIService` and are `async throws`.
- New model types conform to `Codable` and `Identifiable`.
- Cache keys for new data types are added to `RepoCacheStore.CacheKey`.

---

## License

This project uses a dual-license model:

| Component | License | File |
|---|---|---|
| Source code (Swift, logic, services) | MIT | [LICENSE](LICENSE) |
| App & UI design (visual design, assets, UI components) | Apache 2.0 | [APP_LICENSE](APP_LICENSE) |

In short: you can freely use and build on the code under MIT terms, but the app's visual design and UI are covered by Apache 2.0, which requires attribution when redistributed.

---

## Author
_Original Author:_ **Nathaniel Knudsen** ([@stoicswe](https://gitlab.com/stoicswe))

For additional authors, please look at the list of contributors that GitLab generates.
