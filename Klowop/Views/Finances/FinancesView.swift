import SwiftUI
import SwiftData

struct FinancesView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [FinancialAccount]
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @Query(filter: #Predicate<Subscription> { $0.isActive }) private var subscriptions: [Subscription]
    @State private var plaid = PlaidService.shared

    private var netWorth: Double {
        accounts.reduce(0) { $0 + ($1.type == "credit" ? -$1.balance : $1.balance) }
    }
    private var monthlySubscriptionCost: Double {
        subscriptions.reduce(0) { $0 + $1.monthlyEquivalent }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    netWorthCard
                    accountsCard
                    subscriptionsTeaser
                    transactionsCard
                }
                .padding(.horizontal)
            }
            .navigationTitle("Money")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { try? await plaid.refreshData(context: context) }
                    } label: {
                        if plaid.isBusy { ProgressView() }
                        else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .disabled(plaid.isBusy || accounts.allSatisfy { $0.plaidAccountID == nil })
                }
            }
        }
    }

    private var netWorthCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Net balance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(netWorth.asCurrency())
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let status = plaid.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            if let error = plaid.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button {
                Task { await plaid.startLinkFlow(context: context) }
            } label: {
                Label(accounts.isEmpty ? "Link a bank account" : "Link another account",
                      systemImage: "building.columns")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.finance)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accounts", systemImage: "building.columns.fill")
                .font(.headline)
                .foregroundStyle(Theme.finance)
            if accounts.isEmpty {
                Text("No accounts yet. Link your bank above — balances and transactions sync automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts) { account in
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.name).font(.subheadline.weight(.medium))
                        Text("\(account.institution) · \(account.type.capitalized)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(account.balance.asCurrency(account.currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(account.type == "credit" ? .red : .primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var subscriptionsTeaser: some View {
        NavigationLink {
            SubscriptionsView()
        } label: {
            HStack {
                Label("Subscriptions", systemImage: "repeat.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.assistant)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(monthlySubscriptionCost.asCurrency() + "/mo")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("\(subscriptions.count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var transactionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent activity", systemImage: "list.bullet")
                .font(.headline)
            if transactions.isEmpty {
                Text("Transactions appear here after you link a bank.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(transactions.prefix(20)) { tx in
                HStack {
                    VStack(alignment: .leading) {
                        Text(tx.merchant).font(.subheadline.weight(.medium))
                        Text("\(tx.date.formatted(date: .abbreviated, time: .omitted)) · \(tx.category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((tx.amount > 0 ? "−" : "+") + abs(tx.amount).asCurrency())
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tx.amount > 0 ? .primary : Color.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
