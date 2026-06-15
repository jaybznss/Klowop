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

    private var color: Color { Theme.eventColor(event.title) }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            if event.googleEventID != nil {
                Image(systemName: "g.circle.fill")
                    .font(.caption)
                    .foregroundStyle(color.opacity(0.5))
                    .padding(.trailing, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Schedule view

struct ScheduleListView: View {
    let events: [CalendarEvent]
    var showConnect: Bool
    var connectError: String?
    var onConnect: () -> Void
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
                connectBanner.listRowBackground(Color.clear).listRowSeparator(.hidden)
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
                ContentUnavailableView("No upcoming events",
                                       systemImage: "calendar.badge.plus",
                                       description: Text("Add one with + or ask the assistant."))
                    .listRowBackground(Color.clear)
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

    private var connectBanner: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.agendaGradient, in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Google Calendar").font(.subheadline.weight(.semibold))
                    Text(connectError ?? "See your events here and sync both ways.")
                        .font(.caption)
                        .foregroundStyle(connectError == nil ? Color.secondary : Color.red)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.secondary)
            }
            .padding(12)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Month view

struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    var onSelectEvent: (CalendarEvent) -> Void

    @State private var monthOffset = 0
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            TabView(selection: $monthOffset) {
                ForEach(-12...24, id: \.self) { offset in
                    monthGrid(monthStart(offset))
                        .tag(offset)
                        .padding(.horizontal, 8)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            Divider()
            dayList
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

    private func monthGrid(_ monthStart: Date) -> some View {
        let days = gridDays(monthStart)
        let month = cal.component(.month, from: monthStart)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                         spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayCell(day, inMonth: cal.component(.month, from: day) == month)
            }
        }
    }

    private func dayCell(_ date: Date, inMonth: Bool) -> some View {
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let dots = eventsOn(date).prefix(3)
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
                ForEach(Array(dots.enumerated()), id: \.offset) { _, event in
                    Circle()
                        .fill(Theme.eventColor(event.title))
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
    }

    // MARK: Day list

    private var dayList: some View {
        let dayEvents = eventsOn(selectedDate)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
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

    private func eventsOn(_ date: Date) -> [CalendarEvent] {
        events
            .filter { cal.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }
}
