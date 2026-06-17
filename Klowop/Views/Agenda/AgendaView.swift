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
    @State private var showingEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var googleError: String?

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
                        onConnect: connect,
                        onSelect: { editingEvent = $0 },
                        onDelete: delete)
                case .month:
                    MonthCalendarView(
                        selectedDate: $selectedDate,
                        events: events,
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
                        Image(systemName: "square.grid.2x2")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if mode == .month {
                        Button("Today") { withAnimation(.snappy) { selectedDate = .now } }
                    }
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

    private var title: String {
        switch mode {
        case .schedule: return "Agenda"
        case .month: return selectedDate.formatted(.dateTime.month(.wide).year())
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
            Task { await google.deleteRemoteEvent(id: googleID) }
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
