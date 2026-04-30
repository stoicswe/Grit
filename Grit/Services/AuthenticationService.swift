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
    @Published var plan: GitLabPlan = .free

    private let keychain = KeychainService.shared

    // UserDefaults key for storing OAuth token expiry timestamp.
    private let expiryKey = "com.grit.oauth.tokenExpiry"

    // UserDefaults key prefix for the cached current user (username + avatar).
    // Keyed per host so switching GitLab instances never shows the wrong account.
    private var currentUserCacheKey: String {
        let host = URL(string: baseURL)?.host ?? baseURL
        return "com.grit.currentUser.cache.\(host)"
    }

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

        // Restore the cached user immediately so the UI can show the username
        // and avatar before the network fetch completes.
        if let cached = readCachedUser() {
            currentUser = cached
        }

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
            } catch let urlError as URLError where isTransientNetworkError(urlError) {
                // Network not yet available (device waking from sleep).
                // Credentials are intact — stay logged in and retry on the next
                // foreground transition once the network is ready.
                isAuthenticated = true
                return
            } catch {
                // Refresh token may have been rejected — fall through and try the
                // stored access token. If that also fails below, we clear and show login.
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
            writeCachedUser(user)
            isAuthenticated = true
            Task { await refreshPlan() }
        } catch let urlError as URLError
                  where isTransientNetworkError(urlError) {
            // Device is offline or the network is briefly unavailable.
            // Credentials are valid — stay logged in so the user isn't forced
            // to re-authenticate just because of a bad connection at launch.
            // Individual views will surface their own connectivity errors, and
            // the next foreground transition will re-validate the session.
            isAuthenticated = true
        } catch {
            // Definitive auth failure (e.g. 401 / revoked token) — clear and log out.
            isAuthenticated = false
            keychain.clearAll()
            clearWebAuthCache()
        }
    }

    // MARK: - Foreground session refresh

    /// Called each time the app returns to the foreground (scenePhase → .active).
    ///
    /// Silently refreshes the OAuth access token if it has expired or is about to,
    /// then does a lightweight user-ping to confirm the session is still valid.
    /// The user is only redirected to login if the session is definitively invalid
    /// and cannot be recovered — transient network failures are ignored so a brief
    /// loss of connectivity never logs the user out.
    func refreshSessionOnForeground() async {
        guard isAuthenticated else { return }

        // ── Step 1: proactively rotate an expiring OAuth token ─────────────
        if isOAuthTokenExpiredOrSoon() {
            // refreshOAuthTokenIfNeeded updates the keychain on success.
            // If it returns false the token may still be usable — GitLab
            // servers sometimes accept slightly-expired tokens, so we fall
            // through and let the API ping below decide.
            _ = await refreshOAuthTokenIfNeeded()
        }

        // ── Step 2: validate the session with a lightweight user fetch ─────
        guard
            let token    = try? keychain.retrieve(for: .accessToken),
            let savedURL = try? keychain.retrieve(for: .baseURL)
        else {
            isAuthenticated = false
            return
        }

        do {
            let user = try await GitLabAPIService.shared.fetchCurrentUser(
                baseURL: savedURL, token: token)
            currentUser = user   // refresh stale profile data in the background
            writeCachedUser(user)
        } catch let urlError as URLError where isTransientNetworkError(urlError) {
            // No connectivity — stay logged in; individual views will surface
            // their own errors when the user tries to load data.
            return
        } catch {
            // Likely a 401.  Make one unconditional refresh attempt before
            // giving up so server-side token rotations are handled gracefully.
            if let newToken = await refreshTokenUnconditionally() {
                // Token refreshed — re-validate with the new token.
                if let user = try? await GitLabAPIService.shared.fetchCurrentUser(
                    baseURL: savedURL, token: newToken) {
                    currentUser = user
                    writeCachedUser(user)
                }
                // Even if the second ping fails, keep the user logged in —
                // we have a fresh token; the session is almost certainly valid.
            } else {
                // No refresh path available and the session is invalid.
                isAuthenticated = false
                keychain.clearAll()
                clearWebAuthCache()
            }
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
        clearCachedUser()   // must run before baseURL is reset so the key resolves correctly
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

    /// Unconditionally attempts an OAuth refresh — used by the API layer after receiving a
    /// 401, where the client-side expiry clock may be wrong (e.g. server-side revocation)
    /// or the token expired between the last proactive check and the network call.
    /// Returns the new access token string on success, or `nil` if refresh is not possible
    /// (PAT user, no refresh token stored) or if the refresh request itself fails.
    func refreshTokenUnconditionally() async -> String? {
        guard
            let refreshToken = try? keychain.retrieve(for: .refreshToken),
            let clientID     = try? keychain.retrieve(for: .oauthClientID)
        else { return nil }   // PAT user — nothing to refresh

        do {
            let newTokens = try await OAuthService.shared.refresh(
                refreshToken: refreshToken,
                baseURL: baseURL,
                clientID: clientID
            )
            try storeOAuthTokens(newTokens, baseURL: baseURL, clientID: clientID)
            return newTokens.accessToken
        } catch {
            return nil
        }
    }

    // MARK: - Plan detection

    /// Fetches and stores the GitLab plan in the background. Non-fatal — stays `.free` on error.
    func refreshPlan() async {
        guard let token = accessToken else { return }
        plan = (try? await GitLabAPIService.shared.fetchCurrentPlan(
            baseURL: baseURL, token: token
        )) ?? .free
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
        writeCachedUser(user)
        isAuthenticated = true
        Task { await refreshPlan() }
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

    /// Returns `true` for URLErrors that indicate a temporary network condition
    /// rather than a server-side auth rejection.
    private func isTransientNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// Returns `true` if the stored OAuth access token has expired or expires within 5 minutes.
    private func isOAuthTokenExpiredOrSoon() -> Bool {
        let stored = UserDefaults.standard.double(forKey: expiryKey)
        guard stored > 0 else { return false }   // no expiry recorded → PAT, never expires
        let expiry = Date(timeIntervalSince1970: stored)
        return expiry.timeIntervalSinceNow < 5 * 60
    }

    // MARK: - Current user cache

    /// Persists the authenticated user's data to UserDefaults so the profile
    /// header (username, avatar) renders instantly on the next cold launch.
    private func writeCachedUser(_ user: GitLabUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: currentUserCacheKey)
    }

    private func readCachedUser() -> GitLabUser? {
        guard let data = UserDefaults.standard.data(forKey: currentUserCacheKey) else { return nil }
        return try? JSONDecoder().decode(GitLabUser.self, from: data)
    }

    private func clearCachedUser() {
        UserDefaults.standard.removeObject(forKey: currentUserCacheKey)
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
