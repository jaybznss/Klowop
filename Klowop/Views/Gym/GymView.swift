import SwiftUI
import SwiftData

/// Gym hub: custom workouts you can build and perform, plus every dollar the
/// gym costs you (membership, day passes, training, gear).
struct GymView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \GymCharge.date, order: .reverse) private var charges: [GymCharge]

    @State private var showingWorkoutEditor = false
    @State private var editingTemplate: WorkoutTemplate?
    @State private var activeTemplate: WorkoutTemplate?
    @State private var showingChargeEditor = false
    @State private var finishedSessionCount = 0

    private var sessionsThisWeek: Int {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return sessions.filter { $0.date >= weekStart }.count
    }

    private var spentThisMonth: Double {
        guard let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start else { return 0 }
        return charges.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statRow
                workoutsCard
                if !sessions.isEmpty { recentSessionsCard }
                chargesCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("Gym")
        .background(AuroraBackground(colors: [.orange, .red, .pink]))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingWorkoutEditor = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New workout")
            }
        }
        .sheet(isPresented: $showingWorkoutEditor) { WorkoutEditorView(template: nil) }
        .sheet(item: $editingTemplate) { WorkoutEditorView(template: $0) }
        .fullScreenCover(item: $activeTemplate) { template in
            ActiveWorkoutView(template: template) { finishedSessionCount += 1 }
        }
        .sheet(isPresented: $showingChargeEditor) { GymChargeEditorView() }
        .sensoryFeedback(.success, trigger: finishedSessionCount)
    }

    // MARK: - Stats

    private var statRow: some View {
        HStack(spacing: 12) {
            gymStat(value: "\(sessionsThisWeek)",
                    label: sessionsThisWeek == 1 ? "workout this week" : "workouts this week",
                    symbol: "dumbbell.fill")
            gymStat(value: spentThisMonth.asCurrency(),
                    label: "spent this month",
                    symbol: "creditcard.fill")
        }
        .padding(.top, 4)
    }

    private func gymStat(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.gymGradient, in: .rect(cornerRadius: 8, style: .continuous))
            Text(value)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Workouts

    private var workoutsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "My workouts", symbol: "dumbbell.fill", gradient: Theme.gymGradient)
            if templates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Build a workout once, run it every time — sets, reps, and weights remembered.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tip: ask the assistant — “make me a push day with dumbbells only”.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button {
                        showingWorkoutEditor = true
                    } label: {
                        Label("Create a workout", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.gym)
                }
            }
            ForEach(templates) { template in
                Button { editingTemplate = template } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.name).font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                Text(template.focus)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.gym.opacity(0.12), in: .capsule)
                                    .foregroundStyle(Theme.gym)
                                Text("\(template.exercises.count) exercises")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let last = template.lastPerformed {
                                    Text("· last \(last.dayLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        Button("Start") { activeTemplate = template }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(Theme.gym)
                            .disabled(template.exercises.isEmpty)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(template)
                        try? context.save()
                    } label: { Label("Delete workout", systemImage: "trash") }
                }
                .accessibilityHint("Opens the workout editor")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Recent sessions", symbol: "clock.arrow.circlepath",
                       gradient: Theme.activityGradient)
            ForEach(sessions.prefix(6)) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.templateName).font(.subheadline.weight(.medium))
                        Text("\(session.date.dayLabel) · \(session.exercisesCompleted)/\(session.exercisesTotal) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if session.durationMinutes > 0 {
                        Text("\(session.durationMinutes) min")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(session)
                        try? context.save()
                    } label: { Label("Delete session", systemImage: "trash") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Charges

    private var chargesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Gym charges", symbol: "creditcard.fill",
                           gradient: Theme.financeGradient)
                Button { showingChargeEditor = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.gym)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add gym charge")
            }
            if charges.isEmpty {
                Text("Track your membership, day passes, personal training, and gear. Charges also count toward your Money spending under the “Gym” category.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(charges.prefix(10)) { charge in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(charge.name).font(.subheadline.weight(.medium))
                        Text("\(charge.kind) · \(charge.date.dayLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(charge.amount.asCurrency())
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(charge)
                        try? context.save()
                    } label: { Label("Delete charge", systemImage: "trash") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Health-tab teaser

/// Compact entry point shown on the Health tab.
struct GymTeaserCard: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var templates: [WorkoutTemplate]

    private var sessionsThisWeek: Int {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return sessions.filter { $0.date >= weekStart }.count
    }

    var body: some View {
        NavigationLink {
            GymView()
        } label: {
            HStack {
                CardHeader(title: "Gym", symbol: "dumbbell.fill", gradient: Theme.gymGradient)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sessionsThisWeek == 0 ? "—" : "\(sessionsThisWeek)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(templates.isEmpty ? "build a workout" : "workouts this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout editor

struct WorkoutEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let template: WorkoutTemplate?

    private struct ExerciseDraft: Identifiable {
        let id = UUID()
        var name: String
        var sets: Int
        var reps: Int
        var weight: String       // free text, parsed on save; "" = bodyweight
    }

    @State private var name = ""
    @State private var focus = "Push"
    @State private var drafts: [ExerciseDraft] = []
    @FocusState private var fieldFocused: Bool

    private let focusOptions = ["Push", "Pull", "Legs", "Upper", "Lower", "Full body", "Cardio", "Custom"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Workout name (e.g. Push Day)", text: $name)
                        .focused($fieldFocused)
                    Picker("Focus", selection: $focus) {
                        ForEach(focusOptions, id: \.self) { Text($0) }
                    }
                }
                Section("Exercises") {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Exercise (e.g. Bench press)", text: $draft.name)
                                .focused($fieldFocused)
                            HStack(spacing: 14) {
                                Stepper("\(draft.sets) sets", value: $draft.sets, in: 1...10)
                                    .font(.subheadline)
                            }
                            HStack(spacing: 14) {
                                Stepper("\(draft.reps) reps", value: $draft.reps, in: 1...50)
                                    .font(.subheadline)
                            }
                            LabeledContent("Weight (kg)") {
                                TextField("bodyweight", text: $draft.weight)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($fieldFocused)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { drafts.remove(atOffsets: $0) }
                    Button {
                        drafts.append(ExerciseDraft(name: "", sets: 3, reps: 10, weight: ""))
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(template == nil ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || drafts.allSatisfy { $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
            .onAppear {
                guard let template, drafts.isEmpty, name.isEmpty else { return }
                name = template.name
                focus = template.focus
                drafts = template.orderedExercises.map {
                    ExerciseDraft(name: $0.name, sets: $0.sets, reps: $0.reps,
                                  weight: $0.weightKg > 0 ? "\($0.weightKg.formatted())" : "")
                }
            }
        }
    }

    private func save() {
        let cleanDrafts = drafts.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let target: WorkoutTemplate
        if let template {
            target = template
            target.name = name.trimmingCharacters(in: .whitespaces)
            target.focus = focus
            for exercise in target.exercises { context.delete(exercise) }
            target.exercises = []
        } else {
            target = WorkoutTemplate(name: name.trimmingCharacters(in: .whitespaces), focus: focus)
            context.insert(target)
        }
        for (index, draft) in cleanDrafts.enumerated() {
            let exercise = WorkoutExercise(
                name: draft.name.trimmingCharacters(in: .whitespaces),
                sets: draft.sets, reps: draft.reps,
                weightKg: Double(draft.weight.replacingOccurrences(of: ",", with: ".")) ?? 0,
                orderIndex: index)
            exercise.template = target
            context.insert(exercise)
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Active workout

/// Runs a workout: check off exercises as you go, with a live elapsed timer.
struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let template: WorkoutTemplate
    var onFinish: () -> Void = {}

    @State private var startedAt = Date.now
    @State private var done: Set<PersistentIdentifier> = []
    @State private var confirmingExit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    timerHeader
                    exerciseList
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(AuroraBackground(colors: [.orange, .red, .pink]))
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { confirmingExit = true }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { finish() }
                        .font(.headline)
                        .disabled(done.isEmpty)
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmingExit,
                                titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { dismiss() }
            } message: {
                Text("Nothing will be logged.")
            }
        }
        .interactiveDismissDisabled()
    }

    private var timerHeader: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(startedAt))
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            Text("\(done.count) of \(template.exercises.count) done")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(done.count), total: Double(max(1, template.exercises.count)))
                .tint(Theme.gym)
        }
        .frame(maxWidth: .infinity)
        .heroCard(Theme.gym)
        .padding(.top, 8)
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(template.orderedExercises) { exercise in
                let isDone = done.contains(exercise.persistentModelID)
                Button {
                    withAnimation(.snappy) {
                        if isDone { done.remove(exercise.persistentModelID) }
                        else { done.insert(exercise.persistentModelID) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isDone ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(isDone ? Color.secondary : Color.primary)
                                .strikethrough(isDone, color: .secondary)
                            Text(exercise.detailText)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: isDone) { _, new in new }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func finish() {
        let minutes = max(1, Int(Date.now.timeIntervalSince(startedAt) / 60))
        context.insert(WorkoutSession(
            templateName: template.name, focus: template.focus,
            date: startedAt, durationMinutes: minutes,
            exercisesCompleted: done.count,
            exercisesTotal: template.exercises.count))
        template.lastPerformed = .now
        try? context.save()
        onFinish()
        dismiss()
    }
}

// MARK: - Charge editor

struct GymChargeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var amount = ""
    @State private var kind = "Membership"
    @State private var date = Date.now
    @FocusState private var fieldFocused: Bool

    private let kinds = ["Membership", "Day pass", "Personal training", "Gear", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("What was it? (e.g. Basic-Fit monthly)", text: $name)
                    .focused($fieldFocused)
                LabeledContent("Amount") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($fieldFocused)
                }
                Picker("Type", selection: $kind) {
                    ForEach(kinds, id: \.self) { Text($0) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("New Gym Charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
    }

    private func save() {
        let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        context.insert(GymCharge(name: trimmed, amount: value, kind: kind, date: date))
        // Mirror into Money so spending summaries and budgets include the gym.
        context.insert(MoneyTransaction(merchant: trimmed, amount: value, date: date,
                                        category: "Gym", accountName: "Manual"))
        try? context.save()
        dismiss()
    }
}
