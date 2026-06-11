import SwiftUI
import SwiftData
import Charts

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showingEditor = false
    @State private var settings = AppSettings.shared
    @State private var health = HealthKitService.shared
    @State private var weightHistory: [HealthKitService.HistorySample] = []
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
                    weeklyCaloriesCard
                    if health.isEnabled {
                        activityCard
                        if !health.bodyComposition.isEmpty { bodyCard }
                    }
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
            .task {
                await health.refresh(day: selectedDay)
                weightHistory = await health.weightHistory()
            }
            .onChange(of: selectedDay) {
                Task { await health.refresh(day: selectedDay) }
            }
            .refreshable {
                await health.refresh(day: selectedDay)
                weightHistory = await health.weightHistory()
            }
            .animation(.smooth, value: calories)
            .sensoryFeedback(.increase, trigger: allMeals.count)
        }
    }

    // MARK: - Weekly calories chart

    private struct DayCalories: Identifiable {
        let id: Date
        let day: Date
        let calories: Int
    }

    private var weekData: [DayCalories] {
        (0..<7).reversed().map { offset in
            let day = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -offset, to: selectedDay)!)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            let total = allMeals.filter { $0.date >= day && $0.date < end }.reduce(0) { $0 + $1.calories }
            return DayCalories(id: day, day: day, calories: total)
        }
    }

    private var weeklyCaloriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Last 7 days", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundStyle(Theme.nutrition)
            Chart(weekData) { entry in
                BarMark(
                    x: .value("Day", entry.day, unit: .day),
                    y: .value("kcal", entry.calories)
                )
                .foregroundStyle(
                    Calendar.current.isDate(entry.day, inSameDayAs: selectedDay)
                        ? Theme.nutrition.gradient
                        : Theme.nutrition.opacity(0.35).gradient
                )
                .cornerRadius(4)

                RuleMark(y: .value("Goal", settings.dailyCalorieGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Apple Health cards

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Activity", systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(.pink)
            HStack {
                activityStat(value: "\(Int(health.activity?.activeEnergy ?? 0))",
                             unit: "kcal burned", symbol: "flame.fill", color: .pink)
                activityStat(value: "\(Int(health.activity?.steps ?? 0))",
                             unit: "steps", symbol: "figure.walk", color: .teal)
                activityStat(value: "\(Int(health.activity?.exerciseMinutes ?? 0))",
                             unit: "exercise min", symbol: "timer", color: .green)
            }
            netCaloriesLine
            Text("From Apple Watch via Apple Health")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var netCaloriesLine: some View {
        let burned = Int(health.activity?.activeEnergy ?? 0)
        let net = calories - burned
        return Text("Net intake today: **\(net) kcal** (\(calories) eaten − \(burned) burned)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func activityStat(value: String, unit: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.headline).monospacedDigit()
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Body", systemImage: "figure.arms.open")
                .font(.headline)
                .foregroundStyle(.cyan)
            HStack {
                if let weight = health.bodyComposition.weightKg {
                    bodyStat(value: Measurement(value: weight.value, unit: UnitMass.kilograms)
                                .formatted(.measurement(width: .abbreviated, usage: .personWeight)),
                             label: "Weight", date: weight.date)
                }
                if let fat = health.bodyComposition.bodyFatFraction {
                    bodyStat(value: String(format: "%.1f%%", fat.value * 100),
                             label: "Body fat", date: fat.date)
                }
                if let lean = health.bodyComposition.leanMassKg {
                    bodyStat(value: Measurement(value: lean.value, unit: UnitMass.kilograms)
                                .formatted(.measurement(width: .abbreviated, usage: .personWeight)),
                             label: "Lean mass", date: lean.date)
                }
            }
            if weightHistory.count >= 2 {
                Chart(weightHistory) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Weight", sample.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.cyan.gradient)
                    AreaMark(
                        x: .value("Date", sample.date),
                        y: .value("Weight", sample.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan.opacity(0.25), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 110)
            }
            Text("Latest measurements from Apple Health (e.g. Hume BodyPod)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func bodyStat(value: String, label: String, date: Date) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(date.dayLabel).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.cyan.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
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
                        .contentTransition(.numericText(value: Double(calories)))
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
                        if let uuid = meal.healthKitUUID {
                            Task { await HealthKitService.shared.deleteMeal(uuid: uuid) }
                        }
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
        let meal = Meal(name: name, mealType: mealType,
                        calories: Int(calories) ?? 0,
                        protein: Double(protein) ?? 0,
                        carbs: Double(carbs) ?? 0,
                        fat: Double(fat) ?? 0,
                        date: date)
        context.insert(meal)
        try? context.save()
        Task { @MainActor in
            meal.healthKitUUID = await HealthKitService.shared.logMeal(
                name: meal.name, calories: meal.calories, protein: meal.protein,
                carbs: meal.carbs, fat: meal.fat, date: meal.date)
            try? context.save()
        }
        dismiss()
    }
}
