import SwiftUI
import SwiftData

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Categories seen in transactions, offered as suggestions.
    let existingCategories: [String]

    @State private var category = ""
    @State private var limit = ""

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
                        context.insert(Budget(category: category.trimmingCharacters(in: .whitespaces),
                                              monthlyLimit: Double(limit) ?? 0))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(category.trimmingCharacters(in: .whitespaces).isEmpty || Double(limit) == nil)
                }
            }
        }
    }
}
