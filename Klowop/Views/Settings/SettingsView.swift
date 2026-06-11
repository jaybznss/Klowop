import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var settings = AppSettings.shared
    @State private var google = GoogleCalendarService.shared
    @State private var health = HealthKitService.shared
    @State private var notifications = NotificationService.shared
    @State private var googleError: String?
    @State private var healthError: String?

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Your name", text: $settings.userName)
                Stepper("Daily calorie goal: \(settings.dailyCalorieGoal)",
                        value: $settings.dailyCalorieGoal, in: 1000...5000, step: 50)
            }

            Section {
                if notifications.isEnabled {
                    LabeledContent("Reminders") {
                        Label("On", systemImage: "bell.fill").foregroundStyle(.orange)
                    }
                } else {
                    Button("Enable event & renewal reminders") {
                        Task { await notifications.requestAuthorization() }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("30 minutes before events, and the day before a subscription renews.")
            }

            Section {
                SecureField("Anthropic API key (sk-ant-…)", text: $settings.anthropicAPIKey)
            } header: {
                Text("Assistant")
            } footer: {
                Text("Powers the secretary chat. Create a key at console.anthropic.com — see SETUP.md step 2.")
            }

            Section {
                if !HealthKitService.isAvailable {
                    Text("Apple Health isn't available on this device.")
                        .foregroundStyle(.secondary)
                } else if health.isEnabled {
                    LabeledContent("Status") {
                        Label("Connected", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                } else {
                    Button("Connect Apple Health") {
                        Task {
                            do { try await health.requestAuthorization() }
                            catch { healthError = error.localizedDescription }
                        }
                    }
                }
                if let healthError {
                    Text(healthError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Meals you log are saved to Apple Health. Activity from your Apple Watch and body composition from smart scales (e.g. Hume BodyPod) show up in the Food tab and are visible to the assistant.")
            }

            Section {
                TextField("Google OAuth client ID", text: $settings.googleClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if google.isConnected {
                    LabeledContent("Status") {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if let last = google.lastSyncDate {
                        LabeledContent("Last sync", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Disconnect Google Calendar", role: .destructive) {
                        google.disconnect()
                    }
                } else {
                    Button("Connect Google Calendar") {
                        Task {
                            do { try await google.connect() }
                            catch { googleError = error.localizedDescription }
                        }
                    }
                    .disabled(settings.googleClientID.isEmpty)
                }
                if let googleError {
                    Text(googleError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Google Calendar")
            } footer: {
                Text("Two-way sync with your Google account. Setup takes ~10 minutes — see SETUP.md step 3.")
            }

            Section {
                TextField("Companion server URL", text: $settings.plaidServerURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Bank linking (Plaid)")
            } footer: {
                Text("URL of the Klowop companion server that talks to Plaid (default http://localhost:8484 for the simulator). See SETUP.md step 4.")
            }
        }
        .navigationTitle("Settings")
    }
}
