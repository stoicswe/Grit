import Foundation

/// A repository contributor as returned by the GitLab contributors endpoint.
/// GitLab does not provide avatar URLs here; the UI falls back to initials.
struct GitLabContributor: Codable, Identifiable {
    /// Stable identity used by `ForEach` — email is unique per contributor.
    var id: String { email }

    let name:      String
    let email:     String
    let commits:   Int
    let additions: Int
    let deletions: Int
}
