import SwiftUI
import SwiftData

// MARK: - View modes

enum CalendarMode: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case month = "Month"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .schedule: return "list.bullet"
        case .month: return "calendar"
        }
    }
}

// MARK: - Shared event chip

/// A colored event chip used by the Schedule and Month day-list views.
struct EventChip: View {
    let event: CalendarEvent

    private var color: Color { Theme.color(for: event) }

    private var isNow: Bool {
        !event.isAllDay && (event.startDate...event.endDate).contains(.now)
    }

    private var timeText: String {
        event.isAllDay
            ? "All-day"
            : "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    // Neutral text over the tinted fill (Google-style): the color
                    // lives in the rail, so light calendar hues stay readable.
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(timeText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            if isNow {
                Text("Now")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color, in: .capsule)
                    .padding(.trailing, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(timeText)\(isNow ? ", happening now" : "")")
    }
}

// MARK: - Shared connect / sync-error surfaces

/// "Connect Google Calendar" banner — shown by both Schedule and Month modes.
struct GoogleConnectBanner: View {
    var connectError: String?
    var onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.agendaGradient, in: .rect(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Google Calendar").font(.subheadline.weight(.semibold))
                    Text(connectError ?? "See your events here and sync both ways.")
                        .font(.caption)
                        .foregroundStyle(connectError == nil ? Color.secondary : Color.red)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Sync failure with a retry affordance — a tiny orange caption isn't enough.
struct SyncErrorRow: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Button("Try again", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.agenda)
            }
        }
    }
}

// MARK: - Schedule view

struct ScheduleListView: View {
    let events: [CalendarEvent]
    var showConnect: Bool
    var connectError: String?
    var syncError: String?
    var isSyncing: Bool = false
    var onConnect: () -> Void
    var onRetrySync: () -> Void = {}
    var onSelect: (CalendarEvent) -> Void
    var onDelete: (CalendarEvent) -> Void

    private var ordered: [CalendarEvent] {
        let cutoff = Calendar.current.startOfDay(for: .now)
        return events.filter { $0.endDate >= cutoff }.sorted { $0.startDate < $1.startDate }
    }

    private var months: [(label: String, events: [CalendarEvent])] {
        let grouped = Dictionary(grouping: ordered) {
            Calendar.current.dateComponents([.year, .month], from: $0.startDate)
        }
        return grouped.keys
            .sorted { ($0.year!, $0.month!) < ($1.year!, $1.month!) }
            .map { comps in
                let date = Calendar.current.date(from: comps)!
                return (date.formatted(.dateTime.month(.wide).year()),
                        grouped[comps]!.sorted { $0.startDate < $1.startDate })
            }
    }

    var body: some View {
        List {
            if showConnect {
                GoogleConnectBanner(connectError: connectError, onConnect: onConnect)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if let syncError {
                SyncErrorRow(message: syncError, onRetry: onRetrySync)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(months, id: \.label) { month in
                Section {
                    ForEach(Array(month.events.enumerated()), id: \.element.id) { index, event in
                        row(event, showDate: isFirstOfDay(month.events, index))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions {
                                Button(role: .destructive) { onDelete(event) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(month.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            if ordered.isEmpty {
                if isSyncing {
                    // First sync in flight — don't claim "no events" while loading.
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Syncing your calendars…")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ContentUnavailableView("No upcoming events",
                                           systemImage: "calendar.badge.plus",
                                           description: Text("Add one with + or ask the assistant."))
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func isFirstOfDay(_ events: [CalendarEvent], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(events[index].startDate,
                                        inSameDayAs: events[index - 1].startDate)
    }

    private func row(_ event: CalendarEvent, showDate: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            dateRail(for: event.startDate, visible: showDate)
            Button { onSelect(event) } label: { EventChip(event: event) }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }

    private func dateRail(for date: Date, visible: Bool) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return VStack(spacing: 3) {
            if visible {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? Theme.agenda : Color.secondary)
                ZStack {
                    if isToday {
                        Circle().fill(Theme.agendaGradient).frame(width: 34, height: 34)
                    }
                    Text(date.formatted(.dateTime.day()))
                        .font(.headline)
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                }
            }
        }
        .frame(width: 42)
    }

}

// MARK: - Month view

struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var monthOffset: Int
    let events: [CalendarEvent]
    var showConnect: Bool = false
    var connectError: String?
    var syncError: String?
    var onConnect: () -> Void = {}
    var onRetrySync: () -> Void = {}
    var onSelectEvent: (CalendarEvent) -> Void

    private let cal = Calendar.current

    /// Events bucketed by day — computed once per render instead of a linear
    /// scan for every one of the grid's cells.
    private var eventsByDay: [Date: [CalendarEvent]] {
        Dictionary(grouping: events) { cal.startOfDay(for: $0.startDate) }
            .mapValues { $0.sorted { $0.startDate < $1.startDate } }
    }

    var body: some View {
        let buckets = eventsByDay
        VStack(spacing: 0) {
            if showConnect {
                GoogleConnectBanner(connectError: connectError, onConnect: onConnect)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
            if let syncError {
                SyncErrorRow(message: syncError, onRetry: onRetrySync)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
            weekdayHeader
            TabView(selection: $monthOffset) {
                ForEach(-12...24, id: \.self) { offset in
                    monthGrid(monthStart(offset), buckets: buckets)
                        .tag(offset)
                        .padding(.horizontal, 8)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            Divider()
            dayList(buckets: buckets)
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
        // Keep the selection inside the visible month so the day list below
        // always belongs to the page on screen.
        .onChange(of: monthOffset) { _, _ in
            let month = monthStart(monthOffset)
            guard !cal.isDate(selectedDate, equalTo: month, toGranularity: .month) else { return }
            let dayCount = cal.range(of: .day, in: .month, for: month)?.count ?? 28
            let day = min(cal.component(.day, from: selectedDate), dayCount)
            selectedDate = cal.date(byAdding: .day, value: day - 1, to: month) ?? month
        }
    }

    // MARK: Header

    private var weekdayHeader: some View {
        let symbols = orderedWeekdaySymbols()
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func orderedWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        let symbols: [String] = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: Grid

    private func monthStart(_ offset: Int) -> Date {
        let base = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        return cal.date(byAdding: .month, value: offset, to: base)!
    }

    private func gridDays(_ monthStart: Date) -> [Date] {
        let firstWeekday = cal.component(.weekday, from: monthStart)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -leading, to: monthStart)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    private func monthGrid(_ monthStart: Date, buckets: [Date: [CalendarEvent]]) -> some View {
        let days = gridDays(monthStart)
        let month = cal.component(.month, from: monthStart)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                         spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayCell(day, inMonth: cal.component(.month, from: day) == month, buckets: buckets)
            }
        }
    }

    private func dayCell(_ date: Date, inMonth: Bool,
                         buckets: [Date: [CalendarEvent]]) -> some View {
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let dayEvents = buckets[cal.startOfDay(for: date)] ?? []
        return VStack(spacing: 3) {
            ZStack {
                if isToday {
                    Circle().fill(Theme.agendaGradient).frame(width: 30, height: 30)
                } else if isSelected {
                    Circle().stroke(Theme.agenda, lineWidth: 1.5).frame(width: 30, height: 30)
                }
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline)
                    .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
            }
            .frame(height: 32)
            HStack(spacing: 3) {
                ForEach(Array(dayEvents.prefix(3).enumerated()), id: \.offset) { _, event in
                    Circle()
                        .fill(Theme.color(for: event))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { selectedDate = date }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayCellLabel(date, count: dayEvents.count))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayCellLabel(_ date: Date, count: Int) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        switch count {
        case 0: return day
        case 1: return "\(day), 1 event"
        default: return "\(day), \(count) events"
        }
    }

    // MARK: Day list

    private func dayList(buckets: [Date: [CalendarEvent]]) -> some View {
        let dayEvents = buckets[cal.startOfDay(for: selectedDate)] ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(dayListHeader)
                    .font(.headline)
                    .padding(.top, 12)
                if dayEvents.isEmpty {
                    Text("Nothing scheduled.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 4)
                } else {
                    ForEach(dayEvents) { event in
                        Button { onSelectEvent(event) } label: { EventChip(event: event) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    /// "Today · Wednesday, July 2"-style header for the selected day.
    private var dayListHeader: String {
        let full = selectedDate.formatted(.dateTime.weekday(.wide).month().day())
        if cal.isDateInToday(selectedDate) { return "Today · \(full)" }
        if cal.isDateInTomorrow(selectedDate) { return "Tomorrow · \(full)" }
        return full
    }
}
