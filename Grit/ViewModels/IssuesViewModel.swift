import Foundation

@MainActor
final class IssuesViewModel: ObservableObject {

    enum IssueState: String, CaseIterable {
        case opened = "opened"
        case closed = "closed"
        case all    = "all"

        var label: String {
            switch self {
            case .opened: return "Open"
            case .closed: return "Closed"
            case .all:    return "All"
            }
        }
    }

    @Published var issues:       [GitLabIssue] = []
    @Published var isLoading     = false
    @Published var error:        String?
    @Published var hasMore       = false
    @Published var stateFilter:  IssueState = .opened

    private var currentPage = 1
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(projectID: Int, refresh: Bool = false) async {
        guard let token = auth.accessToken else { return }
        if refresh {
            currentPage = 1
            issues = []
            hasMore = false
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchIssues(
                projectID: projectID,
                state: stateFilter.rawValue,
                baseURL: auth.baseURL,
                token: token,
                page: currentPage
            )
            issues += fetched
            hasMore = fetched.count == 20
            if hasMore { currentPage += 1 }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
