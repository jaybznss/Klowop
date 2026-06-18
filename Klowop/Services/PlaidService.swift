import Foundation
import SwiftData
import Observation
import UIKit

/// Bank linking via Plaid **Hosted Link** — the linking UI runs in the browser,
/// so the app carries no native Plaid binary. The companion server (server/ in
/// the repo) holds the Plaid secret, creates hosted link sessions, and exchanges
/// tokens.
///
/// Flow: ask the server for a hosted link URL → open it in the browser → the user
/// links their bank there → back in the app, we ask the server to complete the
/// session (it fetches the public token and exchanges it) → data syncs.
@Observable
final class PlaidService {
    static let shared = PlaidService()

    var isBusy = false
    var statusMessage: String?
    var lastError: String?
    /// Set when a premium action is blocked; the Money view reacts by prompting.
    var requiresSignIn = false
    var requiresSubscription = false

    /// Set while a hosted link session is awaiting completion in the browser.
    var pendingLinkToken: String? {
        didSet { UserDefaults.standard.set(pendingLinkToken, forKey: "plaid_pending_link_token") }
    }

    private init() {
        pendingLinkToken = UserDefaults.standard.string(forKey: "plaid_pending_link_token")
    }

    enum PlaidError: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self { case .server(let m): return "Plaid server: \(m)" }
        }
    }

    private var serverURL: String { AppSettings.shared.plaidServerURL }

    // MARK: - Hosted Link flow

    /// Starts a hosted link session and opens it in the browser.
    @MainActor
    func startLinkFlow(context: ModelContext) async {
        lastError = nil
        requiresSignIn = false
        requiresSubscription = false
        guard BackendService.shared.isSignedIn else { requiresSignIn = true; return }
        do {
            let response = try await post("/api/plaid/create_link_token", body: [:])
            guard let linkToken = response["link_token"] as? String,
                  let urlString = response["hosted_link_url"] as? String,
                  let url = URL(string: urlString) else {
                throw PlaidError.server("no hosted link URL in response")
            }
            pendingLinkToken = linkToken
            statusMessage = "Finish linking your bank in the browser, then come back here."
            await UIApplication.shared.open(url)
        } catch let error as BackendService.BackendError {
            switch error {
            case .subscriptionRequired: requiresSubscription = true
            case .notSignedIn: requiresSignIn = true
            case .server(let message): lastError = message
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Called when the app comes back to the foreground (and on screen load):
    /// if a hosted link session is pending, ask the server whether it completed.
    @MainActor
    func completePendingLinkIfNeeded(context: ModelContext) async {
        guard let token = pendingLinkToken, !isBusy else { return }
        do {
            let response = try await post("/api/plaid/complete_hosted_link", body: ["link_token": token])
            if (response["linked"] as? Bool) == true {
                pendingLinkToken = nil
                statusMessage = "Bank linked. Fetching data…"
                try await refreshData(context: context)
            }
            // Not linked yet: the user may still be mid-flow in the browser — keep waiting.
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func cancelPendingLink() {
        pendingLinkToken = nil
        statusMessage = nil
    }

    // MARK: - Data refresh

    @MainActor
    func refreshData(context: ModelContext) async throws {
        isBusy = true
        defer { isBusy = false }
        try await syncAccounts(context: context)
        try await syncTransactions(context: context)
        try await syncSubscriptions(context: context)
        try context.save()
        statusMessage = "Up to date as of \(Date.now.formatted(date: .omitted, time: .shortened))"
    }

    @MainActor
    private func syncAccounts(context: ModelContext) async throws {
        let response = try await get("/api/plaid/accounts")
        let items = response["accounts"] as? [[String: Any]] ?? []
        let existing = try context.fetch(FetchDescriptor<FinancialAccount>(
            predicate: #Predicate { $0.plaidAccountID != nil }))
        var byID: [String: FinancialAccount] = [:]
        for account in existing { if let id = account.plaidAccountID { byID[id] = account } }

        for item in items {
            guard let id = item["id"] as? String else { continue }
            let balance = (item["balance"] as? Double) ?? 0
            if let account = byID[id] {
                account.balance = balance
            } else {
                context.insert(FinancialAccount(
                    name: (item["name"] as? String) ?? "Account",
                    institution: (item["institution"] as? String) ?? "Bank",
                    type: (item["type"] as? String) ?? "other",
                    balance: balance,
                    currencyCode: (item["currency"] as? String) ?? "USD",
                    plaidAccountID: id))
            }
        }
    }

    @MainActor
    private func syncTransactions(context: ModelContext) async throws {
        let response = try await get("/api/plaid/transactions")
        let items = response["transactions"] as? [[String: Any]] ?? []
        let existing = try context.fetch(FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.plaidTransactionID != nil }))
        let knownIDs = Set(existing.compactMap(\.plaidTransactionID))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for item in items {
            guard let id = item["id"] as? String, !knownIDs.contains(id) else { continue }
            context.insert(MoneyTransaction(
                merchant: (item["merchant"] as? String) ?? "Unknown",
                amount: (item["amount"] as? Double) ?? 0,
                date: formatter.date(from: (item["date"] as? String) ?? "") ?? .now,
                category: (item["category"] as? String) ?? "Other",
                accountName: (item["account_name"] as? String) ?? "",
                plaidTransactionID: id))
        }
    }

    @MainActor
    private func syncSubscriptions(context: ModelContext) async throws {
        let response = try await get("/api/plaid/recurring")
        let items = response["subscriptions"] as? [[String: Any]] ?? []
        let existing = try context.fetch(FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.plaidStreamID != nil }))
        var byID: [String: Subscription] = [:]
        for sub in existing { if let id = sub.plaidStreamID { byID[id] = sub } }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for item in items {
            guard let id = item["id"] as? String else { continue }
            let amount = (item["amount"] as? Double) ?? 0
            let next = formatter.date(from: (item["next_date"] as? String) ?? "") ?? .now
            if let sub = byID[id] {
                sub.amount = amount
                sub.nextRenewal = next
                sub.isActive = (item["active"] as? Bool) ?? true
            } else {
                context.insert(Subscription(
                    name: (item["name"] as? String) ?? "Subscription",
                    amount: amount,
                    billingCycle: (item["cycle"] as? String) ?? "monthly",
                    nextRenewal: next,
                    accountName: (item["account_name"] as? String) ?? "",
                    isActive: (item["active"] as? Bool) ?? true,
                    plaidStreamID: id))
            }
        }
    }

    // MARK: - HTTP (through the authenticated backend)

    private func get(_ path: String) async throws -> [String: Any] {
        try await BackendService.shared.request("GET", path: path)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await BackendService.shared.request("POST", path: path, body: body)
    }
}
