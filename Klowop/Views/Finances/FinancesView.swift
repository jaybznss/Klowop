import SwiftUI
import SwiftData
import Charts

struct FinancesView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [FinancialAccount]
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @Query(filter: #Predicate<Subscription> { $0.isActive }) private var subscriptions: [Subscription]
    @Query(sort: \Budget.category) private var budgets: [Budget]
    @State private var plaid = PlaidService.shared
    @State private var showingBudgetEditor = false
    @State private var showingSignIn = false
    @State private var showingPaywall = false
    @Environment(\.scenePhase) private var scenePhase

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
                    if isEmptyState {
                        moneyEmptyCard
                        subscriptionsTeaser
                        budgetsCard
                    } else {
                        netWorthCard
                        if !transactions.isEmpty { spendingChartCard }
                        budgetsCard
                        accountsCard
                        subscriptionsTeaser
                        transactionsCard
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Money")
            .background(AuroraBackground(colors: [.indigo, .blue, .purple]))
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
            .task { await plaid.completePendingLinkIfNeeded(context: context) }
            .onChange(of: scenePhase) { _, phase in
                // Returning from the browser after a hosted Plaid Link session.
                if phase == .active {
                    Task { await plaid.completePendingLinkIfNeeded(context: context) }
                }
            }
            .onChange(of: plaid.requiresSignIn) { _, needs in
                if needs { showingSignIn = true; plaid.requiresSignIn = false }
            }
            .onChange(of: plaid.requiresSubscription) { _, needs in
                if needs { showingPaywall = true; plaid.requiresSubscription = false }
            }
            .sheet(isPresented: $showingSignIn) { signInSheet }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private var signInSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.financeGradient)
                Text("Sign in to link your bank")
                    .font(.title2.weight(.bold))
                Text("Bank-linking is part of Klowop Pro and needs an account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                AppleSignInButton { showingSignIn = false }
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSignIn = false }
                }
            }
        }
    }

    private var isEmptyState: Bool { accounts.isEmpty && transactions.isEmpty }

    private var moneyEmptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.finance)
                .padding(.top, 8)
            Text("Connect your money")
                .font(.title3.weight(.semibold))
            Text("Link your banks to see balances, transactions, and subscriptions across all your accounts — and let your assistant answer money questions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = plaid.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            linkControls
        }
        .frame(maxWidth: .infinity)
        .heroCard(Theme.finance)
        .glow(Theme.finance)
    }

    private var netWorthCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Net balance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(netWorth.asCurrency())
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: netWorth))
                .animation(.smooth, value: netWorth)
            if let status = plaid.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            if let error = plaid.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            linkControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var linkControls: some View {
        if plaid.pendingLinkToken != nil {
            HStack {
                ProgressView()
                Text("Waiting for you to finish linking in the browser…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { plaid.cancelPendingLink() }
                    .font(.caption)
            }
            .padding(.top, 6)
        } else {
            Button {
                Task { await plaid.startLinkFlow(context: context) }
            } label: {
                Label(accounts.isEmpty ? "Link a bank account" : "Link another account",
                      systemImage: "building.columns")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.finance)
            .padding(.top, 6)
        }
    }

    // MARK: - Spending chart

    private struct DaySpend: Identifiable {
        let id: Date
        let day: Date
        let amount: Double
    }

    private var spendingByDay: [DaySpend] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<30).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: day)!
            let total = transactions
                .filter { $0.date >= day && $0.date < end && $0.amount > 0 }
                .reduce(0) { $0 + $1.amount }
            return DaySpend(id: day, day: day, amount: total)
        }
    }

    private var spendingChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Spending · last 30 days", symbol: "chart.bar.fill", gradient: Theme.financeGradient)
            Chart(spendingByDay) { entry in
                BarMark(
                    x: .value("Day", entry.day, unit: .day),
                    y: .value("Spent", entry.amount)
                )
                .foregroundStyle(Theme.financeGradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Budgets

    /// Spending in the current calendar month for a budget's category.
    private func monthSpent(for category: String) -> Double {
        guard let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start else { return 0 }
        return transactions
            .filter { $0.date >= monthStart && $0.amount > 0 && $0.category.lowercased() == category.lowercased() }
            .reduce(0) { $0 + $1.amount }
    }

    private var budgetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Budgets · this month", symbol: "gauge.with.needle", gradient: Theme.budgetGradient)
                Button { showingBudgetEditor = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.orange)
                }
            }
            if budgets.isEmpty {
                Text("Set monthly limits per category — or just tell the assistant \"set a $300 restaurants budget\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(budgets) { budget in
                let spent = monthSpent(for: budget.category)
                let fraction = spent / max(budget.monthlyLimit, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(budget.category).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(spent.asCurrency()) of \(budget.monthlyLimit.asCurrency())")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(fraction >= 1 ? .red : .secondary)
                    }
                    ProgressView(value: min(1, fraction))
                        .tint(fraction >= 1 ? .red : fraction >= 0.8 ? .orange : .green)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(budget)
                        try? context.save()
                    } label: { Label("Delete budget", systemImage: "trash") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $showingBudgetEditor) {
            BudgetEditorView(existingCategories: Array(Set(transactions.map(\.category))).sorted())
        }
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Accounts", symbol: "building.columns.fill", gradient: Theme.financeGradient)
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
                CardHeader(title: "Subscriptions", symbol: "repeat", gradient: Theme.assistantGradient)
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
            CardHeader(title: "Recent activity", symbol: "list.bullet", gradient: Theme.financeGradient)
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
