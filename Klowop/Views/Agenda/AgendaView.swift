import SwiftUI
import SwiftData

/// Calendar hub — switches between a Schedule feed and a Month grid (Google-style),
/// with two-way Google Calendar sync. Day / 3-Day / Week time grids come next.
struct AgendaView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @State private var google = GoogleCalendarService.shared
    @State private var mode: CalendarMode = .schedule
    @State private var selectedDate = Date.now
    @State private var monthOffset = 0
    @State private var showingEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var googleError: String?
    @State private var manualSyncCount = 0

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .schedule:
                    ScheduleListView(
                        events: events,
                        showConnect: !google.isConnected,
                        connectError: googleError,
                        syncError: google.lastError,
                        isSyncing: google.isSyncing,
                        onConnect: connect,
                        onRetrySync: { Task { await google.sync(context: context) } },
                        onSelect: { editingEvent = $0 },
                        onDelete: delete)
                case .month:
                    MonthCalendarView(
                        selectedDate: $selectedDate,
                        monthOffset: $monthOffset,
                        events: events,
                        showConnect: !google.isConnected,
                        connectError: googleError,
                        syncError: google.lastError,
                        onConnect: connect,
                        onRetrySync: { Task { await google.sync(context: context) } },
                        onSelectEvent: { editingEvent = $0 })
                }
            }
            .background(AuroraBackground(colors: [.blue, .cyan, .teal]))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("View", selection: $mode) {
                            ForEach(CalendarMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                    } label: {
                        // Reflect the active mode so the switcher isn't a mystery icon.
                        Image(systemName: mode.icon)
                    }
                    .accessibilityLabel("Switch calendar view")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if mode == .month {
                        Button("Today") {
                            withAnimation(.snappy) {
                                selectedDate = .now
                                monthOffset = 0   // bring the grid home, not just the dot
                            }
                        }
                    }
                    Button {
                        Task {
                            await google.sync(context: context)
                            if google.lastError == nil { manualSyncCount += 1 }
                        }
                    } label: {
                        if google.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(!google.isConnected || google.isSyncing)
                    .accessibilityLabel("Sync with Google Calendar")
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New event")
                }
            }
            .sheet(isPresented: $showingEditor) { EventEditorView(event: nil) }
            .sheet(item: $editingEvent) { EventEditorView(event: $0) }
            .animation(.snappy, value: events.count)
            // Haptic only for user-initiated syncs — auto-sync on launch shouldn't buzz.
            .sensoryFeedback(.success, trigger: manualSyncCount)
            .task {
                if google.isConnected { await google.sync(context: context) }
            }
        }
    }

    private var visibleMonth: Date {
        let base = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: .now))!
        return Calendar.current.date(byAdding: .month, value: monthOffset, to: base)!
    }

    private var title: String {
        switch mode {
        case .schedule: return "Agenda"
        // Derived from the visible grid page, so swiping months updates the title.
        case .month: return visibleMonth.formatted(.dateTime.month(.wide).year())
        }
    }

    private func connect() {
        Task {
            do { try await google.connect() }
            catch { googleError = error.localizedDescription }
        }
    }

    private func delete(_ event: CalendarEvent) {
        if let googleID = event.googleEventID {
            let calendarID = event.calendarID
            Task { await google.deleteRemoteEvent(id: googleID, calendarID: calendarID) }
        }
        context.delete(event)
        try? context.save()
    }
}

// MARK: - Event editor

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let event: CalendarEvent?
    @State private var title = ""
    // New events default to the next round half hour, not 3:47pm.
    @State private var startDate = Date.now.roundedUpToHalfHour
    @State private var endDate = Date.now.roundedUpToHalfHour.addingTimeInterval(3600)
    @State private var isAllDay = false
    @State private var location = ""
    @State private var notes = ""
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Toggle("All-day", isOn: $isAllDay.animation(.snappy))
                DatePicker("Starts", selection: $startDate,
                           displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $endDate, in: startDate...,
                           displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                TextField("Location", text: $location)
                TextField("Notes", text: $notes, axis: .vertical)
                if event != nil {
                    Section {
                        Button("Delete Event", role: .destructive) {
                            confirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
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
            // Moving the start past the end must drag the end along — otherwise
            // a stale earlier end survives until the picker is reopened.
            .onChange(of: startDate) { old, new in
                if endDate < new { endDate = new.addingTimeInterval(endDate.timeIntervalSince(old) + 3600) }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteEvent() }
            } message: {
                Text(event?.googleEventID != nil
                     ? "This also removes it from Google Calendar."
                     : "This can't be undone.")
            }
            .onAppear {
                if let event {
                    title = event.title
                    startDate = event.startDate
                    endDate = event.endDate
                    isAllDay = event.isAllDay
                    location = event.location ?? ""
                    notes = event.notes ?? ""
                }
            }
        }
    }

    private func save() {
        var start = startDate
        var end = max(endDate, startDate)
        if isAllDay {
            let cal = Calendar.current
            start = cal.startOfDay(for: start)
            end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
                .addingTimeInterval(-1)
        }
        if let event {
            event.title = title
            event.startDate = start
            event.endDate = end
            event.isAllDay = isAllDay
            event.location = location.isEmpty ? nil : location
            event.notes = notes.isEmpty ? nil : notes
            event.needsGoogleSync = true
        } else {
            context.insert(CalendarEvent(title: title, startDate: start, endDate: end,
                                         isAllDay: isAllDay,
                                         location: location.isEmpty ? nil : location,
                                         notes: notes.isEmpty ? nil : notes))
        }
        try? context.save()
        // Push right away — "syncs both ways" shouldn't wait for the next launch.
        if GoogleCalendarService.shared.isConnected {
            let ctx = context
            Task { await GoogleCalendarService.shared.sync(context: ctx) }
        }
        dismiss()
    }

    private func deleteEvent() {
        if let event {
            if let googleID = event.googleEventID {
                let calendarID = event.calendarID
                Task { await GoogleCalendarService.shared.deleteRemoteEvent(id: googleID,
                                                                            calendarID: calendarID) }
            }
            context.delete(event)
            try? context.save()
        }
        dismiss()
    }
}

extension Date {
    /// The next :00 or :30 boundary — sensible default for new events.
    var roundedUpToHalfHour: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        comps.second = 0
        let truncated = cal.date(from: comps)!
        let remainder = (comps.minute ?? 0) % 30
        return remainder == 0 ? truncated
            : cal.date(byAdding: .minute, value: 30 - remainder, to: truncated)!
    }
}
