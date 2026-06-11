import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            AgendaView()
                .tabItem { Label("Agenda", systemImage: "calendar") }
            NutritionView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
            FinancesView()
                .tabItem { Label("Money", systemImage: "creditcard.fill") }
            AssistantView()
                .tabItem { Label("Assistant", systemImage: "sparkles") }
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
