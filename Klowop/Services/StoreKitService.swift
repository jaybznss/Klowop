import Foundation
import StoreKit
import Observation

/// StoreKit 2 subscription handling. Loads the products, runs purchases, listens
/// for renewals/refunds, and forwards each signed transaction to the backend so
/// the server can gate premium features (AI + bank-linking) independently.
@Observable
final class StoreKitService {
    static let shared = StoreKitService()

    /// Product IDs — must match the subscription products created in App Store
    /// Connect (and the bundled Klowop.storekit file used for local testing).
    static let monthlyID = "com.jaybznss.Klowop.pro.monthly"
    static let yearlyID = "com.jaybznss.Klowop.pro.yearly"
    static let allIDs = [monthlyID, yearlyID]

    var products: [Product] = []
    var isSubscribed = false
    var purchaseError: String?
    var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in await self?.listenForTransactions() }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    @MainActor
    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await sendToBackend(jws: verification.jwsRepresentation)
                    await transaction.finish()
                    isSubscribed = true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    @MainActor
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    /// Recomputes whether the user currently holds an active entitlement.
    @MainActor
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.allIDs.contains(transaction.productID) {
                active = true
                await sendToBackend(jws: result.jwsRepresentation)
            }
        }
        isSubscribed = active
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await sendToBackend(jws: update.jwsRepresentation)
                await transaction.finish()
                await refreshEntitlement()
            }
        }
    }

    /// Records the entitlement on the backend (which gates the AI + Plaid APIs).
    private func sendToBackend(jws: String) async {
        guard BackendService.shared.isSignedIn else { return }
        do {
            _ = try await BackendService.shared.request(
                "POST", path: "/api/subscription/verify", body: ["signedTransaction": jws])
            await MainActor.run { BackendService.shared.subscriptionActive = true }
        } catch {
            // Backend may be unreachable; local entitlement still governs the UI.
        }
    }
}
