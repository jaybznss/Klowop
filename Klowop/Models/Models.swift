import Foundation
import SwiftData

/// Shared between the app and the widget extension so both read the same database.
enum AppGroup {
    static let id = "group.com.jaybznss.klowop"

    static var schema: Schema {
        Schema([Meal.self, CalendarEvent.self, TodoItem.self, FinancialAccount.self,
                MoneyTransaction.self, Subscription.self, ChatMessage.self])
    }

    static func makeModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("Klowop", schema: schema,
                                               groupContainer: .identifier(id))
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - Nutrition

@Model
final class Meal {
    var name: String
    var mealType: String        // breakfast, lunch, dinner, snack
    var calories: Int
    var protein: Double         // grams
    var carbs: Double           // grams
    var fat: Double             // grams
    var date: Date
    var notes: String?
    var healthKitUUID: String?   // links the meal to its Apple Health samples

    init(name: String, mealType: String, calories: Int,
         protein: Double = 0, carbs: Double = 0, fat: Double = 0,
         date: Date = .now, notes: String? = nil) {
        self.name = name
        self.mealType = mealType
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.date = date
        self.notes = notes
    }
}

// MARK: - Agenda

@Model
final class CalendarEvent {
    var title: String
    var startDate: Date
    var endDate: Date
    var location: String?
    var notes: String?
    var googleEventID: String?
    var needsGoogleSync: Bool

    init(title: String, startDate: Date, endDate: Date,
         location: String? = nil, notes: String? = nil,
         googleEventID: String? = nil, needsGoogleSync: Bool = true) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.googleEventID = googleEventID
        self.needsGoogleSync = needsGoogleSync
    }
}

// MARK: - Todos

@Model
final class TodoItem {
    var title: String
    var listName: String        // e.g. "Inbox", "Groceries", "Work"
    var isDone: Bool
    var dueDate: Date?
    var createdAt: Date

    init(title: String, listName: String = "Inbox", isDone: Bool = false,
         dueDate: Date? = nil, createdAt: Date = .now) {
        self.title = title
        self.listName = listName
        self.isDone = isDone
        self.dueDate = dueDate
        self.createdAt = createdAt
    }
}

// MARK: - Finances

@Model
final class FinancialAccount {
    var name: String
    var institution: String
    var type: String            // checking, savings, credit, investment, other
    var balance: Double
    var currencyCode: String
    var plaidAccountID: String?

    init(name: String, institution: String, type: String,
         balance: Double, currencyCode: String = "USD", plaidAccountID: String? = nil) {
        self.name = name
        self.institution = institution
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
        self.plaidAccountID = plaidAccountID
    }
}

@Model
final class MoneyTransaction {
    var merchant: String
    var amount: Double          // positive = money out, negative = money in
    var date: Date
    var category: String
    var accountName: String
    var plaidTransactionID: String?

    init(merchant: String, amount: Double, date: Date, category: String,
         accountName: String, plaidTransactionID: String? = nil) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.category = category
        self.accountName = accountName
        self.plaidTransactionID = plaidTransactionID
    }
}

@Model
final class Subscription {
    var name: String
    var amount: Double
    var billingCycle: String    // weekly, monthly, yearly
    var nextRenewal: Date
    var accountName: String
    var isActive: Bool
    var plaidStreamID: String?

    init(name: String, amount: Double, billingCycle: String, nextRenewal: Date,
         accountName: String = "", isActive: Bool = true, plaidStreamID: String? = nil) {
        self.name = name
        self.amount = amount
        self.billingCycle = billingCycle
        self.nextRenewal = nextRenewal
        self.accountName = accountName
        self.isActive = isActive
        self.plaidStreamID = plaidStreamID
    }

    var monthlyEquivalent: Double {
        switch billingCycle {
        case "weekly": return amount * 52 / 12
        case "yearly": return amount / 12
        default: return amount
        }
    }
}

// MARK: - Assistant chat

@Model
final class ChatMessage {
    var role: String            // "user" or "assistant"
    var text: String
    var date: Date

    init(role: String, text: String, date: Date = .now) {
        self.role = role
        self.text = text
        self.date = date
    }
}
