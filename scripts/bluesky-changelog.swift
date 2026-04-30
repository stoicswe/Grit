#!/usr/bin/env swift
//
// bluesky-changelog.swift
//
// Uses Apple Intelligence (FoundationModels) to summarise the most notable
// changes in a GitLab CI pipeline, then posts the result as a Bluesky thread.
//
// The first post always contains a link back to the pipeline. If the summary
// is short enough it is included in that same post; otherwise the summary
// continues in threaded replies.
//
// Required CI/CD variables (set in GitLab → Settings → CI/CD → Variables):
//   BLUESKY_HANDLE        – Bluesky handle  (e.g. grit-app.bsky.social)
//   BLUESKY_APP_PASSWORD  – App password     (Settings → App Passwords on Bluesky)
//
// Automatically available GitLab CI variables used:
//   CI_PIPELINE_URL, CI_PIPELINE_IID, CI_PROJECT_NAME,
//   CI_COMMIT_SHA, CI_COMMIT_BEFORE_SHA
//
// Optional:
//   DRY_RUN=true  – print posts to stdout without publishing

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

/// Returns the commit log, diffstat, and a truncated diff for the changes in this pipeline.
func gatherGitChanges(beforeSHA: String, commitSHA: String) -> (commits: String, diffStat: String, diff: String) {
    let isFirstPush = beforeSHA.isEmpty || beforeSHA.allSatisfy { $0 == "0" }

    let logRange  = isFirstPush ? "-20"                              : "\(beforeSHA)..\(commitSHA)"
    let diffRange = isFirstPush ? "\(commitSHA)~10..\(commitSHA)"    : "\(beforeSHA)..\(commitSHA)"

    let commits  = shell("git log \(logRange) --pretty=format:'%h %s' 2>/dev/null")
    let diffStat = shell("git diff \(diffRange) --stat 2>/dev/null")
    // Cap the raw diff so the AI prompt stays a reasonable size.
    let rawDiff  = shell("git diff \(diffRange) 2>/dev/null | head -500")

    return (commits, diffStat, String(rawDiff.prefix(8000)))
}

// MARK: - AI Summary (Apple Intelligence)

/// Asks Foundation Models to produce a concise, social-media-friendly summary.
/// Falls back to a bullet list of commit subjects if the model is unavailable.
func generateSummary(commits: String, diffStat: String, diff: String, projectName: String) async -> String {
    guard SystemLanguageModel.default.availability == .available else {
        fputs("⚠️  Apple Intelligence is not available on this machine — using commit log fallback.\n", stderr)
        return fallbackSummary(commits)
    }

    let instructions = """
    You are a developer-relations writer creating a social media changelog \
    post for "\(projectName)", an iOS GitLab client app.

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

/// Simple bullet-list of commit subjects used when AI is unavailable.
func fallbackSummary(_ commits: String) -> String {
    let lines = commits
        .components(separatedBy: "\n")
        .filter { !$0.isEmpty }
        .prefix(8)
        .map { "• \($0)" }
    return "Recent changes:\n" + lines.joined(separator: "\n")
}

// MARK: - Text Splitting (grapheme-aware)

/// Splits `text` into chunks of at most `maxGraphemes` grapheme clusters,
/// preferring paragraph → sentence → word boundaries.
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

        // Prefer paragraph break
        if let r = candidate.range(of: "\n\n", options: .backwards) {
            chunks.append(String(remaining[remaining.startIndex..<r.lowerBound]))
            remaining = String(remaining[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }
        // Then sentence break
        if let r = candidate.range(of: ". ", options: .backwards) {
            let end = remaining.index(after: r.lowerBound)
            chunks.append(String(remaining[remaining.startIndex..<end]))
            remaining = String(remaining[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }
        // Then word break
        if let r = candidate.range(of: " ", options: .backwards) {
            chunks.append(String(remaining[remaining.startIndex..<r.lowerBound]))
            remaining = String(remaining[r.upperBound...])
            continue
        }
        // Hard split (very long unbroken token — unlikely)
        chunks.append(candidate)
        remaining = String(remaining.dropFirst(maxGraphemes))
    }

    return chunks
}

// MARK: - Post Thread Builder

typealias PostEntry = (text: String, facets: [[String: Any]])

/// Builds an array of (text, facets) tuples ready for publishing.
/// The first entry always contains the pipeline link.
func buildThread(summary: String, pipelineURL: String, pipelineIID: String) -> [PostEntry] {
    let maxChars = 300
    let header   = "🛠️ Grit Build #\(pipelineIID)"
    let linkLine = "\(pipelineURL)"

    // Attempt a single post: header + summary + link
    let single = "\(header)\n\n\(summary)\n\n🔗 \(linkLine)"
    if single.count <= maxChars {
        return [(text: single, facets: makeLinkFacets(in: single, url: pipelineURL))]
    }

    // Multi-post thread: first post is the announcement + link
    let first = "\(header) — What's New 🧵\n\n🔗 \(linkLine)"
    var thread: [PostEntry] = [
        (text: first, facets: makeLinkFacets(in: first, url: pipelineURL))
    ]

    for chunk in splitIntoChunks(summary, maxGraphemes: maxChars) {
        thread.append((text: chunk, facets: []))
    }

    return thread
}

/// Creates a Bluesky rich-text link facet for the given URL inside `text`.
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

/// Authenticates with Bluesky and returns `(did, accessJwt)`.
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

/// Publishes a single post and returns a reference to it (for threading).
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
    let pipelineURL  = try requiredEnv("CI_PIPELINE_URL")
    let pipelineIID  = try requiredEnv("CI_PIPELINE_IID")
    let projectName  = env("CI_PROJECT_NAME") ?? "Grit"
    let commitSHA    = try requiredEnv("CI_COMMIT_SHA")
    let beforeSHA    = env("CI_COMMIT_BEFORE_SHA") ?? ""
    let bskyHandle   = try requiredEnv("BLUESKY_HANDLE")
    let bskyPassword = try requiredEnv("BLUESKY_APP_PASSWORD")
    let dryRun       = env("DRY_RUN") == "true"

    // ── 2. Gather changes ───────────────────────────────────────────────
    print("📋 Gathering git changes…")
    let (commits, diffStat, diff) = gatherGitChanges(beforeSHA: beforeSHA, commitSHA: commitSHA)

    guard !commits.isEmpty else {
        print("ℹ️  No commits found in range — skipping Bluesky post.")
        return
    }

    // ── 3. AI summary ───────────────────────────────────────────────────
    print("🤖 Generating summary with Apple Intelligence…")
    let summary = await generateSummary(
        commits: commits, diffStat: diffStat, diff: diff, projectName: projectName
    )

    // ── 4. Build thread ─────────────────────────────────────────────────
    let thread = buildThread(summary: summary, pipelineURL: pipelineURL, pipelineIID: pipelineIID)
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
