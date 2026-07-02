import SwiftUI
import SwiftData

/// Daily dashboard: schedule, todos, calories, and money at a glance.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var todayEvents: [CalendarEvent]
    @Query private var todayMeals: [Meal]
    @Query(filter: #Predicate<TodoItem> { !$0.isDone },
           sort: \TodoItem.createdAt) private var openTodos: [TodoItem]
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]

    @State private var settings = AppSettings.shared
    @State private var newTodoTitle = ""
    @State private var completedTodoCount = 0
    @State private var briefing: String? = BriefingScheduler.cachedBriefingForToday
    @State private var briefingLoading = false
    @State private var briefingError: String?
    @State private var showAllTodos = false

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        _todayEvents = Query(filter: #Predicate<CalendarEvent> {
            $0.startDate >= start && $0.startDate < end
        }, sort: \CalendarEvent.startDate)
        _todayMeals = Query(filter: #Predicate<Meal> {
            $0.date >= start && $0.date < end
        })
    }

    private var caloriesToday: Int { todayMeals.reduce(0) { $0 + $1.calories } }

    private var spentThisWeek: Double {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return transactions.filter { $0.date >= weekStart && $0.amount > 0 }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    greetingHeader
                    briefingCard
                    statRow
                    scheduleCard
                    todosCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Today")
            .refreshable {
                if GoogleCalendarService.shared.isConnected {
                    await GoogleCalendarService.shared.sync(context: context)
                }
            }
            .background(AuroraBackground(colors: [.indigo, Theme.assistant, .blue]))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .animation(.snappy, value: openTodos.count)
            .sensoryFeedback(.success, trigger: completedTodoCount)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: openTodos.count) { old, new in
                new > old // gentle tap when a todo is added
            }
        }
    }

    private var greetingHeader: some View {
        Text("\(greeting) · \(Date.now.formatted(.dateTime.weekday(.wide).month().day()))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let firstName = settings.userName.split(separator: " ").first.map(String.init) ?? ""
        let name = firstName.isEmpty ? "" : ", \(firstName)"
        switch hour {
        case ..<12: return "Good morning\(name)"
        case ..<18: return "Good afternoon\(name)"
        default: return "Good evening\(name)"
        }
    }

    private var briefingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Daily briefing", symbol: "sparkles", gradient: Theme.assistantGradient)
                if briefingLoading {
                    ProgressView()
                } else {
                    Button {
                        generateBriefing()
                    } label: {
                        Image(systemName: briefing == nil ? "wand.and.stars" : "arrow.clockwise")
                            .foregroundStyle(Theme.assistant)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(briefing == nil ? "Generate briefing" : "Refresh briefing")
                }
            }
            if let briefingError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(briefingError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Try again") { generateBriefing() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.assistant)
                    }
                }
            } else if let briefing {
                Text(LocalizedStringKey(briefing))
                    .font(.subheadline)
                    .transition(.opacity)
            } else if briefingLoading {
                Text("Your secretary is reading through your day…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap the wand for a secretary's summary of your day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard(Theme.assistant)
        // Only glow once there's a real briefing — an empty placeholder
        // shouldn't be the loudest thing on screen.
        .glow(briefing == nil ? .clear : Theme.assistant)
        .animation(.smooth, value: briefing)
    }

    private func generateBriefing() {
        briefingLoading = true
        briefingError = nil
        Task { @MainActor in
            defer { briefingLoading = false }
            do {
                let text = try await ClaudeAssistantService.shared.oneShot(
                    BriefingScheduler.prompt, context: context)
                briefing = text
                BriefingScheduler.cache(text)
            } catch {
                briefingError = error.localizedDescription
            }
        }
    }

    private var statRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                TabRouter.shared.selection = .health
            } label: {
                statTile(title: "Calories",
                         value: "\(caloriesToday)",
                         detail: "of \(settings.dailyCalorieGoal.formatted())",
                         symbol: "flame.fill", color: Theme.nutrition,
                         progress: min(1, Double(caloriesToday) / Double(max(1, settings.dailyCalorieGoal))))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Health")
            Button {
                TabRouter.shared.selection = .money
            } label: {
                statTile(title: "This week",
                         value: spentThisWeek.asCurrency(),
                         detail: "spent",
                         symbol: "creditcard.fill", color: Theme.finance,
                         progress: nil)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Money")
        }
    }

    private func statTile(title: String, value: String, detail: String,
                          symbol: String, color: Color, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(color.gradient, in: .rect(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            // Always lay out the bar so both tiles match height; hide it when unused.
            ProgressView(value: progress ?? 0)
                .tint(color)
                .opacity(progress == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Schedule", symbol: "calendar", gradient: Theme.agendaGradient)
            if todayEvents.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                        .foregroundStyle(Theme.agenda)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing scheduled")
                            .font(.subheadline.weight(.medium))
                        Text("Enjoy the free time — or plan something.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add") { TabRouter.shared.selection = .agenda }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.agenda)
                }
            } else {
                ForEach(todayEvents) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.isAllDay ? "All-day"
                             : event.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(minWidth: 76, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(event.title).font(.subheadline.weight(.medium))
                            if let location = event.location, !location.isEmpty {
                                Text(location).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "To-dos", symbol: "checklist", gradient: Theme.assistantGradient)
            if openTodos.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.assistant)
                    Text("All clear — add your first to-do below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            let visibleTodos = showAllTodos ? Array(openTodos) : Array(openTodos.prefix(8))
            ForEach(visibleTodos) { todo in
                Button {
                    withAnimation(.snappy) {
                        todo.isDone = true
                        completedTodoCount += 1
                    }
                    try? context.save()
                } label: {
                    HStack {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(todo.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if todo.listName != "Inbox" {
                                Text(todo.listName).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let due = todo.dueDate {
                            let overdue = due < Calendar.current.startOfDay(for: .now)
                            Text(due.dayLabel)
                                .font(.caption)
                                .foregroundStyle(overdue ? Color.red : Color.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Marks as done")
            }
            if openTodos.count > 8 {
                Button {
                    withAnimation(.snappy) { showAllTodos.toggle() }
                } label: {
                    Text(showAllTodos ? "Show less" : "Show all \(openTodos.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.assistant)
                }
                .buttonStyle(.plain)
            }
            HStack {
                TextField("Add a to-do…", text: $newTodoTitle)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(addTodo)
                Button(action: addTodo) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.assistant)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to-do")
                .disabled(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func addTodo() {
        let title = newTodoTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        context.insert(TodoItem(title: title))
        try? context.save()
        newTodoTitle = ""
    }
}
