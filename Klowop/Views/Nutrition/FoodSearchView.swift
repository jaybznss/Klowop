import SwiftUI
import SwiftData
import VisionKit

/// Food logging flow: search the Open Food Facts database (or scan a barcode),
/// pick a product, set the portion, save. Manual entry remains as a fallback.
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let day: Date

    @State private var query = ""
    @State private var results: [FoodDatabaseService.FoodItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedItem: FoodDatabaseService.FoodItem?
    @State private var showingScanner = false
    @State private var showingManualEntry = false
    @State private var isLookingUpBarcode = false

    var body: some View {
        NavigationStack {
            List {
                if isSearching || isLookingUpBarcode {
                    HStack {
                        ProgressView()
                        Text(isLookingUpBarcode ? "Looking up product…" : "Searching the food database…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                if results.isEmpty && !isSearching && query.isEmpty {
                    introSection
                }
                ForEach(results) { item in
                    Button { selectedItem = item } label: { resultRow(item) }
                        .buttonStyle(.plain)
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search foods, e.g. greek yogurt")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if DataScannerViewController.isSupported {
                        Button { showingScanner = true } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                    }
                    Button { showingManualEntry = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("Enter manually")
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                PortionView(item: item, day: day) { dismiss() }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                BarcodeScannerSheet { code in
                    showingScanner = false
                    Task { await lookupBarcode(code) }
                }
            }
            .sheet(isPresented: $showingManualEntry, onDismiss: { dismiss() }) {
                MealEditorView(day: day)
            }
        }
    }

    private var introSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.nutrition)
            Text("Real nutrition data")
                .font(.headline)
            Text("Search millions of foods from the Open Food Facts database, or scan a product's barcode. Portions are scaled from verified per-100g values.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
    }

    private func resultRow(_ item: FoodDatabaseService.FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    if let brand = item.brand {
                        Text(brand).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.source)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (item.source == "USDA" ? Color.blue : Theme.nutrition).opacity(0.12),
                            in: .capsule)
                        .foregroundStyle(item.source == "USDA" ? Color.blue : Theme.nutrition)
                    if let serving = item.servingDescription {
                        Text("serving \(serving)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(Int(item.caloriesPer100g))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("kcal/100g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await FoodDatabaseService.search(trimmed)
            if results.isEmpty { errorMessage = "No matches — try a simpler name, or enter it manually." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func lookupBarcode(_ code: String) async {
        isLookingUpBarcode = true
        errorMessage = nil
        defer { isLookingUpBarcode = false }
        do {
            selectedItem = try await FoodDatabaseService.product(barcode: code)
        } catch {
            errorMessage = "Barcode \(code): \(error.localizedDescription)"
        }
    }
}

// MARK: - Portion picker

struct PortionView: View {
    @Environment(\.modelContext) private var context

    let item: FoodDatabaseService.FoodItem
    let day: Date
    let onDone: () -> Void

    @State private var grams: Double
    @State private var mealType: String

    init(item: FoodDatabaseService.FoodItem, day: Date, onDone: @escaping () -> Void) {
        self.item = item
        self.day = day
        self.onDone = onDone
        _grams = State(initialValue: item.servingGrams ?? 100)
        let hour = Calendar.current.component(.hour, from: .now)
        _mealType = State(initialValue: hour < 11 ? "breakfast" : hour < 15 ? "lunch" : hour < 21 ? "dinner" : "snack")
    }

    private var factor: Double { grams / 100 }
    private var calories: Int { Int(item.caloriesPer100g * factor) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline)
                    if let brand = item.brand {
                        Text(brand).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Portion") {
                HStack {
                    Slider(value: $grams, in: 5...500, step: 5)
                    Text("\(Int(grams)) g")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    portionChip("50 g", 50)
                    portionChip("100 g", 100)
                    portionChip("150 g", 150)
                    if let serving = item.servingGrams {
                        portionChip("1 serving", serving)
                    }
                }
                Picker("Meal", selection: $mealType) {
                    Text("Breakfast").tag("breakfast")
                    Text("Lunch").tag("lunch")
                    Text("Dinner").tag("dinner")
                    Text("Snack").tag("snack")
                }
            }
            Section("This portion") {
                LabeledContent("Calories", value: "\(calories) kcal")
                LabeledContent("Protein", value: String(format: "%.1f g", item.proteinPer100g * factor))
                LabeledContent("Carbs", value: String(format: "%.1f g", item.carbsPer100g * factor))
                LabeledContent("Fat", value: String(format: "%.1f g", item.fatPer100g * factor))
            }
        }
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") { save() }
            }
        }
    }

    private func portionChip(_ label: String, _ value: Double) -> some View {
        Button(label) { withAnimation(.snappy) { grams = value } }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.nutrition)
    }

    private func save() {
        let date = Calendar.current.isDateInToday(day) ? Date.now
            : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let meal = Meal(name: item.name,
                        mealType: mealType,
                        calories: calories,
                        protein: item.proteinPer100g * factor,
                        carbs: item.carbsPer100g * factor,
                        fat: item.fatPer100g * factor,
                        date: date,
                        notes: item.brand)
        context.insert(meal)
        try? context.save()
        Task { @MainActor in
            meal.healthKitUUID = await HealthKitService.shared.logMeal(
                name: meal.name, calories: meal.calories, protein: meal.protein,
                carbs: meal.carbs, fat: meal.fat, date: meal.date)
            try? context.save()
        }
        onDone()
    }
}

// MARK: - Barcode scanner

private struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            BarcodeScannerView(onScan: onScan)
                .ignoresSafeArea()
                .navigationTitle("Scan a barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .fast,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var hasFired = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasFired else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    hasFired = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}
