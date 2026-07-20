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
    @State private var mealToDelete: Meal?
    @State private var favoritedTrigger = 0
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
                    GymTeaserCard()
                    if health.isEnabled {
                        activityCard
                        if !health.bodyComposition.isEmpty { bodyCard }
                    } else if HealthKitService.isAvailable {
                        connectHealthCard
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
                                               description: Text("Search foods or scan a barcode with +, or just tell the assistant what you ate."))
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Health")
            .background(AuroraBackground(colors: [.green, .mint, .pink]))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Log food")
                }
            }
            .sheet(isPresented: $showingEditor) { FoodSearchView(day: selectedDay) }
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
            // Only celebrate additions — deletions shouldn't play an "increase" tick.
            .sensoryFeedback(.increase, trigger: allMeals.count) { old, new in new > old }
            .sensoryFeedback(.success, trigger: favoritedTrigger)
            .confirmationDialog("Delete this meal?",
                                isPresented: Binding(get: { mealToDelete != nil },
                                                     set: { if !$0 { mealToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let meal = mealToDelete { delete(meal) }
                    mealToDelete = nil
                }
            } message: {
                Text("This also removes it from Apple Health.")
            }
        }
    }

    private func delete(_ meal: Meal) {
        if let uuid = meal.healthKitUUID {
            Task { await HealthKitService.shared.deleteMeal(uuid: uuid) }
        }
        context.delete(meal)
        try? context.save()
    }

    /// Shown when Apple Health is available but not connected — the features
    /// shouldn't silently vanish; invite the user in.
    private var connectHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Apple Health", symbol: "heart.text.square.fill",
                       gradient: Theme.activityGradient)
            Text("See your Apple Watch activity and body composition next to your food log — and mirror logged meals back into Health.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    try? await health.requestAuthorization()
                    await health.refresh(day: selectedDay)
                    weightHistory = await health.weightHistory()
                }
            } label: {
                Text("Connect Apple Health")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
            CardHeader(title: "Last 7 days", symbol: "chart.bar.fill", gradient: Theme.nutritionGradient)
            Chart(weekData) { entry in
                BarMark(
                    x: .value("Day", entry.day, unit: .day),
                    y: .value("kcal", entry.calories)
                )
                .foregroundStyle(
                    Calendar.current.isDate(entry.day, inSameDayAs: selectedDay)
                        ? AnyShapeStyle(Theme.nutritionGradient)
                        : AnyShapeStyle(Theme.nutrition.opacity(0.3))
                )
                .cornerRadius(6)

                RuleMark(y: .value("Goal", settings.dailyCalorieGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
            CardHeader(title: "Activity", symbol: "figure.run", gradient: Theme.activityGradient)
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
        .background(color.opacity(0.10), in: .rect(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Body", symbol: "figure.arms.open", gradient: Theme.bodyGradient)
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
        .background(Color.cyan.opacity(0.10), in: .rect(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
    }

    private var dayPicker: some View {
        HStack {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")
            Spacer()
            Text(selectedDay.dayLabel).font(.headline)
            Spacer()
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next day")
            .disabled(Calendar.current.isDateInToday(selectedDay))
        }
    }

    private func shiftDay(_ delta: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay)!
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(calories)")
                        // Semantic style so it scales with Dynamic Type.
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(calories)))
                    Text("of \(settings.dailyCalorieGoal) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let percent = Int(Double(calories) / Double(max(1, settings.dailyCalorieGoal)) * 100)
                ZStack {
                    ProgressRing(progress: Double(calories) / Double(max(1, settings.dailyCalorieGoal)),
                                 gradient: Theme.nutritionGradient, glow: .green)
                    Text("\(percent)%")
                        .font(.caption.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        // Over-goal reads amber instead of pretending it's fine.
                        .foregroundStyle(percent > 100 ? Color.orange : Color.primary)
                }
                .frame(width: 64, height: 64)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(percent) percent of calorie goal")
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
        .background(color.opacity(0.10), in: .rect(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
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
                    // Visible affordance — context menus alone are undiscoverable.
                    Menu {
                        Button {
                            addToFavorites(meal)
                        } label: { Label("Add to favorites", systemImage: "star") }
                        Button(role: .destructive) {
                            mealToDelete = meal
                        } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Meal options")
                }
                .contextMenu {
                    Button {
                        addToFavorites(meal)
                    } label: { Label("Add to favorites", systemImage: "star") }
                    Button(role: .destructive) {
                        mealToDelete = meal
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func addToFavorites(_ meal: Meal) {
        context.insert(FavoriteFood(
            name: meal.name, brand: meal.notes, calories: meal.calories,
            protein: meal.protein, carbs: meal.carbs, fat: meal.fat,
            mealType: meal.mealType))
        try? context.save()
        favoritedTrigger += 1
    }
}

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let day: Date
    @State private var name = ""
    // Default to the meal implied by the current time, not a hard-coded lunch.
    @State private var mealType: String = {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 11 ? "breakfast" : hour < 15 ? "lunch" : hour < 21 ? "dinner" : "snack"
    }()
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("What did you eat?", text: $name)
                    .focused($fieldFocused)
                Picker("Meal", selection: $mealType) {
                    Text("Breakfast").tag("breakfast")
                    Text("Lunch").tag("lunch")
                    Text("Dinner").tag("dinner")
                    Text("Snack").tag("snack")
                }
                Section("Nutrition") {
                    LabeledContent("Calories") {
                        TextField("0", text: $calories).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).focused($fieldFocused)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("0", text: $protein).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).focused($fieldFocused)
                    }
                    LabeledContent("Carbs (g)") {
                        TextField("0", text: $carbs).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).focused($fieldFocused)
                    }
                    LabeledContent("Fat (g)") {
                        TextField("0", text: $fat).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).focused($fieldFocused)
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
                // Number pads have no Return key — give the keyboard a Done.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
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
