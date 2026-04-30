# Contributing to Grit

First off — thank you. Seriously. Whether you're here to fix a typo, squash a gnarly bug, or build something entirely new, your time matters and it means a lot. It feels good, really good even, to have a community of people... whether that be developers, cosplayers, artists, musicians... whatever the calling is, its great to have a supportive community.

Grit is a minimalist iOS GitLab client. The guiding philosophy is **do less, better** — every feature should earn its place, the UI should get out of the way, and the code should be easy to follow even if you're new to the project. Contributions that align with that spirit are warmly welcomed and encoraged to be a part of this project. The goal is for this to be a welcoming environment for developers of all levels.

---

## Before You Start

**For small changes** (typos, minor bug fixes, polish) — just open a PR. No need to file an issue first.

**For larger changes** (new features, architectural shifts, redesigns) — open an issue and describe what you have in mind. A quick conversation upfront saves everyone time and avoids duplicated effort, but also gains consensus for design and implementation.

If you're unsure whether something is in scope, ask. The worst that can happen is a friendly "not right now."

---

## Development Setup

Requirements: **Xcode 16.3+**, **XcodeGen** (`brew install xcodegen`), an iOS 26 simulator or device.

```bash
git clone https://gitlab.com/stoicswe/grit.git
cd grit
xcodegen generate
open Grit.xcodeproj
```

That's it. No package manager dance, no build scripts.

---

## How to Contribute

1. **Fork** the repo and create a branch from `main`.
   - Name it something descriptive: `fix/pipeline-crash`, `feature/draft-mr-badge`, `chore/update-readme`.

2. **Make your changes.** Keep commits focused — one logical change per commit is easier to review than a sweeping "misc fixes" commit.

3. **Test on a real device or simulator** before opening a PR. The UI is the product that needs to be stable and reliable; please make sure it looks good.

4. **Open a Merge Request** against `main` with a brief description of what changed and why.

You'll hear back within a few days. If it's quiet for too long, feel free to ping.

---

## Code Guidelines

A few conventions that keep the codebase consistent and easy to navigate:

- **MVVM** — views should be as dumb as possible. Logic lives in ViewModels, networking in Services.
- **Async/await** — no Combine or callbacks. New async work belongs in `actor`-isolated services as much as possible.
- **Localisation** — every user-facing string must be localisable. Use `Text("literal")` in SwiftUI (automatic) and `String(localized: "…", comment: "…")` everywhere else. No raw string variables in UI.
- **Cache keys** — if your feature stores data, add a key to `RepoCacheStore.CacheKey` and document its TTL.
- **New models** — should conform to `Codable` and `Identifiable`. Keep `id` a stable key, not a display string.
- **No new dependencies** — if something can be done reasonably with the standard library or SwiftUI, prefer that over adding a package. We want this to be a very lightweight app, to keep it small once compiled and fast. We want blazing fast and for this app to be the best that it can be.

Style-wise, just match the surrounding code.

---

## Reporting Bugs

Found something broken? Please include:

- What you did
- What you expected to happen
- What actually happened
- iOS version and device (or simulator)

Open an issue with that info and it'll get looked at. Screenshots and screen recordings are always helpful.

**Security issues** — please don't open a public issue. Email `contact@stoicswe.com` directly so it can be handled privately first, that is, until we have a group place for issues to be privately submitted.

---

## Suggesting Features

Grit is intentionally focused. Not every idea will fit into the mold this app has set, but that is ok. There is a reason this app is open sourced.

When suggesting a feature, it helps to explain the *why*: what problem does it solve, and for whom? Features that make the core GitLab workflow faster or clearer on mobile are the strongest candidates. Features that add complexity without a clear benefit tend to be deferred.

The best place to suggest features is a GitLab issue, tagged with the `enhancement` label.

---

## What Good Looks Like

A great contribution to Grit is:

- **Minimal** — it does one thing and does it well
- **Consistent** — it looks and behaves like the rest of the app
- **Safe** — it doesn't regress existing behaviour, does not add security flaws
- **Readable** — another developer can understand it without a comment marathon

If you're ever in doubt, look at how something similar is already done in the codebase and follow that pattern.

---

## Recognition

All contributors are credited in the project's GitLab contributor graph. If you make a significant contribution, you'll also be added to the README's author section.

Contributions of all sizes are valued equally here — a well-written bug report is just as useful as a new feature.

---

## License

This project uses a dual-license model:

- **Source code** (Swift files, logic, services) — [MIT](LICENSE)
- **App & UI design** (visual design, assets, UI components) — [Apache 2.0](APP_LICENSE)

By submitting a contribution you agree that your code changes will be covered by the MIT license and any UI/design contributions will be covered by the Apache 2.0 license.

---

Thanks again for taking the time. Happy collaborating. Welcome to the project! 🚀
