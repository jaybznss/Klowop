import SwiftUI
import SwiftData

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Categories seen in transactions, offered as suggestions.
    let existingCategories: [String]

    @Query private var budgets: [Budget]
    @State private var category = ""
    @State private var limit = ""

    private var trimmedCategory: String {
        category.trimmingCharacters(in: .whitespaces)
    }
    private var isDuplicate: Bool {
        budgets.contains { $0.category.lowercased() == trimmedCategory.lowercased() }
    }
    private var isValid: Bool {
        !trimmedCategory.isEmpty && (Double(limit) ?? 0) > 0 && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category (e.g. Food And Drink)", text: $category)
                    LabeledContent("Monthly limit") {
                        TextField("0.00", text: $limit)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if isDuplicate {
                        Text("You already have a budget for \(trimmedCategory).")
                            .foregroundStyle(.red)
                    }
                }
                if !existingCategories.isEmpty {
                    Section("Your categories") {
                        ForEach(existingCategories, id: \.self) { suggestion in
                            Button(suggestion) { category = suggestion }
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(Budget(category: trimmedCategory,
                                              monthlyLimit: Double(limit) ?? 0))
                        try? context.save()
                        dismiss()
                    }
                    // Requires a positive limit and no duplicate category —
                    // a $0 budget reads as permanently "over".
                    .disabled(!isValid)
                }
            }
        }
    }
}
