import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Bundle

@main
struct KlowopWidgetBundle: WidgetBundle {
    var body: some Widget {
        KlowopTodayWidget()
    }
}

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    struct EventLine: Identifiable {
        let id = UUID()
        let time: String
        let title: String
    }

    let date: Date
    let calories: Int
    let goal: Int
    let upcomingEvents: [EventLine]
    let openTodoCount: Int

    var progress: Double { min(1, Double(calories) / Double(max(1, goal))) }

    static let placeholder = TodayEntry(
        date: .now, calories: 1430, goal: 2200,
        upcomingEvents: [.init(time: "12:30", title: "Lunch with Sam"),
                         .init(time: "15:00", title: "Design review")],
        openTodoCount: 4)
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = loadEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadEntry() -> TodayEntry {
        let goal = UserDefaults(suiteName: AppGroup.id)?.integer(forKey: "daily_calorie_goal") ?? 0

        guard let container = try? AppGroup.makeModelContainer() else {
            return TodayEntry(date: .now, calories: 0, goal: max(goal, 2200),
                              upcomingEvents: [], openTodoCount: 0)
        }
        let context = ModelContext(container)
        let dayStart = Calendar.current.startOfDay(for: .now)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let now = Date.now

        let meals = (try? context.fetch(FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }))) ?? []

        var eventsDescriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= now && $0.startDate < dayEnd },
            sortBy: [SortDescriptor(\.startDate)])
        eventsDescriptor.fetchLimit = 3
        let events = (try? context.fetch(eventsDescriptor)) ?? []

        let openTodos = (try? context.fetchCount(FetchDescriptor<TodoItem>(
            predicate: #Predicate { !$0.isDone }))) ?? 0

        return TodayEntry(
            date: .now,
            calories: meals.reduce(0) { $0 + $1.calories },
            goal: max(goal, 1),
            upcomingEvents: events.map {
                .init(time: $0.startDate.formatted(date: .omitted, time: .shortened), title: $0.title)
            },
            openTodoCount: openTodos)
    }
}

// MARK: - Widget

struct KlowopTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KlowopToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your calories, next events, and open to-dos at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            calorieRing(size: 52)
            if let next = entry.upcomingEvents.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.time)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(next.title)
                        .font(.caption)
                        .lineLimit(2)
                }
            } else {
                Text("No more events today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                calorieRing(size: 62)
                Text("\(entry.openTodoCount) to-dos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Up next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                if entry.upcomingEvents.isEmpty {
                    Text("All clear for the rest of today 🎉")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.upcomingEvents) { event in
                        HStack(spacing: 8) {
                            Text(event.time)
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 52, alignment: .leading)
                            Text(event.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func calorieRing(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(entry.calories)")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("kcal")
                    .font(.system(size: size * 0.16))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
