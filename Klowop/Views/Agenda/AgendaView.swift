import SwiftUI
import SwiftData

struct AgendaView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @State private var google = GoogleCalendarService.shared
    @State private var showingEditor = false
    @State private var editingEvent: CalendarEvent?

    private var upcoming: [(day: Date, events: [CalendarEvent])] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!
        let grouped = Dictionary(grouping: events.filter { $0.startDate > cutoff }) {
            Calendar.current.startOfDay(for: $0.startDate)
        }
        return grouped.keys.sorted().map { (day: $0, events: grouped[$0]!.sorted { $0.startDate < $1.startDate }) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = google.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ForEach(upcoming, id: \.day) { group in
                    Section(group.day.dayLabel) {
                        ForEach(group.events) { event in
                            Button { editingEvent = event } label: { row(for: event) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let event = group.events[index]
                                if let googleID = event.googleEventID {
                                    Task { await google.deleteRemoteEvent(id: googleID) }
                                }
                                context.delete(event)
                            }
                            try? context.save()
                        }
                    }
                }
                if upcoming.isEmpty {
                    ContentUnavailableView("No upcoming events",
                                           systemImage: "calendar.badge.plus",
                                           description: Text("Add one with + or ask the assistant."))
                }
            }
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
                            Image(systemName: google.isConnected
                                  ? "arrow.triangle.2.circlepath"
                                  : "arrow.triangle.2.circlepath.circle")
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

    private func row(for event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading) {
                Text(event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Text(event.endDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.medium))
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if event.googleEventID != nil {
                Image(systemName: "g.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
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
