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

    /// - Parameter readmeURL: the project's `readme_url`; lets the README be
    ///   fetched with a single request instead of probing candidate filenames.
    func load(projectID: Int, ref: String, readmeURL: String? = nil,
              pipeline: Pipeline? = nil) async {
        guard let token = auth.accessToken else { return }
        // Both values are cached — only show the skeleton when we have nothing.
        isLoading = contributors.isEmpty && readmeContent == nil
        error     = nil
        defer { isLoading = false }

        // Fire off contributors (throwing) and README (non-throwing) concurrently.
        // Both go through RepoContentLoader, so the detail view, info tab and
        // info overlay share one cached copy instead of each fetching their own.
        async let contribsTask: [GitLabContributor] = RepoContentLoader.contributors(
            projectID: projectID, baseURL: auth.baseURL, token: token
        )
        async let readmeTask: String? = RepoContentLoader.readme(
            projectID: projectID, ref: ref, readmeURL: readmeURL,
            baseURL: auth.baseURL, token: token
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

        guard AIAssistantService.shared.isUserEnabled else { return }

        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        // Quick task — the service keeps it on-device.
        if let summary = try? await AIAssistantService.shared.summarizeReadme(
            description: description, readme: readme
        ) {
            readmeSummary = summary
        }
    }
}
