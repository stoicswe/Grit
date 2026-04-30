import Foundation

// Apple Intelligence / Foundation Models integration
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class RepoInfoViewModel: ObservableObject {
    @Published var contributors:        [GitLabContributor] = []
    @Published var readmeContent:       String?             = nil
    @Published var pipelineJobs:        [PipelineJob]       = []
    @Published var isLoading:           Bool                = false
    @Published var error:               String?             = nil
    @Published var readmeSummary:       String?             = nil
    @Published var isGeneratingSummary: Bool                = false

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: - Load

    func load(projectID: Int, ref: String, pipeline: Pipeline? = nil) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error     = nil
        defer { isLoading = false }

        // Fire off contributors (throwing) and README (non-throwing) concurrently.
        async let contribsTask: [GitLabContributor] = api.fetchContributors(
            projectID: projectID, baseURL: auth.baseURL, token: token
        )
        async let readmeTask: String? = api.fetchReadme(
            projectID: projectID, ref: ref, baseURL: auth.baseURL, token: token
        )

        do {
            contributors = try await contribsTask
        } catch {
            self.error = error.localizedDescription
        }
        readmeContent = await readmeTask

        // Fetch pipeline jobs silently — failure leaves pipelineJobs empty and
        // the build status section simply omits the stage breakdown.
        if let pipeline {
            pipelineJobs = (try? await api.fetchPipelineJobs(
                projectID: projectID,
                pipelineID: pipeline.id,
                baseURL: auth.baseURL,
                token: token
            )) ?? []
        }
    }

    // MARK: - README summary

    /// Generates a 6-sentence README summary and appends it to the description
    /// if the existing description is short (fewer than 3 sentences).
    /// Only runs when Apple Intelligence is available and user-enabled.
    func generateDescriptionSummary(description: String, readme: String) async {
        guard !readme.isEmpty else { return }

        // Count sentences — if 3 or more, description is sufficient
        let sentenceCount = description
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        guard sentenceCount < 3 else { return }

        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard SystemLanguageModel.default.isAvailable,
                  SettingsStore.shared.appleIntelligenceEnabled else { return }

            isGeneratingSummary = true
            defer { isGeneratingSummary = false }

            let session = LanguageModelSession()
            let truncatedReadme = String(readme.prefix(6000))
            let prompt = """
            Based on the following README, write exactly 6 sentences summarizing what \
            this repository does, its key features, and its purpose. Write in plain \
            prose with no bullet points, markdown, or headers. Do not repeat or \
            rephrase the existing description: "\(description)".

            README:
            \(truncatedReadme)
            """

            if let response = try? await session.respond(to: prompt) {
                readmeSummary = response.content
            }
        }
        #endif
    }
}
