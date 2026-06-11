import SwiftUI

struct RootTabView: View {
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "has_onboarded")

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max.fill") {
                TodayView()
            }
            Tab("Agenda", systemImage: "calendar") {
                AgendaView()
            }
            Tab("Health", systemImage: "heart.fill") {
                NutritionView()
            }
            Tab("Money", systemImage: "creditcard.fill") {
                FinancesView()
            }
            Tab("Assistant", systemImage: "sparkles") {
                AssistantView()
            }
        }
        // Liquid Glass: let the floating tab bar shrink away while scrolling content.
        .tabBarMinimizeBehavior(.onScrollDown)
        // One brand accent across navigation, toggles, and controls.
        .tint(Theme.assistant)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Meal.self, CalendarEvent.self, TodoItem.self,
                              FinancialAccount.self, MoneyTransaction.self,
                              Subscription.self, ChatMessage.self],
                        inMemory: true)
}
