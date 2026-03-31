import Foundation
import SwiftUI

@MainActor
final class MergeRequestViewModel: ObservableObject {
    @Published var mergeRequests: [MergeRequest] = []
    @Published var selectedMR: MergeRequest?
    @Published var notes: [MRNote] = []
    @Published var isLoading = false
    @Published var isApproving = false
    @Published var error: String?
    @Published var filterState: String = "opened"
    @Published var aiReview: String?
    @Published var isAILoading = false

    private let api = GitLabAPIService.shared
    private let auth = AuthenticationService.shared
    private let ai = AIAssistantService.shared

    func loadMergeRequests(projectID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            mergeRequests = try await api.fetchMergeRequests(
                projectID: projectID,
                state: filterState,
                baseURL: auth.baseURL,
                token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMergeRequestDetail(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let mrTask = api.fetchMergeRequest(projectID: projectID, mrIID: mrIID, baseURL: auth.baseURL, token: token)
            async let notesTask = api.fetchMRNotes(projectID: projectID, mrIID: mrIID, baseURL: auth.baseURL, token: token)
            let (mr, fetchedNotes) = try await (mrTask, notesTask)
            selectedMR = mr
            notes = fetchedNotes.filter { !$0.system }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func approve(projectID: Int, mrIID: Int) async {
        guard let token = auth.accessToken else { return }
        isApproving = true
        defer { isApproving = false }
        do {
            try await api.approveMergeRequest(projectID: projectID, mrIID: mrIID, baseURL: auth.baseURL, token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addComment(projectID: Int, mrIID: Int, body: String) async {
        guard let token = auth.accessToken, !body.isEmpty else { return }
        do {
            let note = try await api.addMRComment(
                projectID: projectID, mrIID: mrIID, body: body, baseURL: auth.baseURL, token: token
            )
            notes.append(note)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func requestAIReview() async {
        guard let mr = selectedMR else { return }
        isAILoading = true
        defer { isAILoading = false }
        do {
            aiReview = try await ai.reviewMergeRequest(
                title: mr.title,
                description: mr.description ?? "",
                diff: "See merge request \(mr.iid)"
            )
        } catch {
            aiReview = "AI review unavailable: \(error.localizedDescription)"
        }
    }
}
