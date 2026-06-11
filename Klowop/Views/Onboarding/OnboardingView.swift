import SwiftUI

/// First-launch walkthrough: what the app does, who you are, and permissions.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var settings = AppSettings.shared
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            features.tag(1)
            profile.tag(2)
            permissions.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(colors: [.indigo, .purple],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Welcome to Klowop")
                .font(.largeTitle.weight(.bold))
            Text("One place for your whole life — schedule, food, money, and a secretary who actually does things.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
            nextButton("Get started")
        }
        .padding(.bottom, 60)
    }

    private var features: some View {
        VStack(spacing: 18) {
            Spacer()
            featureRow("calendar", Theme.agenda, "Agenda",
                       "Two-way sync with your Google Calendar.")
            featureRow("fork.knife", Theme.nutrition, "Food",
                       "Log meals; your Apple Watch and smart scale fill in the rest.")
            featureRow("creditcard.fill", Theme.finance, "Money",
                       "Bank accounts, transactions, and subscription tracking via Plaid.")
            featureRow("sparkles", Theme.assistant, "Assistant",
                       "Talk to it like a secretary — it schedules, logs, and answers.")
            Spacer()
            nextButton("Next")
        }
        .padding(.bottom, 60)
    }

    private func featureRow(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var profile: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("About you")
                .font(.largeTitle.weight(.bold))
            Text("So your secretary knows who it's working for.")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(spacing: 14) {
                TextField("Your first name", text: $settings.userName)
                    .textFieldStyle(.roundedBorder)
                Stepper("Daily calorie goal: \(settings.dailyCalorieGoal)",
                        value: $settings.dailyCalorieGoal, in: 1000...5000, step: 50)
            }
            .padding(.horizontal, 36)
            Spacer()
            nextButton("Next")
        }
        .padding(.bottom, 60)
    }

    private var permissions: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Stay ahead")
                .font(.largeTitle.weight(.bold))
            Text("Klowop can remind you before events start and before subscriptions renew. You can change this anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task {
                        await NotificationService.shared.requestAuthorization()
                        finish()
                    }
                } label: {
                    Text("Enable reminders")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.assistant)
                Button("Not now") { finish() }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
        }
        .padding(.bottom, 60)
    }

    private func nextButton(_ label: String) -> some View {
        Button {
            withAnimation { page += 1 }
        } label: {
            Text(label).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.assistant)
        .padding(.horizontal, 36)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "has_onboarded")
        isPresented = false
    }
}
