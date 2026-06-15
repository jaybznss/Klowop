import SwiftUI
import SwiftData

struct AgendaView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @State private var google = GoogleCalendarService.shared
    @State private var showingEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var googleError: String?

    /// Today onward, in chronological order — the Schedule feed.
    private var orderedEvents: [CalendarEvent] {
        let cutoff = Calendar.current.startOfDay(for: .now)
        return events.filter { $0.endDate >= cutoff }.sorted { $0.startDate < $1.startDate }
    }

    /// Grouped into month sections (matches Google's Schedule headers).
    private var months: [(label: String, events: [CalendarEvent])] {
        let grouped = Dictionary(grouping: orderedEvents) {
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
        NavigationStack {
            List {
                if !google.isConnected {
                    connectBanner.listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(months, id: \.label) { month in
                    Section {
                        ForEach(Array(month.events.enumerated()), id: \.element.id) { index, event in
                            scheduleRow(event, showDate: isFirstOfDay(month.events, index))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions {
                                    Button(role: .destructive) { delete(event) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(month.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if orderedEvents.isEmpty {
                    ContentUnavailableView("No upcoming events",
                                           systemImage: "calendar.badge.plus",
                                           description: Text("Add one with + or ask the assistant."))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AuroraBackground(colors: [.blue, .cyan, .teal]))
            .navigationTitle("Agenda")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await google.sync(context: context) }
                    } label: {
                        if google.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(!google.isConnected || google.isSyncing)
                    .help("Sync with Google Calendar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) { EventEditorView(event: nil) }
            .sheet(item: $editingEvent) { EventEditorView(event: $0) }
            .animation(.snappy, value: events.count)
            .sensoryFeedback(.success, trigger: google.lastSyncDate)
            .task {
                if google.isConnected { await google.sync(context: context) }
            }
        }
    }

    private func isFirstOfDay(_ events: [CalendarEvent], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(events[index].startDate,
                                        inSameDayAs: events[index - 1].startDate)
    }

    private func delete(_ event: CalendarEvent) {
        if let googleID = event.googleEventID {
            Task { await google.deleteRemoteEvent(id: googleID) }
        }
        context.delete(event)
        try? context.save()
    }

    // MARK: - Connect banner

    private var connectBanner: some View {
        Button {
            Task {
                do { try await google.connect() }
                catch { googleError = error.localizedDescription }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.agendaGradient, in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Google Calendar").font(.subheadline.weight(.semibold))
                    Text(googleError ?? "See your events here and sync both ways.")
                        .font(.caption)
                        .foregroundStyle(googleError == nil ? .secondary : .red)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule row

    private func scheduleRow(_ event: CalendarEvent, showDate: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            dateRail(for: event.startDate, visible: showDate)
            Button { editingEvent = event } label: { eventChip(event) }
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
                    .foregroundStyle(isToday ? Theme.agenda : .secondary)
                ZStack {
                    if isToday {
                        Circle().fill(Theme.agendaGradient).frame(width: 34, height: 34)
                    }
                    Text(date.formatted(.dateTime.day()))
                        .font(.headline)
                        .foregroundStyle(isToday ? .white : .primary)
                }
            }
        }
        .frame(width: 42)
    }

    private func eventChip(_ event: CalendarEvent) -> some View {
        let color = Self.eventColor(event.title)
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    /// Stable color per event (a hash that survives relaunches, unlike hashValue).
    private static func eventColor(_ title: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .teal, .green, .orange, .pink, .purple, .red]
        let sum = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let event: CalendarEvent?
    @State private var title = ""
    @State private var startDate = Date.now
    @State private var endDate = Date.now.addingTimeInterval(3600)
    @State private var location = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $startDate)
                DatePicker("Ends", selection: $endDate, in: startDate...)
                TextField("Location", text: $location)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle(event == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let event {
                    title = event.title
                    startDate = event.startDate
                    endDate = event.endDate
                    location = event.location ?? ""
                    notes = event.notes ?? ""
                }
            }
        }
    }

    private func save() {
        if let event {
            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.location = location.isEmpty ? nil : location
            event.notes = notes.isEmpty ? nil : notes
            event.needsGoogleSync = true
        } else {
            context.insert(CalendarEvent(title: title, startDate: startDate, endDate: endDate,
                                         location: location.isEmpty ? nil : location,
                                         notes: notes.isEmpty ? nil : notes))
        }
        try? context.save()
        dismiss()
    }
}
