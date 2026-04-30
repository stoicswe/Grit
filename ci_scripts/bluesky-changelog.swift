#!/usr/bin/env swift
//
// bluesky-changelog.swift
//
// Posts a changelog thread to Bluesky after a successful Xcode Cloud archive.
// Tries Apple Intelligence (FoundationModels) for the summary; falls back to
// a bullet list of commit subjects when the model isn't available — which is
// the case on Xcode Cloud runners today.
//
// Required environment variables (configure in App Store Connect →
// Xcode Cloud → Workflow → Environment, marked Secret):
//   BLUESKY_HANDLE        – e.g. grit-app.bsky.social
//   BLUESKY_APP_PASSWORD  – Bluesky app password
//
// Xcode Cloud variables consumed automatically:
//   CI_BUILD_NUMBER, CI_COMMIT, CI_BRANCH, CI_TAG, CI_PRIMARY_REPOSITORY_PATH
//
// Optional:
//   DRY_RUN=true          – print posts without publishing

import Foundation
import FoundationModels

// MARK: - Types & Errors

struct PostRef {
    let uri: String
    let cid: String
}

enum ScriptError: LocalizedError {
    case missingEnv(String)
    case blueskyAPI(String)

    var errorDescription: String? {
        switch self {
        case .missingEnv(let key): return "Missing required environment variable: \(key)"
        case .blueskyAPI(let msg): return "Bluesky API error: \(msg)"
        }
    }
}

// MARK: - Environment Helpers

func env(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key]
}

func requiredEnv(_ key: String) throws -> String {
    guard let value = env(key), !value.isEmpty else { throw ScriptError.missingEnv(key) }
    return value
}

// MARK: - Shell

@discardableResult
func shell(_ command: String) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// MARK: - Git

/// Returns commit log, diffstat, and a truncated diff for the changes in this build.
/// Xcode Cloud doesn't expose a "previous commit" variable, so we diff against HEAD~1
/// (or the last 20 commits on a shallow first build).
func gatherGitChanges(commitSHA: String) -> (commits: String, diffStat: String, diff: String) {
    let parentExists = shell("git rev-parse --verify --quiet \(commitSHA)~1").isEmpty == false

    let logRange  = parentExists ? "\(commitSHA)~1..\(commitSHA)" : "-20"
    let diffRange = parentExists ? "\(commitSHA)~1..\(commitSHA)" : "\(commitSHA)~10..\(commitSHA)"

    let commits  = shell("git log \(logRange) --pretty=format:'%h %s' 2>/dev/null")
    let diffStat = shell("git diff \(diffRange) --stat 2>/dev/null")
    let rawDiff  = shell("git diff \(diffRange) 2>/dev/null | head -500")

    return (commits, diffStat, String(rawDiff.prefix(8000)))
}

/// Best-effort GitHub commit URL derived from `git remote get-url origin`.
/// Returns nil if the remote isn't a GitHub URL.
func githubCommitURL(commitSHA: String) -> String? {
    let remote = shell("git remote get-url origin 2>/dev/null")
    guard !remote.isEmpty else { return nil }

    // Normalise: git@github.com:owner/repo.git → https://github.com/owner/repo
    var url = remote
    if url.hasPrefix("git@github.com:") {
        url = url.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
    }
    if url.hasSuffix(".git") {
        url = String(url.dropLast(4))
    }
    guard url.contains("github.com/") else { return nil }
    return "\(url)/commit/\(commitSHA)"
}

// MARK: - AI Summary (Apple Intelligence)

func generateSummary(commits: String, diffStat: String, diff: String) async -> String {
    guard SystemLanguageModel.default.availability == .available else {
        fputs("⚠️  Apple Intelligence is not available on this runner — using commit log fallback.\n", stderr)
        return fallbackSummary(commits)
    }

    let instructions = """
    You are a developer-relations writer creating a social media changelog \
    post for "Grit", an iOS GitLab client app.

    Guidelines:
    - Write 2-4 concise bullet points about the most notable changes.
    - Focus on user-facing improvements and meaningful technical changes.
    - Use plain, approachable language.
    - Add a few emoji for visual interest — don't overdo it.
    - Keep the total output under 800 characters.
    - Do NOT include links, hashtags, or @-mentions.
    - If changes are minor (formatting, config, refactoring), say so briefly in one line.
    - Do not fabricate changes that are not reflected in the commits or diff.
    """

    let prompt = """
    Summarise the following changes from the latest build:

    COMMITS:
    \(commits)

    FILES CHANGED:
    \(diffStat)

    DIFF (excerpt):
    \(diff)
    """

    do {
        let session  = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallbackSummary(commits) : text
    } catch {
        fputs("⚠️  AI summary generation failed: \(error.localizedDescription)\n", stderr)
        fputs("    Falling back to commit log.\n", stderr)
        return fallbackSummary(commits)
    }
}

func fallbackSummary(_ commits: String) -> String {
    let lines = commits
        .components(separatedBy: "\n")
        .filter { !$0.isEmpty }
        .prefix(8)
        .map { "• \($0)" }
    return "Recent changes:\n" + lines.joined(separator: "\n")
}

// MARK: - Text Splitting (grapheme-aware)

func splitIntoChunks(_ text: String, maxGraphemes: Int) -> [String] {
    guard text.count > maxGraphemes else { return [text] }

    var chunks: [String] = []
    var remaining = text

    while !remaining.isEmpty {
        if remaining.count <= maxGraphemes {
            chunks.append(remaining)
            break
        }

        let candidate = String(remaining.prefix(maxGraphemes))

        if let r = candidate.range(of: "\n\n", options: .backwards) {
            chunks.append(String(remaining[remaining.startIndex..<r.lowerBound]))
            remaining = String(remaining[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }
        if let r = candidate.range(of: ". ", options: .backwards) {
            let end = remaining.index(after: r.lowerBound)
            chunks.append(String(remaining[remaining.startIndex..<end]))
            remaining = String(remaining[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }
        if let r = candidate.range(of: " ", options: .backwards) {
            chunks.append(String(remaining[remaining.startIndex..<r.lowerBound]))
            remaining = String(remaining[r.upperBound...])
            continue
        }
        chunks.append(candidate)
        remaining = String(remaining.dropFirst(maxGraphemes))
    }

    return chunks
}

// MARK: - Post Thread Builder

typealias PostEntry = (text: String, facets: [[String: Any]])

func buildThread(summary: String, buildNumber: String, commitURL: String?) -> [PostEntry] {
    let maxChars = 300
    let header   = "🛠️ Grit Build #\(buildNumber)"

    let linkLine: String
    if let url = commitURL { linkLine = "🔗 \(url)" } else { linkLine = "" }

    let single = linkLine.isEmpty
        ? "\(header)\n\n\(summary)"
        : "\(header)\n\n\(summary)\n\n\(linkLine)"

    if single.count <= maxChars {
        return [(text: single, facets: commitURL.map { makeLinkFacets(in: single, url: $0) } ?? [])]
    }

    let first = linkLine.isEmpty
        ? "\(header) — What's New 🧵"
        : "\(header) — What's New 🧵\n\n\(linkLine)"

    var thread: [PostEntry] = [
        (text: first, facets: commitURL.map { makeLinkFacets(in: first, url: $0) } ?? [])
    ]

    for chunk in splitIntoChunks(summary, maxGraphemes: maxChars) {
        thread.append((text: chunk, facets: []))
    }

    return thread
}

func makeLinkFacets(in text: String, url: String) -> [[String: Any]] {
    guard let range = text.range(of: url) else { return [] }
    let byteStart = text[text.startIndex..<range.lowerBound].utf8.count
    let byteEnd   = byteStart + text[range].utf8.count
    return [[
        "index": ["byteStart": byteStart, "byteEnd": byteEnd],
        "features": [["$type": "app.bsky.richtext.facet#link", "uri": url]]
    ]]
}

// MARK: - Bluesky API

func blueskyAuth(handle: String, password: String) async throws -> (did: String, jwt: String) {
    let url = URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "identifier": handle,
        "password": password
    ])

    let (data, resp) = try await URLSession.shared.data(for: request)
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
        let body = String(data: data, encoding: .utf8) ?? "unknown"
        throw ScriptError.blueskyAPI("Auth failed (\(status)): \(body)")
    }

    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    guard let did = json["did"] as? String, let jwt = json["accessJwt"] as? String else {
        throw ScriptError.blueskyAPI("Auth response missing did / accessJwt")
    }
    return (did, jwt)
}

func blueskyPost(
    did: String, jwt: String,
    text: String, facets: [[String: Any]],
    reply: (root: PostRef, parent: PostRef)? = nil
) async throws -> PostRef {
    let url = URL(string: "https://bsky.social/xrpc/com.atproto.repo.createRecord")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var record: [String: Any] = [
        "$type":     "app.bsky.feed.post",
        "text":      text,
        "createdAt": formatter.string(from: Date()),
        "langs":     ["en"]
    ]
    if !facets.isEmpty { record["facets"] = facets }
    if let reply = reply {
        record["reply"] = [
            "root":   ["uri": reply.root.uri,   "cid": reply.root.cid],
            "parent": ["uri": reply.parent.uri, "cid": reply.parent.cid]
        ]
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "repo":       did,
        "collection": "app.bsky.feed.post",
        "record":     record
    ])

    let (data, resp) = try await URLSession.shared.data(for: request)
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
        let body = String(data: data, encoding: .utf8) ?? "unknown"
        throw ScriptError.blueskyAPI("Post failed (\(status)): \(body)")
    }

    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    guard let uri = json["uri"] as? String, let cid = json["cid"] as? String else {
        throw ScriptError.blueskyAPI("Post response missing uri / cid")
    }
    return PostRef(uri: uri, cid: cid)
}

// MARK: - Entry Point

func main() async throws {
    // ── 1. Configuration ────────────────────────────────────────────────
    let buildNumber  = try requiredEnv("CI_BUILD_NUMBER")
    let commitSHA    = try requiredEnv("CI_COMMIT")
    let bskyHandle   = try requiredEnv("BLUESKY_HANDLE")
    let bskyPassword = try requiredEnv("BLUESKY_APP_PASSWORD")
    let dryRun       = env("DRY_RUN") == "true"

    // ── 2. Gather changes ───────────────────────────────────────────────
    print("📋 Gathering git changes…")
    let (commits, diffStat, diff) = gatherGitChanges(commitSHA: commitSHA)

    guard !commits.isEmpty else {
        print("ℹ️  No commits found in range — skipping Bluesky post.")
        return
    }

    // ── 3. AI summary ───────────────────────────────────────────────────
    print("🤖 Generating summary…")
    let summary = await generateSummary(commits: commits, diffStat: diffStat, diff: diff)

    // ── 4. Build thread ─────────────────────────────────────────────────
    let commitURL = githubCommitURL(commitSHA: commitSHA)
    let thread = buildThread(summary: summary, buildNumber: buildNumber, commitURL: commitURL)
    print("📝 Prepared \(thread.count) post\(thread.count == 1 ? "" : "s")")

    // ── 5. Dry-run output ───────────────────────────────────────────────
    if dryRun {
        print("\n🏁 DRY RUN — posts that would be published:\n")
        for (i, post) in thread.enumerated() {
            print("─── Post \(i + 1) (\(post.text.count) chars) ───")
            print(post.text)
            print()
        }
        return
    }

    // ── 6. Authenticate ─────────────────────────────────────────────────
    print("🔐 Authenticating with Bluesky…")
    let (did, jwt) = try await blueskyAuth(handle: bskyHandle, password: bskyPassword)

    // ── 7. Publish thread ───────────────────────────────────────────────
    print("📤 Posting to Bluesky…")
    var rootRef: PostRef?
    var parentRef: PostRef?

    for (i, post) in thread.enumerated() {
        let replyCtx: (root: PostRef, parent: PostRef)?
        if let root = rootRef, let parent = parentRef {
            replyCtx = (root: root, parent: parent)
        } else {
            replyCtx = nil
        }

        let ref = try await blueskyPost(
            did: did, jwt: jwt,
            text: post.text, facets: post.facets,
            reply: replyCtx
        )

        if i == 0 { rootRef = ref }
        parentRef = ref
        print("   ✅ Post \(i + 1)/\(thread.count) published")
    }

    print("\n🎉 Changelog posted to Bluesky!")
}

// ── Run ─────────────────────────────────────────────────────────────────
let semaphore = DispatchSemaphore(value: 0)
var scriptExitCode: Int32 = 0

Task {
    do {
        try await main()
    } catch {
        fputs("❌ \(error.localizedDescription)\n", stderr)
        scriptExitCode = 1
    }
    semaphore.signal()
}

semaphore.wait()
exit(scriptExitCode)
