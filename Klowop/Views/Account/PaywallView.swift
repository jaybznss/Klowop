import SwiftUI
import StoreKit

/// Klowop Pro paywall — unlocks the AI assistant and automatic bank-linking.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitService.shared
    @State private var selected: Product?
    @State private var loadAttempted = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var privacyURL: URL {
        URL(string: AppSettings.shared.backendURL + "/privacy")!
    }
    /// Apple's standard EULA for apps that don't ship a custom one.
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private let perks: [(symbol: String, title: String, detail: String)] = [
        ("sparkles", "Your AI secretary", "Schedule, log, and ask about your life by talking."),
        ("building.columns.fill", "Automatic bank-linking", "Balances, transactions, and subscriptions, synced."),
        ("sun.max.fill", "Daily briefings", "A morning summary written just for you."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    perksList
                    plans
                    footer
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(AuroraBackground(colors: [.indigo, Theme.assistant, .blue]))
            .navigationTitle("Klowop Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Button("Restore") { restore() }
                            .font(.subheadline)
                    }
                }
            }
            .onChange(of: store.isSubscribed) { _, subscribed in
                if subscribed { dismiss() }
            }
            .sensoryFeedback(.success, trigger: store.isSubscribed) { _, new in new }
            .alert("Restore Purchases", isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
            .task {
                if store.products.isEmpty { await store.loadProducts() }
                loadAttempted = true
                if selected == nil {
                    selected = store.products.first { $0.id == StoreKitService.yearlyID }
                        ?? store.products.first
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Theme.assistantGradient)
                .padding(.top, 8)
            Text("Unlock everything")
                .font(.title.weight(.bold))
            Text("Tracking, calendar, and manual entry are always free. Pro adds the assistant and automatic bank-linking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var perksList: some View {
        VStack(spacing: 14) {
            ForEach(perks, id: \.title) { perk in
                HStack(spacing: 14) {
                    Image(systemName: perk.symbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.assistantGradient, in: .rect(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(perk.title).font(.subheadline.weight(.semibold))
                        Text(perk.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var plans: some View {
        VStack(spacing: 10) {
            if store.products.isEmpty {
                if loadAttempted {
                    // Load failed or returned nothing — never strand the user
                    // on an infinite spinner.
                    VStack(spacing: 8) {
                        Text("Couldn't load subscription plans.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Try again") {
                            Task {
                                await store.loadProducts()
                                selected = store.products.first { $0.id == StoreKitService.yearlyID }
                                    ?? store.products.first
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.assistant)
                    }
                    .padding()
                } else {
                    ProgressView().padding()
                }
            }
            ForEach(store.products) { product in
                planRow(product)
            }
        }
    }

    /// The yearly plan expressed per month ("$3.33/mo") plus the saving vs
    /// paying monthly — so the value claim is visible, not homework.
    private func yearlyDetail(_ product: Product) -> String {
        let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
        var text = "\(perMonth)/mo, billed yearly"
        if let monthly = store.products.first(where: { $0.id == StoreKitService.monthlyID }),
           monthly.price > 0 {
            let saving = (1 - product.price / (monthly.price * 12)) * 100
            let rounded = Int((saving as NSDecimalNumber).doubleValue.rounded())
            if rounded > 0 { text += " · save \(rounded)%" }
        }
        return text
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = selected?.id == product.id
        let isYearly = product.id == StoreKitService.yearlyID
        return Button {
            selected = product
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isYearly ? "Yearly" : "Monthly").font(.headline)
                        if isYearly {
                            Text("BEST VALUE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.assistant.opacity(0.15), in: .capsule)
                                .foregroundStyle(Theme.assistant)
                        }
                    }
                    if isYearly {
                        Text(yearlyDetail(product))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let offer = product.subscription?.introductoryOffer {
                        // Disclose the post-trial price next to the trial offer.
                        Text("\(trialText(offer)) trial, then \(product.displayPrice)/mo")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(product.displayPrice).font(.headline).monospacedDigit()
            }
            .padding(16)
            .background(
                isSelected ? AnyShapeStyle(Theme.assistant.opacity(0.12))
                           : AnyShapeStyle(.background.secondary),
                in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.assistant : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func restore() {
        isRestoring = true
        Task { @MainActor in
            await store.restore()
            isRestoring = false
            restoreMessage = store.isSubscribed
                ? "Your Klowop Pro subscription is active."
                : "No active subscription found for this Apple ID."
        }
    }

    private func trialText(_ offer: Product.SubscriptionOffer) -> String {
        let unit: String
        switch offer.period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        let count = offer.period.value
        return "\(count) \(unit)\(count > 1 ? "s" : "") free"
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                if let product = selected { Task { await store.purchase(product) } }
            } label: {
                Group {
                    if store.isPurchasing { ProgressView().tint(.white) }
                    else { Text(selected?.subscription?.introductoryOffer != nil ? "Start free trial" : "Subscribe") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Theme.assistant)
            .disabled(selected == nil || store.isPurchasing)

            if let error = store.purchaseError {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Text("Cancel anytime in Settings. Payment is charged to your Apple ID; subscriptions renew automatically unless cancelled at least 24 hours before the period ends.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            // App Review requires tappable Privacy Policy and Terms links on paywalls.
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: privacyURL)
                Link("Terms of Use", destination: termsURL)
            }
            .font(.caption2)
        }
    }
}
