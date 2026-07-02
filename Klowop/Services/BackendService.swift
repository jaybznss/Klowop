import Foundation
import Observation

/// Talks to the Klowop backend. Holds the user's session token (from Sign in
/// with Apple), reports subscription state, and makes authenticated requests —
/// the app no longer holds any API keys itself.
@Observable
final class BackendService {
    static let shared = BackendService()

    private(set) var isSignedIn: Bool
    var subscriptionActive = false
    var userEmail: String?

    private var session: String? {
        didSet {
            if let session { KeychainHelper.set(session, for: "backend_session") }
            else { KeychainHelper.delete("backend_session") }
            isSignedIn = session != nil
        }
    }

    private var baseURL: String { AppSettings.shared.backendURL }

    enum BackendError: LocalizedError {
        case notSignedIn
        case subscriptionRequired
        case unreachable
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Please sign in to use the assistant."
            case .subscriptionRequired: return "This feature needs a Klowop subscription."
            case .unreachable: return "Can't reach the Klowop server. Check your connection and try again."
            case .server(let message): return message
            }
        }
    }

    /// The server no longer recognizes our session (expired, or the account
    /// was removed). Drop it locally so the UI shows sign-in states instead
    /// of a stale "Signed in" that errors on every action.
    @MainActor
    func handleUnauthorized() {
        signOut()
    }

    private init() {
        let saved = KeychainHelper.get("backend_session")
        session = saved
        isSignedIn = saved != nil
        userEmail = UserDefaults.standard.string(forKey: "backend_user_email")
    }

    // MARK: - Sign in with Apple

    @MainActor
    func signInWithApple(identityToken: String, email: String?) async throws {
        var request = URLRequest(url: URL(string: baseURL + "/auth/apple")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["identityToken": identityToken]
        if let email { payload["email"] = email }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["session"] as? String else {
            throw BackendError.server("Sign-in failed. Please try again.")
        }
        session = token
        subscriptionActive = (json["subscriptionActive"] as? Bool) ?? false
        if let email {
            userEmail = email
            UserDefaults.standard.set(email, forKey: "backend_user_email")
        }
    }

    func signOut() {
        session = nil
        subscriptionActive = false
        userEmail = nil
        UserDefaults.standard.removeObject(forKey: "backend_user_email")
    }

    // MARK: - Authenticated requests

    /// Opens an authenticated streaming request to the assistant endpoint. The
    /// caller parses the SSE body; status is returned so callers can handle
    /// 401 (re-auth) and 402 (subscription) distinctly.
    func assistantStream(body: [String: Any]) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        guard let session else { throw BackendError.notSignedIn }
        var request = URLRequest(url: URL(string: baseURL + "/api/assistant/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.server("No response from the server.")
        }
        return (bytes, http)
    }

    /// Authenticated JSON request (used by Plaid routing, account deletion, etc.).
    @discardableResult
    func request(_ method: String, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let session else { throw BackendError.notSignedIn }
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw urlError
        } catch is URLError {
            throw BackendError.unreachable
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.server("No response from the server.")
        }
        if http.statusCode == 402 { throw BackendError.subscriptionRequired }
        if http.statusCode == 401 {
            await handleUnauthorized()
            throw BackendError.notSignedIn
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server((json["error"] as? String) ?? "Request failed (\(http.statusCode)).")
        }
        return json
    }

    /// Permanently deletes the account and all server-side data.
    @MainActor
    func deleteAccount() async throws {
        _ = try await request("DELETE", path: "/api/account")
        signOut()
    }
}
