import AppIntents
import SwiftData
import WidgetKit

/// Siri / Shortcuts / Spotlight actions. Each intent writes through the same
/// shared database the app and widget use.

struct AddTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a To-Do"
    static let description = IntentDescription("Adds an item to your Klowop to-do list.")

    @Parameter(title: "What needs to be done?")
    var title: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try AppGroup.makeModelContainer()
        container.mainContext.insert(TodoItem(title: title))
        try container.mainContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Added “\(title)” to your list.")
    }
}

struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Meal"
    static let description = IntentDescription("Logs something you ate, with estimated calories.")

    @Parameter(title: "What did you eat?")
    var name: String

    @Parameter(title: "Calories", default: 400)
    var calories: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let hour = Calendar.current.component(.hour, from: .now)
        let mealType: String = switch hour {
        case ..<11: "breakfast"
        case ..<15: "lunch"
        case ..<21: "dinner"
        default: "snack"
        }
        let meal = Meal(name: name, mealType: mealType, calories: calories)
        meal.healthKitUUID = await HealthKitService.shared.logMeal(
            name: name, calories: calories, protein: 0, carbs: 0, fat: 0, date: meal.date)
        let container = try AppGroup.makeModelContainer()
        container.mainContext.insert(meal)
        try container.mainContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged \(name), \(calories) calories, as \(mealType).")
    }
}

struct KlowopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTodoIntent(),
            phrases: [
                "Add a to-do in \(.applicationName)",
                "Remind me in \(.applicationName)",
            ],
            shortTitle: "Add To-Do",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log food in \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife"
        )
    }
}
