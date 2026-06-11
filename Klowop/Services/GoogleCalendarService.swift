import Foundation
import AuthenticationServices
import CryptoKit
import SwiftData
import Observation
import UIKit

/// Google Calendar integration: OAuth 2.0 with PKCE (no client secret needed for iOS apps)
/// and two-way sync against the primary calendar.
@Observable
final class GoogleCalendarService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleCalendarService()

    var isConnected: Bool
    var isSyncing = false
    var lastSyncDate: Date?
    var lastError: String?

    private var authSession: ASWebAuthenticationSession?
    private let iso = AssistantTools.isoFormatter

    private override init() {
        isConnected = KeychainHelper.get("google_refresh_token") != nil
        super.init()
    }

    enum GoogleError: LocalizedError {
        case missingClientID, authFailed(String), api(String)
        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Add your Google OAuth client ID in Settings first."
            case .authFailed(let m): return "Google sign-in failed: \(m)"
            case .api(let m): return "Google Calendar error: \(m)"
            }
        }
    }

    private var clientID: String { AppSettings.shared.googleClientID }

    /// iOS OAuth clients use the reversed client ID as redirect scheme.
    private var redirectScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    private var redirectURI: String { redirectScheme + ":/oauthredirect" }

    // MARK: - Connect (OAuth + PKCE)

    @MainActor
    func connect() async throws {
        guard !clientID.isEmpty else { throw GoogleError.missingClientID }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.base64URL(SHA256.hash(data: Data(verifier.utf8)))

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/calendar"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: GoogleError.authFailed(error?.localizedDescription ?? "cancelled")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleError.authFailed("no authorization code returned")
        }

        let tokens = try await tokenRequest(parameters: [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        storeTokens(tokens)
        isConnected = true
    }

    func disconnect() {
        KeychainHelper.delete("google_access_token")
        KeychainHelper.delete("google_refresh_token")
        UserDefaults.standard.removeObject(forKey: "google_token_expiry")
        isConnected = false
    }

    // MARK: - Tokens

    private func storeTokens(_ tokens: [String: Any]) {
        if let access = tokens["access_token"] as? String {
            KeychainHelper.set(access, for: "google_access_token")
        }
        if let refresh = tokens["refresh_token"] as? String {
            KeychainHelper.set(refresh, for: "google_refresh_token")
        }
        let expiresIn = (tokens["expires_in"] as? Double) ?? 3600
        UserDefaults.standard.set(Date.now.addingTimeInterval(expiresIn - 60).timeIntervalSince1970,
                                  forKey: "google_token_expiry")
    }

    private func validAccessToken() async throws -> String {
        let expiry = UserDefaults.standard.double(forKey: "google_token_expiry")
        if let token = KeychainHelper.get("google_access_token"),
           Date.now.timeIntervalSince1970 < expiry {
            return token
        }
        guard let refresh = KeychainHelper.get("google_refresh_token") else {
            throw GoogleError.authFailed("not connected")
        }
        let tokens = try await tokenRequest(parameters: [
            "refresh_token": refresh,
            "client_id": clientID,
            "grant_type": "refresh_token",
        ])
        storeTokens(tokens)
        guard let token = tokens["access_token"] as? String else {
            throw GoogleError.authFailed("token refresh failed")
        }
        return token
    }

    private func tokenRequest(parameters: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleError.api("bad token response")
        }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            throw GoogleError.api((json["error_description"] as? String) ?? (json["error"] as? String) ?? "token error")
        }
        return json
    }

    // MARK: - Two-way sync

    /// Pushes local changes to Google, then pulls remote events for a -30d..+365d window.
    @MainActor
    func sync(context: ModelContext) async {
        guard isConnected else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            try await pushLocalChanges(context: context)
            try await pullRemoteEvents(context: context)
            lastSyncDate = .now
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func pushLocalChanges(context: ModelContext) async throws {
        let pending = try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.needsGoogleSync }))
        for event in pending {
            let body: [String: Any] = [
                "summary": event.title,
                "location": event.location ?? "",
                "description": event.notes ?? "",
                "start": ["dateTime": iso.string(from: event.startDate)],
                "end": ["dateTime": iso.string(from: event.endDate)],
            ]
            if let googleID = event.googleEventID {
                _ = try await calendarRequest("PATCH", path: "events/\(googleID)", body: body)
            } else {
                let created = try await calendarRequest("POST", path: "events", body: body)
                event.googleEventID = created["id"] as? String
            }
            event.needsGoogleSync = false
        }
    }

    @MainActor
    private func pullRemoteEvents(context: ModelContext) async throws {
        let timeMin = iso.string(from: Calendar.current.date(byAdding: .day, value: -30, to: .now)!)
        let timeMax = iso.string(from: Calendar.current.date(byAdding: .year, value: 1, to: .now)!)
        let query = "events?singleEvents=true&maxResults=2500&orderBy=startTime&timeMin=\(timeMin)&timeMax=\(timeMax)"
        let result = try await calendarRequest("GET", path: query)
        let items = result["items"] as? [[String: Any]] ?? []

        let synced = try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.googleEventID != nil }))
        var byGoogleID: [String: CalendarEvent] = [:]
        for event in synced { if let id = event.googleEventID { byGoogleID[id] = event } }

        for item in items {
            guard let id = item["id"] as? String,
                  (item["status"] as? String) != "cancelled",
                  let start = parseGoogleDate(item["start"]),
                  let end = parseGoogleDate(item["end"]) else { continue }
            let title = (item["summary"] as? String) ?? "(no title)"
            if let existing = byGoogleID[id] {
                // Remote wins for events we didn't change locally.
                if !existing.needsGoogleSync {
                    existing.title = title
                    existing.startDate = start
                    existing.endDate = end
                    existing.location = item["location"] as? String
                    existing.notes = item["description"] as? String
                }
            } else {
                context.insert(CalendarEvent(title: title, startDate: start, endDate: end,
                                             location: item["location"] as? String,
                                             notes: item["description"] as? String,
                                             googleEventID: id, needsGoogleSync: false))
            }
        }
    }

    private func parseGoogleDate(_ value: Any?) -> Date? {
        guard let dict = value as? [String: Any] else { return nil }
        if let dateTime = dict["dateTime"] as? String { return iso.date(from: dateTime) }
        if let date = dict["date"] as? String {
            // All-day event
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            return formatter.date(from: date)
        }
        return nil
    }

    private func calendarRequest(_ method: String, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let token = try await validAccessToken()
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "request failed"
            throw GoogleError.api(message)
        }
        return json
    }

    // MARK: - Helpers

    private static func randomURLSafeString(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func base64URL(_ digest: SHA256.Digest) -> String {
        Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Sign-in is always triggered from the foreground UI, so a window scene exists.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        return scene.keyWindow ?? ASPresentationAnchor(windowScene: scene)
    }
}
