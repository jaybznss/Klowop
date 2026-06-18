import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var settings = AppSettings.shared
    @State private var google = GoogleCalendarService.shared
    @State private var health = HealthKitService.shared
    @State private var notifications = NotificationService.shared
    @State private var backend = BackendService.shared
    @State private var googleError: String?
    @State private var healthError: String?
    @State private var showingDeleteConfirm = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Your name", text: $settings.userName)
                Stepper("Daily calorie goal: \(settings.dailyCalorieGoal)",
                        value: $settings.dailyCalorieGoal, in: 1000...5000, step: 50)
            }

            accountSection

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
                Toggle("Morning briefing", isOn: $settings.autoBriefingEnabled)
                    .onChange(of: settings.autoBriefingEnabled) { _, enabled in
                        if enabled {
                            Task {
                                if !notifications.isEnabled {
                                    await notifications.requestAuthorization()
                                }
                                BriefingScheduler.scheduleNext()
                            }
                        } else {
                            BriefingScheduler.scheduleNext() // cancels when disabled
                        }
                    }
                if settings.autoBriefingEnabled {
                    Picker("Around", selection: $settings.briefingHour) {
                        ForEach(5..<13, id: \.self) { hour in
                            Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
                                .formatted(date: .omitted, time: .shortened)).tag(hour)
                        }
                    }
                    .onChange(of: settings.briefingHour) {
                        BriefingScheduler.scheduleNext()
                    }
                }
            } header: {
                Text("Daily briefing")
            } footer: {
                Text("Your secretary writes a morning summary and sends it as a notification. iOS schedules background work opportunistically, so it can arrive a little after the chosen time. Requires being signed in.")
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
                TextField("USDA API key (optional)", text: $settings.usdaAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Food database")
            } footer: {
                Text("Food search combines USDA FoodData Central with Open Food Facts. Without a key it uses USDA's shared DEMO_KEY (rate-limited) — get a free personal key in 2 minutes at fdc.nal.usda.gov/api-key-signup.")
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
            Section {
                LabeledContent("Version", value: appVersion)
            } footer: {
                Text("Klowop — your life, one app.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Settings")
        .alert("Delete account?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { try? await backend.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Klowop account and any data on our servers (bank links, subscription). Data stored only on this device is unaffected.")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if backend.isSignedIn {
                LabeledContent("Account") {
                    Label("Signed in", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                if let email = backend.userEmail {
                    LabeledContent("Apple ID", value: email)
                }
                LabeledContent("Subscription",
                               value: backend.subscriptionActive ? "Active" : "Free")
                Button("Sign out") { backend.signOut() }
                Button("Delete account", role: .destructive) { showingDeleteConfirm = true }
            } else {
                Text("Sign in to use the assistant and link your bank accounts. Tracking, calendar, and manual entry work without an account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AppleSignInButton()
                    .padding(.vertical, 4)
            }
        } header: {
            Text("Account")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
