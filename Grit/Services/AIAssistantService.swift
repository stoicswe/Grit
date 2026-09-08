import Foundation
import SwiftUI

// Apple Intelligence / Foundation Models integration
// Requires iOS 26+ with FoundationModels framework
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AIAssistantService: ObservableObject {
    static let shared = AIAssistantService()

    @Published var isAvailable: Bool = false
    @Published var isProcessing: Bool = false
    @Published var lastResponse: String = ""

    var isUserEnabled: Bool {
        isAvailable && SettingsStore.shared.appleIntelligenceEnabled
    }

    private init() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            isAvailable = SystemLanguageModel.default.isAvailable
        }
        #endif
    }

    // MARK: - Model routing
    //
    // Two models can serve a request:
    //
    //  * The on-device model (`SystemLanguageModel.default`). Fast, private,
    //    no quota, ~4k-token context. On iOS 27 the system picks the strongest
    //    on-device variant the hardware supports ("Core" or "Core Advanced");
    //    there is no API to request one explicitly.
    //  * Apple's server model on Private Cloud Compute
    //    (`PrivateCloudComputeLanguageModel`, iOS 27+). Considerably more
    //    capable, 32k-token context, but metered and network-bound.
    //
    // Routing is automatic: quick, short tasks stay on-device; in-depth work
    // (code review, commit explanations with diffs, large files, repo-wide
    // questions) or anything that won't fit the on-device window goes to the
    // cloud model when the device offers it. Each path falls back to the other
    // on failure.

    /// How demanding a request is. Callers describe the task; the service
    /// picks the model.
    enum Complexity {
        /// Short summaries and rewrites over small inputs.
        case quick
        /// Reasoning over diffs, whole files, or repository context.
        case intricate
    }

    /// Approximate prompt budgets (characters) per model, leaving headroom for
    /// the reply. Callers use `contextBudget(for:)` to trim what they embed.
    private static let onDeviceCharBudget = 9_000
    private static let cloudCharBudget    = 90_000

    /// Info.plist flag mirroring the `com.apple.developer.private-cloud-compute`
    /// entitlement. Apple grants that entitlement per app (request form:
    /// https://developer.apple.com/contact/request/private-cloud-compute/).
    /// Using `PrivateCloudComputeLanguageModel` without it is a `fatalError`
    /// inside FoundationModels — not a thrown error — so the cloud path must be
    /// unreachable until the entitlement is in `Grit.entitlements` and this key
    /// (`GritPrivateCloudComputeEnabled`) is set to YES in `project.yml`.
    private static let cloudEntitlementDeclared: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "GritPrivateCloudComputeEnabled") as? Bool) ?? false

    /// True when the Private Cloud Compute model can be used right now.
    var cloudModelAvailable: Bool {
        guard Self.cloudEntitlementDeclared else { return false }
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27, *) { return CloudModel.shared.isAvailable }
        #endif
        return false
    }

    /// Human-readable routing summary for the Settings screen.
    var routingDescription: String {
        guard isAvailable else { return "Not available on this device" }
        return cloudModelAvailable
            ? "On-device · Private Cloud Compute for in-depth tasks"
            : "On-device · Private"
    }

    /// Largest amount of context (characters) a caller should embed for the
    /// given complexity, matching the model that will most likely serve it.
    func contextBudget(for complexity: Complexity) -> Int {
        (complexity == .intricate && cloudModelAvailable)
            ? Self.cloudCharBudget - 2_000
            : Self.onDeviceCharBudget - 2_000
    }

    #if canImport(FoundationModels) && compiler(>=6.4)
    @available(iOS 27, *)
    private enum CloudModel {
        static let shared = PrivateCloudComputeLanguageModel()
    }
    #endif

    /// Sends `prompt` to the model best suited to `complexity` and returns the
    /// reply text. Falls back between cloud and on-device on failure.
    func respond(to prompt: String, complexity: Complexity) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard isAvailable else { throw AIError.notAvailable }
            isProcessing = true
            defer { isProcessing = false }

            let preferCloud = cloudModelAvailable &&
                (complexity == .intricate || prompt.count > Self.onDeviceCharBudget)

            if preferCloud {
                if let text = try? await respondViaCloud(prompt) {
                    lastResponse = text
                    return text
                }
                // Cloud failed (offline, quota, service) — degrade to on-device.
            }

            do {
                let text = try await respondOnDevice(String(prompt.prefix(Self.onDeviceCharBudget)))
                lastResponse = text
                return text
            } catch {
                // On-device refused (e.g. context window) — one cloud attempt if
                // we haven't already tried it.
                if !preferCloud, cloudModelAvailable,
                   let text = try? await respondViaCloud(prompt) {
                    lastResponse = text
                    return text
                }
                throw error
            }
        }
        #endif
        throw AIError.notAvailable
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func respondOnDevice(_ prompt: String) async throws -> String {
        let session = LanguageModelSession()
        return try await session.respond(to: prompt).content
    }

    @available(iOS 26, *)
    private func respondViaCloud(_ prompt: String) async throws -> String {
        guard Self.cloudEntitlementDeclared else { throw AIError.notAvailable }
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            let session = LanguageModelSession(model: CloudModel.shared)
            return try await session.respond(to: String(prompt.prefix(Self.cloudCharBudget))).content
        }
        #endif
        throw AIError.notAvailable
    }
    #endif

    // MARK: - Tasks

    /// General code question. Routed by size: a short snippet stays on-device,
    /// a whole file or a repository-context question is "intricate".
    func analyzeCode(_ code: String, instruction: String) async throws -> String {
        let prompt = """
        You are a helpful code assistant, your goal is to help with understanding. \(instruction)

        ```
        \(code)
        ```
        """
        let complexity: Complexity = (code.count + instruction.count) > 2_500 ? .intricate : .quick
        return try await respond(to: prompt, complexity: complexity)
    }

    /// Full merge-request review — always an intricate task.
    func reviewMergeRequest(title: String, description: String, diff: String) async throws -> String {
        let prompt = """
        You are a senior software engineer, using your deep knowledge and understanding, review this merge request concisely:

        Title: \(title)
        Description: \(description.isEmpty ? "No description provided." : description)

        Changes:
        \(diff.isEmpty ? "(diff not available)" : diff)

        Provide:
        1. A short paragraph to explain the change
        2. Key concerns or issues (if any)
        3. Suggested improvements (if any)
        """
        return try await respond(to: prompt, complexity: .intricate)
    }

    /// Commit explanation — intricate when a diff is included.
    func explainCommit(message: String, stats: String, diff: String) async throws -> String {
        var prompt = """
        You are a senior software engineer reviewing a Git commit. \
        Explain clearly what this commit does, why it likely matters, and highlight \
        any notable implementation choices visible in the diff.

        ## Commit Message
        \(message)

        ## Change Stats
        \(stats)

        """
        if !diff.isEmpty {
            prompt += """

        ## File Diffs
        \(diff)

        """
        }
        prompt += """

        Respond in plain prose — no bullet points, no headers. \
        2–4 sentences. Focus on intent and impact, not line-by-line narration.
        """
        return try await respond(to: prompt, complexity: diff.isEmpty ? .quick : .intricate)
    }

    /// Six-sentence README summary — a quick, on-device task.
    func summarizeReadme(description: String, readme: String) async throws -> String {
        let prompt = """
        Based on the following README, write exactly 6 sentences summarizing what \
        this repository does, its key features, and its purpose. Write in plain \
        prose with no bullet points, markdown, or headers. Do not repeat or \
        rephrase the existing description: "\(description)".

        README:
        \(readme.prefix(6_000))
        """
        return try await respond(to: prompt, complexity: .quick)
    }

    /// Drafts a squash-commit message for a merge request: an imperative
    /// subject line followed by one or two sentences summarising the change.
    /// Intricate when a diff excerpt is supplied (the model reasons over code).
    ///
    /// - Parameters:
    ///   - title / description: from the merge request.
    ///   - changeSummary: one line per file, e.g. `M Sources/App.swift (+12 −3)`.
    ///   - diff: unified diff excerpt (trimmed by the caller to `contextBudget`).
    func suggestSquashCommitMessage(
        title: String,
        description: String,
        changeSummary: String,
        diff: String
    ) async throws -> String {
        var prompt = """
        You write Git commit messages. Draft the message for a single squash commit \
        that combines all of this merge request's changes.

        Format, exactly:
        - Line 1: an imperative subject of at most 72 characters (e.g. "Add ETag caching to API layer"). No trailing period.
        - Line 2: blank.
        - Then one or two plain sentences explaining what changed and why. No bullet points, no headers, no markdown, no quotes around the message.

        Merge request title: \(title)
        Description: \(description.isEmpty ? "No description provided." : description.prefix(1200))

        Changed files:
        \(changeSummary.isEmpty ? "(not available)" : changeSummary)
        """
        if !diff.isEmpty {
            prompt += """


        Diff excerpt:
        \(diff)
        """
        }
        prompt += "\n\nRespond with the commit message only."
        let text = try await respond(to: prompt, complexity: diff.isEmpty ? .quick : .intricate)
        return Self.cleanCommitMessage(text)
    }

    /// Strips code fences / surrounding quotes the model sometimes adds and
    /// normalises whitespace so the result drops straight into a text field.
    private static func cleanCommitMessage(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count > 1 {
            text = String(text.dropFirst().dropLast())
        }
        // Collapse 3+ newlines to the single blank line between subject and body.
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\\n\\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum AIError: LocalizedError {
        case notAvailable

        var errorDescription: String? {
            "Apple Intelligence is not available on this device or region."
        }
    }
}
