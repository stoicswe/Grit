import AuthenticationServices
import CryptoKit
import Foundation

// MARK: - GitLab.com Client ID
//
// To enable OAuth sign-in for GitLab.com:
//   1. Go to https://gitlab.com/-/profile/applications
//   2. Click "Add new application"
//   3. Name: Grit
//   4. Redirect URI: grit://oauth/callback
//   5. Uncheck "Confidential" (this is required for a native iOS app)
//   6. Scopes: api, read_user
//   7. Save — copy the Application ID shown and paste it below.
//
// For self-managed instances, each user registers their own application
// on their instance and provides the client_id in the login screen.
//
// ASWebAuthenticationSession intercepts the grit:// callback internally;
// no URL scheme entry in Info.plist is required.

extension OAuthService {
    /// Replace with the Application ID from your registered GitLab.com OAuth app.
    static let gitLabComClientID = "dc8393bf379546b9d1824a98f25aea0deb92ca34873c45ec8917d8bbc6568144"
}

// MARK: - Token model

struct OAuthTokens {
    let accessToken:  String
    let refreshToken: String?
    /// Seconds until the access token expires (GitLab issues 7 200 s / 2 h tokens).
    let expiresIn:    Int
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case cancelled
    case noAuthCode
    case notConfigured          // placeholder client_id still in place
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .noAuthCode:
            return "No authorization code was returned."
        case .notConfigured:
            return "OAuth is not configured. Replace the client ID in OAuthService.swift, or use a Personal Access Token to sign in."
        case .tokenExchangeFailed(let detail):
            return "Token exchange failed: \(detail)"
        }
    }
}

// MARK: - Service

@MainActor
final class OAuthService: NSObject {

    static let shared = OAuthService()

    private let callbackScheme = "grit"
    private let callbackURL    = "grit://oauth/callback"

    private var activeSession: ASWebAuthenticationSession?

    // MARK: - Authorization Code + PKCE

    /// Runs the full OAuth 2.0 PKCE Authorization Code flow.
    /// - Parameters:
    ///   - baseURL:  GitLab instance root, e.g. `https://gitlab.com`
    ///   - clientID: The Application ID from the registered OAuth app.
    func authenticate(baseURL: String, clientID: String) async throws -> OAuthTokens {
        guard !clientID.isEmpty,
              !clientID.hasPrefix("YOUR_") else { throw OAuthError.notConfigured }

        let (verifier, challenge) = makePKCE()
        let state   = UUID().uuidString
        let authURL = buildAuthorizationURL(baseURL: baseURL,
                                            clientID: clientID,
                                            challenge: challenge,
                                            state: state)

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    if let asErr = error as? ASWebAuthenticationSessionError,
                       asErr.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let url else {
                    continuation.resume(throwing: OAuthError.noAuthCode)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            // Use a shared session so the user's GitLab sign-in cookie is remembered
            // between subsequent app launches (they won't have to re-enter credentials).
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }

        let code = try extractCode(from: callbackURL)
        return try await exchange(
            params: [
                "client_id":     clientID,
                "code":          code,
                "grant_type":    "authorization_code",
                "redirect_uri":  self.callbackURL,
                "code_verifier": verifier,
            ],
            baseURL: baseURL
        )
    }

    // MARK: - Token Refresh

    /// Exchanges a refresh token for a new pair of tokens.
    func refresh(refreshToken: String,
                 baseURL: String,
                 clientID: String) async throws -> OAuthTokens {
        try await exchange(
            params: [
                "client_id":     clientID,
                "refresh_token": refreshToken,
                "grant_type":    "refresh_token",
                "redirect_uri":  callbackURL,
            ],
            baseURL: baseURL
        )
    }

    // MARK: - PKCE helpers

    private func makePKCE() -> (verifier: String, challenge: String) {
        // RFC 7636 §4.1 — verifier is 43–128 unreserved characters.
        // 32 random bytes → 43-char base64url string, well within spec.
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier  = Data(bytes).base64URLEncoded
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        return (verifier, challenge)
    }

    private func buildAuthorizationURL(baseURL: String,
                                       clientID: String,
                                       challenge: String,
                                       state: String) -> URL {
        var comps = URLComponents(string: "\(baseURL)/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id",             value: clientID),
            URLQueryItem(name: "redirect_uri",          value: callbackURL),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "api read_user"),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return comps.url!
    }

    private func extractCode(from url: URL) throws -> String {
        guard
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code  = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw OAuthError.noAuthCode }
        return code
    }

    // MARK: - Token endpoint (shared by auth + refresh)

    /// Posts form-encoded params to `/oauth/token` and decodes the response.
    /// GitLab uses Doorkeeper which strictly requires application/x-www-form-urlencoded.
    private func exchange(params: [String: String], baseURL: String) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: "\(baseURL)/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formComponents        = URLComponents()
        formComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody              = formComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed(msg)
        }

        struct TokenResponse: Decodable {
            let accessToken:  String
            let refreshToken: String?
            let expiresIn:    Int
            enum CodingKeys: String, CodingKey {
                case accessToken  = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn    = "expires_in"
            }
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken:  decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresIn:    decoded.expiresIn
        )
    }
}

// MARK: - Presentation context

extension OAuthService: @preconcurrency ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Data + Base64URL

private extension Data {
    /// Base64URL encoding (RFC 4648 §5) without padding characters.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
