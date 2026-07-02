import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.nextRenewal) private var subscriptions: [Subscription]
    @State private var showingEditor = false

    private var active: [Subscription] { subscriptions.filter(\.isActive) }
    private var monthlyTotal: Double { active.reduce(0) { $0 + $1.monthlyEquivalent } }

    var body: some View {
        List {
            // One empty state, not a "$0.00 across 0 subscriptions" header
            // stacked on an empty section stacked on a placeholder.
            if active.isEmpty {
                ContentUnavailableView("No subscriptions tracked",
                                       systemImage: "repeat.circle",
                                       description: Text("They're detected automatically from linked banks, or add one with +."))
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monthlyTotal.asCurrency())
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text("per month across \(active.count) subscriptions (\((monthlyTotal * 12).asCurrency())/year)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }
                Section("Upcoming renewals") {
                    ForEach(active) { sub in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(sub.name).font(.subheadline.weight(.medium))
                                Text(renewalText(sub))
                                    .font(.caption)
                                    .foregroundStyle(renewalColor(sub))
                            }
                            Spacer()
                            Text(sub.amount.asCurrency())
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions {
                            Button("Mark Cancelled") {
                                sub.isActive = false
                                try? context.save()
                            }
                            .tint(.orange)
                            Button(role: .destructive) {
                                context.delete(sub)
                                try? context.save()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add subscription")
            }
        }
        .sheet(isPresented: $showingEditor) { SubscriptionEditorView() }
    }

    private func renewalText(_ sub: Subscription) -> String {
        let cycle = sub.billingCycle.capitalized
        if sub.nextRenewal < .now {
            return "Renewal overdue · \(sub.nextRenewal.dayLabel) · \(cycle)"
        }
        return "Renews \(sub.nextRenewal.dayLabel) · \(cycle)"
    }

    private func renewalColor(_ sub: Subscription) -> Color {
        if sub.nextRenewal < .now { return .red }
        if sub.nextRenewal < Calendar.current.date(byAdding: .day, value: 7, to: .now)! {
            return .orange
        }
        return .secondary
    }
}

struct SubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var amount = ""
    @State private var cycle = "monthly"
    @State private var nextRenewal = Date.now

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Netflix)", text: $name)
                LabeledContent("Amount") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Billing cycle", selection: $cycle) {
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                    Text("Yearly").tag("yearly")
                }
                DatePicker("Next renewal", selection: $nextRenewal, displayedComponents: .date)
            }
            .navigationTitle("New Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(Subscription(name: name, amount: Double(amount) ?? 0,
                                                    billingCycle: cycle, nextRenewal: nextRenewal))
                        try? context.save()
                        dismiss()
                    }
                    // A $0 subscription is always a typo.
                    .disabled(name.isEmpty || (Double(amount) ?? 0) <= 0)
                }
            }
        }
    }
}
