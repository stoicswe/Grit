import Foundation
import SwiftUI

@MainActor
final class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()

    @Published var isAuthenticated = false
    @Published var currentUser: GitLabUser?
    @Published var baseURL: String = "https://gitlab.com"
    @Published var isLoading = false
    @Published var error: String?

    private let keychain = KeychainService.shared

    private init() {
        Task { await restoreSession() }
    }

    func restoreSession() async {
        guard
            let token = try? keychain.retrieve(for: .accessToken),
            let savedURL = try? keychain.retrieve(for: .baseURL)
        else {
            isAuthenticated = false
            return
        }
        baseURL = savedURL
        do {
            let user = try await GitLabAPIService.shared.fetchCurrentUser(baseURL: savedURL, token: token)
            currentUser = user
            isAuthenticated = true
        } catch {
            isAuthenticated = false
        }
    }

    func login(baseURL: String, token: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let normalizedURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL

        let user = try await GitLabAPIService.shared.fetchCurrentUser(baseURL: normalizedURL, token: token)
        try keychain.save(token, for: .accessToken)
        try keychain.save(normalizedURL, for: .baseURL)

        self.baseURL = normalizedURL
        currentUser = user
        isAuthenticated = true
    }

    func logout() {
        keychain.clearAll()
        currentUser = nil
        isAuthenticated = false
        baseURL = "https://gitlab.com"
    }

    var accessToken: String? {
        try? keychain.retrieve(for: .accessToken)
    }
}
