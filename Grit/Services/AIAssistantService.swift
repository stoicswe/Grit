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
        isAvailable = SystemLanguageModel.default.isAvailable
        #endif
    }

    func analyzeCode(_ code: String, instruction: String) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else { throw AIError.notAvailable }
        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()
        let prompt = """
        You are a helpful code assistant. \(instruction)

        ```
        \(code)
        ```
        """
        let response = try await session.respond(to: prompt)
        lastResponse = response.content
        return response.content
        #else
        throw AIError.notAvailable
        #endif
    }

    func reviewMergeRequest(title: String, description: String, diff: String) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else { throw AIError.notAvailable }
        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()
        let prompt = """
        Review this merge request concisely:

        Title: \(title)
        Description: \(description.isEmpty ? "No description provided." : description)

        Changes (truncated):
        \(diff.prefix(4000))

        Provide:
        1. A one-line summary
        2. Key concerns or issues (if any)
        3. Suggested improvements (if any)
        """
        let response = try await session.respond(to: prompt)
        lastResponse = response.content
        return response.content
        #else
        throw AIError.notAvailable
        #endif
    }

    func explainCommit(message: String, stats: String, diff: String) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else { throw AIError.notAvailable }
        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()

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

        let response = try await session.respond(to: prompt)
        lastResponse = response.content
        return response.content
        #else
        throw AIError.notAvailable
        #endif
    }

    enum AIError: LocalizedError {
        case notAvailable

        var errorDescription: String? {
            "Apple Intelligence is not available on this device or region."
        }
    }
}
