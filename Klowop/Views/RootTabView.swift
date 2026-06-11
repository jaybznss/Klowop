import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max.fill") {
                TodayView()
            }
            Tab("Agenda", systemImage: "calendar") {
                AgendaView()
            }
            Tab("Food", systemImage: "fork.knife") {
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
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Meal.self, CalendarEvent.self, TodoItem.self,
                              FinancialAccount.self, MoneyTransaction.self,
                              Subscription.self, ChatMessage.self],
                        inMemory: true)
}
