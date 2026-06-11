import SwiftUI
import SwiftData

@main
struct KlowopApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                Meal.self,
                CalendarEvent.self,
                TodoItem.self,
                FinancialAccount.self,
                MoneyTransaction.self,
                Subscription.self,
                ChatMessage.self
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
