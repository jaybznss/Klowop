import SwiftUI
import SwiftData

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showingEditor = false
    @State private var settings = AppSettings.shared
    @Query(sort: \Meal.date) private var allMeals: [Meal]

    private var dayMeals: [Meal] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay)!
        return allMeals.filter { $0.date >= selectedDay && $0.date < end }
    }

    private var calories: Int { dayMeals.reduce(0) { $0 + $1.calories } }
    private var protein: Double { dayMeals.reduce(0) { $0 + $1.protein } }
    private var carbs: Double { dayMeals.reduce(0) { $0 + $1.carbs } }
    private var fat: Double { dayMeals.reduce(0) { $0 + $1.fat } }

    private let mealOrder = ["breakfast", "lunch", "dinner", "snack"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dayPicker
                    summaryCard
                    ForEach(mealOrder, id: \.self) { type in
                        let meals = dayMeals.filter { $0.mealType == type }
                        if !meals.isEmpty {
                            mealSection(type: type, meals: meals)
                        }
                    }
                    if dayMeals.isEmpty {
                        ContentUnavailableView("Nothing logged",
                                               systemImage: "fork.knife.circle",
                                               description: Text("Log a meal with + or just tell the assistant what you ate."))
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Food")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) { MealEditorView(day: selectedDay) }
        }
    }

    private var dayPicker: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(selectedDay.dayLabel).font(.headline)
            Spacer()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(selectedDay))
        }
        .padding(.top, 4)
    }

    private func shiftDay(_ delta: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay)!
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(calories)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("of \(settings.dailyCalorieGoal) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Gauge(value: min(1, Double(calories) / Double(max(1, settings.dailyCalorieGoal)))) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.nutrition)
                .scaleEffect(1.2)
            }
            HStack {
                macro("Protein", protein, .red)
                macro("Carbs", carbs, .orange)
                macro("Fat", fat, .yellow)
            }
        }
        .card()
    }

    private func macro(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(grams))g")
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
    }

    private func mealSection(type: String, meals: [Meal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(type.capitalized)
                .font(.headline)
            ForEach(meals) { meal in
                HStack {
                    VStack(alignment: .leading) {
                        Text(meal.name).font(.subheadline.weight(.medium))
                        Text("P \(Int(meal.protein))g · C \(Int(meal.carbs))g · F \(Int(meal.fat))g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(meal.calories) kcal")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .swipeActions { } // keep row tappable in ScrollView context
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(meal)
                        try? context.save()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let day: Date
    @State private var name = ""
    @State private var mealType = "lunch"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("What did you eat?", text: $name)
                Picker("Meal", selection: $mealType) {
                    Text("Breakfast").tag("breakfast")
                    Text("Lunch").tag("lunch")
                    Text("Dinner").tag("dinner")
                    Text("Snack").tag("snack")
                }
                Section("Nutrition") {
                    LabeledContent("Calories") {
                        TextField("0", text: $calories).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("0", text: $protein).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Carbs (g)") {
                        TextField("0", text: $carbs).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat (g)") {
                        TextField("0", text: $fat).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(calories) == nil)
                }
            }
        }
    }

    private func save() {
        let date = Calendar.current.isDateInToday(day) ? Date.now
            : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        context.insert(Meal(name: name, mealType: mealType,
                            calories: Int(calories) ?? 0,
                            protein: Double(protein) ?? 0,
                            carbs: Double(carbs) ?? 0,
                            fat: Double(fat) ?? 0,
                            date: date))
        try? context.save()
        dismiss()
    }
}
