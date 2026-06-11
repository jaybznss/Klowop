import Foundation
import SwiftData
import Observation
import UIKit
#if canImport(LinkKit)
import LinkKit
#endif

/// Bank linking via Plaid. The Plaid secret never lives in the app — the companion
/// server (see server/ in the repo) creates link tokens and exchanges public tokens.
@Observable
final class PlaidService {
    static let shared = PlaidService()

    var isBusy = false
    var statusMessage: String?
    var lastError: String?

    #if canImport(LinkKit)
    private var linkHandler: Handler?
    #endif

    private init() {}

    enum PlaidError: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self { case .server(let m): return "Plaid server: \(m)" }
        }
    }

    private var serverURL: String { AppSettings.shared.plaidServerURL }

    // MARK: - Link flow

    @MainActor
    func startLinkFlow(context: ModelContext) async {
        lastError = nil
        do {
            let response = try await post("/api/create_link_token", body: [:])
            guard let linkToken = response["link_token"] as? String else {
                throw PlaidError.server("no link_token in response")
            }
            try presentLink(token: linkToken, context: context)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func presentLink(token: String, context: ModelContext) throws {
        #if canImport(LinkKit)
        var configuration = LinkTokenConfiguration(token: token) { [weak self] success in
            Task { @MainActor in
                await self?.exchange(publicToken: success.publicToken, context: context)
            }
        }
        configuration.onExit = { [weak self] exit in
            if let error = exit.error { self?.lastError = error.localizedDescription }
        }
        switch Plaid.create(configuration) {
        case .success(let handler):
            linkHandler = handler
            guard let root = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?
                .keyWindow?.rootViewController else { return }
            handler.open(presentUsing: .viewController(root))
        case .failure(let error):
            lastError = error.localizedDescription
        }
        #else
        lastError = "LinkKit is not available. Add the plaid-link-ios Swift package (see SETUP.md)."
        #endif
    }

    @MainActor
    private func exchange(publicToken: String, context: ModelContext) async {
        do {
            _ = try await post("/api/exchange_public_token", body: ["public_token": publicToken])
            statusMessage = "Bank linked. Fetching data…"
            try await refreshData(context: context)
        } catch {
            lastError = error.localizedDescription
        }
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
        let response = try await get("/api/accounts")
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
        let response = try await get("/api/transactions")
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
        let response = try await get("/api/recurring")
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

    // MARK: - HTTP

    private func get(_ path: String) async throws -> [String: Any] {
        try await request("GET", path: path, body: nil)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await request("POST", path: path, body: body)
    }

    private func request(_ method: String, path: String, body: [String: Any]?) async throws -> [String: Any] {
        guard let url = URL(string: serverURL + path) else {
            throw PlaidError.server("invalid server URL — set it in Settings")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PlaidError.server((json["error"] as? String) ?? "request to \(path) failed")
        }
        return json
    }
}
