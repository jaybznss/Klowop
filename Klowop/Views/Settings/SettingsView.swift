import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var settings = AppSettings.shared
    @State private var google = GoogleCalendarService.shared
    @State private var health = HealthKitService.shared
    @State private var notifications = NotificationService.shared
    @State private var backend = BackendService.shared
    @State private var store = StoreKitService.shared
    @State private var googleError: String?
    @State private var healthError: String?
    @State private var showingDeleteConfirm = false
    @State private var showingSignOutConfirm = false
    @State private var showingPaywall = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var showAdvanced = false

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
                }
                if let googleError {
                    Text(googleError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Google Calendar")
            } footer: {
                Text("Two-way sync with your Google account.")
            }

            Section {
                LabeledContent("Version", value: appVersion)
            } footer: {
                Text("Klowop — your life, one app.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            // Developer configuration — hidden from the normal flow; defaults
            // are baked in and users should never need these.
            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Google OAuth client ID", text: $settings.googleClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption)
                    TextField("USDA API key (optional)", text: $settings.usdaAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption)
                }
            } footer: {
                if showAdvanced {
                    Text("Food search uses USDA's shared key unless you add a personal one (free at fdc.nal.usda.gov). Leave these as-is unless you know why you're changing them.")
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .alert("Delete account?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Klowop account and any data on our servers (bank links, subscription). Data stored only on this device is unaffected.")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Restore Purchases", isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .confirmationDialog("Sign out?", isPresented: $showingSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { backend.signOut() }
        } message: {
            Text("The assistant and bank-linking stop working until you sign in again.")
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task { @MainActor in
            defer { isDeletingAccount = false }
            do {
                try await backend.deleteAccount()
            } catch {
                // Silence here would look like nothing happened.
                deleteError = error.localizedDescription
            }
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
                if store.isSubscribed {
                    LabeledContent("Subscription") {
                        Label("Klowop Pro", systemImage: "sparkles").foregroundStyle(Theme.assistant)
                    }
                } else {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("Upgrade to Klowop Pro", systemImage: "sparkles")
                            .foregroundStyle(Theme.assistant)
                    }
                }
                if isRestoring {
                    HStack { Text("Restoring…").foregroundStyle(.secondary); Spacer(); ProgressView() }
                } else {
                    Button("Restore purchases") { restorePurchases() }
                }
                Button("Sign out") { showingSignOutConfirm = true }
                if isDeletingAccount {
                    HStack { Text("Deleting account…").foregroundStyle(.secondary); Spacer(); ProgressView() }
                } else {
                    Button("Delete account", role: .destructive) { showingDeleteConfirm = true }
                }
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

    private func restorePurchases() {
        isRestoring = true
        Task { @MainActor in
            await store.restore()
            isRestoring = false
            restoreMessage = store.isSubscribed
                ? "Your Klowop Pro subscription is active."
                : "No active subscription found for this Apple ID."
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
