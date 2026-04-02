import Foundation
import SwiftUI
import WebKit

@MainActor
final class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()

    @Published var isAuthenticated    = false
    @Published var isRestoringSession = true   // true until the first restoreSession() finishes
    @Published var currentUser: GitLabUser?
    @Published var baseURL: String = "https://gitlab.com"
    @Published var isLoading = false
    @Published var error: String?

    private let keychain = KeychainService.shared

    // UserDefaults key for storing OAuth token expiry timestamp.
    private let expiryKey = "com.grit.oauth.tokenExpiry"

    private init() {
        Task { await restoreSession() }
    }

    // MARK: - Session restoration

    func restoreSession() async {
        defer { isRestoringSession = false }

        guard
            let token      = try? keychain.retrieve(for: .accessToken),
            let savedURL   = try? keychain.retrieve(for: .baseURL)
        else {
            isAuthenticated = false
            clearWebAuthCache()
            return
        }

        baseURL = savedURL

        // If an OAuth refresh token is available and the access token is expired
        // (or about to expire within 5 minutes), try to refresh silently first.
        if isOAuthTokenExpiredOrSoon(),
           let refreshToken = try? keychain.retrieve(for: .refreshToken),
           let clientID     = try? keychain.retrieve(for: .oauthClientID) {
            do {
                let newTokens = try await OAuthService.shared.refresh(
                    refreshToken: refreshToken,
                    baseURL: savedURL,
                    clientID: clientID
                )
                try storeOAuthTokens(newTokens, baseURL: savedURL, clientID: clientID)
            } catch {
                // Refresh failed — fall through and try the stored access token.
                // If that also fails below, we clear and show login.
            }
        }

        // Validate whatever access token we now have.
        guard let currentToken = try? keychain.retrieve(for: .accessToken) else {
            isAuthenticated = false
            keychain.clearAll()
            clearWebAuthCache()
            return
        }

        do {
            let user = try await GitLabAPIService.shared.fetchCurrentUser(
                baseURL: savedURL, token: currentToken)
            currentUser     = user
            isAuthenticated = true
        } catch {
            isAuthenticated = false
            keychain.clearAll()
            clearWebAuthCache()
        }
    }

    // MARK: - Login: Personal Access Token

    func login(baseURL: String, token: String) async throws {
        isLoading = true
        error     = nil
        defer { isLoading = false }
        let url = normalize(baseURL)
        try await validateAndStore(baseURL: url, token: token)
        // PAT sessions have no refresh token — clear any leftover OAuth keys.
        keychain.delete(for: .refreshToken)
        keychain.delete(for: .oauthClientID)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

    // MARK: - Login: OAuth

    /// Runs the OAuth PKCE browser flow for the given GitLab instance.
    /// - Parameters:
    ///   - baseURL:  GitLab instance root URL.
    ///   - clientID: Application ID from the registered non-confidential OAuth app.
    func loginWithOAuth(baseURL: String, clientID: String) async throws {
        isLoading = true
        error     = nil
        defer { isLoading = false }
        let url    = normalize(baseURL)
        let tokens = try await OAuthService.shared.authenticate(baseURL: url, clientID: clientID)
        try await validateAndStore(baseURL: url, token: tokens.accessToken)
        try storeOAuthTokens(tokens, baseURL: url, clientID: clientID)
    }

    // MARK: - Logout

    func logout() {
        keychain.clearAll()
        UserDefaults.standard.removeObject(forKey: expiryKey)
        // Signal OAuthService to use an ephemeral browser session on the next
        // sign-in attempt, so the previous account's Safari cookie is not reused.
        UserDefaults.standard.set(true, forKey: OAuthService.freshSessionKey)
        clearWebAuthCache()
        currentUser     = nil
        isAuthenticated = false
        baseURL         = "https://gitlab.com"
    }

    // MARK: - Token refresh (callable externally, e.g. on 401)

    /// Attempts to refresh the OAuth access token using the stored refresh token.
    /// Returns `true` if the token was successfully refreshed.
    @discardableResult
    func refreshOAuthTokenIfNeeded() async -> Bool {
        guard
            isOAuthTokenExpiredOrSoon(),
            let refreshToken = try? keychain.retrieve(for: .refreshToken),
            let clientID     = try? keychain.retrieve(for: .oauthClientID)
        else { return false }

        do {
            let newTokens = try await OAuthService.shared.refresh(
                refreshToken: refreshToken,
                baseURL: baseURL,
                clientID: clientID
            )
            try storeOAuthTokens(newTokens, baseURL: baseURL, clientID: clientID)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Accessors

    var accessToken: String? {
        try? keychain.retrieve(for: .accessToken)
    }

    // MARK: - Private helpers

    private func normalize(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    private func validateAndStore(baseURL: String, token: String) async throws {
        let user = try await GitLabAPIService.shared.fetchCurrentUser(
            baseURL: baseURL, token: token)
        try keychain.save(token,   for: .accessToken)
        try keychain.save(baseURL, for: .baseURL)
        self.baseURL   = baseURL
        currentUser    = user
        isAuthenticated = true
    }

    /// Persists OAuth-specific credentials (refresh token, client ID, expiry).
    private func storeOAuthTokens(_ tokens: OAuthTokens,
                                   baseURL: String,
                                   clientID: String) throws {
        // Always update the access token in case this was a refresh.
        try keychain.save(tokens.accessToken, for: .accessToken)
        if let rt = tokens.refreshToken {
            try keychain.save(rt, for: .refreshToken)
        }
        try keychain.save(clientID, for: .oauthClientID)
        let expiry = Date().addingTimeInterval(Double(tokens.expiresIn))
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: expiryKey)
    }

    /// Returns `true` if the stored OAuth access token has expired or expires within 5 minutes.
    private func isOAuthTokenExpiredOrSoon() -> Bool {
        let stored = UserDefaults.standard.double(forKey: expiryKey)
        guard stored > 0 else { return false }   // no expiry recorded → PAT, never expires
        let expiry = Date(timeIntervalSince1970: stored)
        return expiry.timeIntervalSinceNow < 5 * 60
    }

    // MARK: - Web auth cache

    /// Clears WKWebView / ASWebAuthenticationSession browser state so stale OAuth
    /// sessions cannot block a fresh sign-in attempt.
    private func clearWebAuthCache() {
        let store     = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { records in
            store.removeData(ofTypes: dataTypes, for: records) { }
        }
        HTTPCookieStorage.shared.cookies?.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }
    }
}
