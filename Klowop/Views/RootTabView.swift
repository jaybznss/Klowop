import SwiftUI

enum AppTab: Hashable {
    case today, agenda, health, money, assistant
}

/// App-wide tab selection, so any screen (dashboard tiles, empty-state CTAs,
/// assistant actions) can deep-link into a tab.
@Observable
final class TabRouter {
    static let shared = TabRouter()
    var selection: AppTab = .today
}

struct RootTabView: View {
    @State private var router = TabRouter.shared
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "has_onboarded")

    var body: some View {
        TabView(selection: $router.selection) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Agenda", systemImage: "calendar", value: AppTab.agenda) {
                AgendaView()
            }
            Tab("Health", systemImage: "heart.fill", value: AppTab.health) {
                NutritionView()
            }
            Tab("Money", systemImage: "creditcard.fill", value: AppTab.money) {
                FinancesView()
            }
            Tab("Assistant", systemImage: "sparkles", value: AppTab.assistant) {
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
                              Subscription.self, Budget.self, FavoriteFood.self,
                              ChatMessage.self],
                        inMemory: true)
}
