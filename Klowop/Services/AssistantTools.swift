import Foundation
import SwiftData

/// Tool definitions exposed to Claude, and their execution against local data.
/// Tool inputs/outputs are plain JSON dictionaries to match the Messages API wire format.
enum AssistantTools {

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return isoFormatter.date(from: s)
    }

    // MARK: - Definitions sent in the `tools` array

    static var definitions: [[String: Any]] {
        [
            tool("add_calendar_event",
                 "Add an event to the user's agenda. Call this whenever the user asks to schedule, book, or plan something at a specific time.",
                 properties: [
                    "title": str("Event title"),
                    "start": str("Start date-time in ISO 8601 with timezone offset, e.g. 2026-06-12T15:00:00+02:00"),
                    "end": str("End date-time in ISO 8601 with timezone offset. If the user gives no duration, use one hour."),
                    "location": str("Location (optional)"),
                    "notes": str("Notes (optional)"),
                 ],
                 required: ["title", "start", "end"]),

            tool("list_calendar_events",
                 "List agenda events between two dates. Call this when the user asks what's on their schedule.",
                 properties: [
                    "from": str("Range start, ISO 8601 with timezone offset"),
                    "to": str("Range end, ISO 8601 with timezone offset"),
                 ],
                 required: ["from", "to"]),

            tool("delete_calendar_event",
                 "Delete agenda events by title (case-insensitive contains match), optionally limited to one day. Use this to remove duplicates or cancelled plans. Synced Google Calendar copies are removed too.",
                 properties: [
                    "title": str("Title (or part of it) of the event(s) to delete"),
                    "date": str("Optional: only delete events on this day, ISO 8601"),
                 ],
                 required: ["title"]),

            tool("add_todo",
                 "Add an item to the user's to-do lists. Call this when the user asks to remember, buy, or do something without a fixed time.",
                 properties: [
                    "title": str("What needs to be done"),
                    "list": str("List name, e.g. Inbox, Groceries, Work. Default Inbox."),
                    "due": str("Optional due date-time, ISO 8601 with timezone offset"),
                 ],
                 required: ["title"]),

            tool("complete_todo",
                 "Mark a to-do item as done by its title (case-insensitive match).",
                 properties: ["title": str("Title of the item to complete")],
                 required: ["title"]),

            tool("list_todos",
                 "List the user's open to-do items, grouped by list.",
                 properties: ["include_done": ["type": "boolean", "description": "Also include completed items"]],
                 required: []),

            tool("log_meal",
                 "Log something the user ate or drank. Call this whenever the user mentions eating. Estimate calories and macros yourself if the user doesn't give them.",
                 properties: [
                    "name": str("What was eaten, e.g. 'Chicken caesar salad'"),
                    "meal_type": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"], "description": "Which meal"],
                    "calories": ["type": "integer", "description": "Estimated calories"],
                    "protein": ["type": "number", "description": "Protein in grams (optional)"],
                    "carbs": ["type": "number", "description": "Carbs in grams (optional)"],
                    "fat": ["type": "number", "description": "Fat in grams (optional)"],
                    "date": str("When it was eaten, ISO 8601 with timezone offset. Omit for now."),
                 ],
                 required: ["name", "meal_type", "calories"]),

            tool("get_nutrition_summary",
                 "Get calories and macros logged for a given day. Call this when the user asks how their eating is going.",
                 properties: ["date": str("Day to summarize, ISO 8601. Omit for today.")],
                 required: []),

            tool("get_finance_overview",
                 "Get account balances, recent transactions, and active subscriptions. Call this when the user asks about money, spending, or subscriptions.",
                 properties: [:],
                 required: []),

            tool("add_subscription",
                 "Track a new recurring subscription the user mentions (e.g. they signed up for Netflix).",
                 properties: [
                    "name": str("Service name, e.g. Netflix"),
                    "amount": ["type": "number", "description": "Cost per billing cycle"],
                    "cycle": ["type": "string", "enum": ["weekly", "monthly", "yearly"], "description": "Billing cycle"],
                    "next_renewal": str("Next renewal date, ISO 8601"),
                 ],
                 required: ["name", "amount", "cycle", "next_renewal"]),

            tool("cancel_subscription",
                 "Mark a tracked subscription as cancelled (stops renewal reminders). Use when the user says they cancelled a service.",
                 properties: ["name": str("Subscription name (case-insensitive match)")],
                 required: ["name"]),

            tool("search_transactions",
                 "Search transactions by merchant or category text. Call this for questions like 'how much did I spend at Amazon' or 'show my restaurant spending'.",
                 properties: [
                    "query": str("Text to match against merchant and category"),
                    "days": ["type": "integer", "description": "How many days back to search. Default 30."],
                 ],
                 required: ["query"]),

            tool("get_spending_summary",
                 "Total spending grouped by category over a period. Call this for 'where does my money go' style questions.",
                 properties: ["days": ["type": "integer", "description": "How many days back. Default 30."]],
                 required: []),

            tool("set_budget",
                 "Create or update a monthly spending budget for a category. Use the user's existing transaction categories when possible (get_spending_summary shows them).",
                 properties: [
                    "category": str("Spending category, e.g. Food And Drink"),
                    "monthly_limit": ["type": "number", "description": "Monthly limit in the user's currency"],
                 ],
                 required: ["category", "monthly_limit"]),

            tool("get_budget_status",
                 "Check all budgets: limit, spent so far this month, and remaining. Call this when the user asks how their budgets are doing or whether they can afford something.",
                 properties: [:],
                 required: []),

            tool("get_health_summary",
                 "Get Apple Health data: today's Apple Watch activity (active calories burned, steps, exercise minutes) and the latest body composition (weight, body fat, lean mass from a smart scale). Call this when the user asks about workouts, calories burned, weight, or body composition.",
                 properties: ["date": str("Day for the activity numbers, ISO 8601. Omit for today.")],
                 required: []),
        ]
    }

    private static func str(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func tool(_ name: String, _ description: String,
                             properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": required,
            ] as [String: Any],
        ]
    }

    // MARK: - Execution

    @MainActor
    static func execute(name: String, input: [String: Any], context: ModelContext) async -> String {
        do {
            switch name {
            case "add_calendar_event": return try addCalendarEvent(input, context)
            case "list_calendar_events": return try listCalendarEvents(input, context)
            case "delete_calendar_event": return try await deleteCalendarEvent(input, context)
            case "add_todo": return try addTodo(input, context)
            case "complete_todo": return try completeTodo(input, context)
            case "list_todos": return try listTodos(input, context)
            case "log_meal": return try await logMeal(input, context)
            case "get_nutrition_summary": return try nutritionSummary(input, context)
            case "get_finance_overview": return try financeOverview(context)
            case "add_subscription": return try addSubscription(input, context)
            case "cancel_subscription": return try cancelSubscription(input, context)
            case "search_transactions": return try searchTransactions(input, context)
            case "get_spending_summary": return try spendingSummary(input, context)
            case "set_budget": return try setBudget(input, context)
            case "get_budget_status": return try budgetStatus(context)
            case "get_health_summary": return await healthSummary(input)
            default: return "Error: unknown tool \(name)"
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    @MainActor
    private static func addCalendarEvent(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let title = input["title"] as? String,
              let start = parseDate(input["start"]),
              let end = parseDate(input["end"]) else {
            return "Error: title, start and end (ISO 8601) are required."
        }
        let event = CalendarEvent(title: title, startDate: start, endDate: end,
                                  location: input["location"] as? String,
                                  notes: input["notes"] as? String)
        context.insert(event)
        try context.save()
        return "Created event '\(title)' on \(start.formatted(date: .abbreviated, time: .shortened)). It will sync to Google Calendar on the next sync."
    }

    @MainActor
    private static func listCalendarEvents(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let from = parseDate(input["from"]), let to = parseDate(input["to"]) else {
            return "Error: from and to (ISO 8601) are required."
        }
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= from && $0.startDate <= to },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let events = try context.fetch(descriptor)
        if events.isEmpty { return "No events between \(from.formatted()) and \(to.formatted())." }
        return events.map {
            "- \($0.title): \($0.startDate.formatted(date: .abbreviated, time: .shortened)) to \($0.endDate.formatted(date: .omitted, time: .shortened))\($0.location.map { " at \($0)" } ?? "")"
        }.joined(separator: "\n")
    }

    @MainActor
    private static func deleteCalendarEvent(_ input: [String: Any], _ context: ModelContext) async throws -> String {
        guard let title = (input["title"] as? String)?.lowercased(), !title.isEmpty else {
            return "Error: title is required."
        }
        var matches = try context.fetch(FetchDescriptor<CalendarEvent>())
            .filter { $0.title.lowercased().contains(title) }
        if let day = parseDate(input["date"]) {
            let start = Calendar.current.startOfDay(for: day)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            matches = matches.filter { $0.startDate >= start && $0.startDate < end }
        }
        guard !matches.isEmpty else { return "No events matching '\(title)'." }

        var deleted: [String] = []
        for event in matches {
            if let googleID = event.googleEventID {
                await GoogleCalendarService.shared.deleteRemoteEvent(id: googleID)
            }
            deleted.append("\(event.title) — \(event.startDate.formatted(date: .abbreviated, time: .shortened))")
            context.delete(event)
        }
        try context.save()
        return "Deleted \(deleted.count) event(s):\n" + deleted.map { "- \($0)" }.joined(separator: "\n")
    }

    @MainActor
    private static func addTodo(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let title = input["title"] as? String else { return "Error: title is required." }
        let item = TodoItem(title: title,
                            listName: (input["list"] as? String) ?? "Inbox",
                            dueDate: parseDate(input["due"]))
        context.insert(item)
        try context.save()
        return "Added '\(title)' to the \(item.listName) list."
    }

    @MainActor
    private static func completeTodo(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let title = (input["title"] as? String)?.lowercased() else { return "Error: title is required." }
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isDone })
        let open = try context.fetch(descriptor)
        guard let match = open.first(where: { $0.title.lowercased().contains(title) }) else {
            return "No open to-do matching '\(title)'. Open items: \(open.map(\.title).joined(separator: ", "))"
        }
        match.isDone = true
        try context.save()
        return "Marked '\(match.title)' as done."
    }

    @MainActor
    private static func listTodos(_ input: [String: Any], _ context: ModelContext) throws -> String {
        let includeDone = (input["include_done"] as? Bool) ?? false
        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.createdAt)])
        let items = try context.fetch(descriptor).filter { includeDone || !$0.isDone }
        if items.isEmpty { return "No open to-dos. 🎉" }
        let grouped = Dictionary(grouping: items, by: \.listName)
        return grouped.keys.sorted().map { list in
            let lines = grouped[list]!.map { item in
                "  \(item.isDone ? "[x]" : "[ ]") \(item.title)\(item.dueDate.map { " (due \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? "")"
            }.joined(separator: "\n")
            return "\(list):\n\(lines)"
        }.joined(separator: "\n")
    }

    @MainActor
    private static func logMeal(_ input: [String: Any], _ context: ModelContext) async throws -> String {
        guard let name = input["name"] as? String,
              let mealType = input["meal_type"] as? String,
              let calories = input["calories"] as? Int else {
            return "Error: name, meal_type and calories are required."
        }
        let meal = Meal(name: name, mealType: mealType, calories: calories,
                        protein: (input["protein"] as? Double) ?? 0,
                        carbs: (input["carbs"] as? Double) ?? 0,
                        fat: (input["fat"] as? Double) ?? 0,
                        date: parseDate(input["date"]) ?? .now)
        meal.healthKitUUID = await HealthKitService.shared.logMeal(
            name: name, calories: calories, protein: meal.protein,
            carbs: meal.carbs, fat: meal.fat, date: meal.date)
        context.insert(meal)
        try context.save()
        let healthNote = meal.healthKitUUID != nil ? " Saved to Apple Health too." : ""
        return "Logged \(name) (\(calories) kcal) as \(mealType).\(healthNote)"
    }

    @MainActor
    private static func addSubscription(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let name = input["name"] as? String,
              let amount = input["amount"] as? Double,
              let cycle = input["cycle"] as? String,
              let renewal = parseDate(input["next_renewal"]) else {
            return "Error: name, amount, cycle and next_renewal (ISO 8601) are required."
        }
        context.insert(Subscription(name: name, amount: amount, billingCycle: cycle, nextRenewal: renewal))
        try context.save()
        return "Now tracking \(name): \(amount.asCurrency())/\(cycle), next renewal \(renewal.formatted(date: .abbreviated, time: .omitted))."
    }

    @MainActor
    private static func cancelSubscription(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let name = (input["name"] as? String)?.lowercased() else { return "Error: name is required." }
        let active = try context.fetch(FetchDescriptor<Subscription>(predicate: #Predicate { $0.isActive }))
        guard let match = active.first(where: { $0.name.lowercased().contains(name) }) else {
            return "No active subscription matching '\(name)'. Active: \(active.map(\.name).joined(separator: ", "))"
        }
        match.isActive = false
        try context.save()
        return "Marked \(match.name) as cancelled — that frees up \(match.monthlyEquivalent.asCurrency()) per month."
    }

    @MainActor
    private static func searchTransactions(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let query = (input["query"] as? String)?.lowercased() else { return "Error: query is required." }
        let days = (input["days"] as? Int) ?? 30
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let matches = try context.fetch(FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]))
            .filter { $0.merchant.lowercased().contains(query) || $0.category.lowercased().contains(query) }
        guard !matches.isEmpty else { return "No transactions matching '\(query)' in the last \(days) days." }
        let total = matches.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        let lines = matches.prefix(20).map {
            "- \($0.date.formatted(date: .abbreviated, time: .omitted)) \($0.merchant): \($0.amount.asCurrency()) [\($0.category)]"
        }.joined(separator: "\n")
        return "\(matches.count) matches, \(total.asCurrency()) spent in the last \(days) days:\n\(lines)"
    }

    @MainActor
    private static func spendingSummary(_ input: [String: Any], _ context: ModelContext) throws -> String {
        let days = (input["days"] as? Int) ?? 30
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let spent = try context.fetch(FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.date >= cutoff && $0.amount > 0 }))
        guard !spent.isEmpty else { return "No spending recorded in the last \(days) days." }
        let byCategory = Dictionary(grouping: spent, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
            .sorted { $0.value > $1.value }
        let total = spent.reduce(0) { $0 + $1.amount }
        let lines = byCategory.map { "- \($0.key): \($0.value.asCurrency())" }.joined(separator: "\n")
        return "Spending last \(days) days — total \(total.asCurrency()):\n\(lines)"
    }

    @MainActor
    private static func setBudget(_ input: [String: Any], _ context: ModelContext) throws -> String {
        guard let category = input["category"] as? String,
              let limit = input["monthly_limit"] as? Double else {
            return "Error: category and monthly_limit are required."
        }
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        if let existing = budgets.first(where: { $0.category.lowercased() == category.lowercased() }) {
            existing.monthlyLimit = limit
            try context.save()
            return "Updated the \(existing.category) budget to \(limit.asCurrency())/month."
        }
        context.insert(Budget(category: category, monthlyLimit: limit))
        try context.save()
        return "Set a \(limit.asCurrency())/month budget for \(category)."
    }

    @MainActor
    private static func budgetStatus(_ context: ModelContext) throws -> String {
        let budgets = try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.category)]))
        guard !budgets.isEmpty else { return "No budgets set yet. Offer to create some based on spending." }
        guard let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start else {
            return "Error: could not compute the current month."
        }
        let spentTx = try context.fetch(FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.date >= monthStart && $0.amount > 0 }))
        return budgets.map { budget in
            let spent = spentTx
                .filter { $0.category.lowercased() == budget.category.lowercased() }
                .reduce(0) { $0 + $1.amount }
            let remaining = budget.monthlyLimit - spent
            let state = remaining < 0 ? "OVER by \((-remaining).asCurrency())" : "\(remaining.asCurrency()) left"
            return "- \(budget.category): \(spent.asCurrency()) of \(budget.monthlyLimit.asCurrency()) (\(state))"
        }.joined(separator: "\n")
    }

    @MainActor
    private static func healthSummary(_ input: [String: Any]) async -> String {
        let health = HealthKitService.shared
        guard health.isEnabled else {
            return "Apple Health isn't connected yet. The user can connect it in Settings → Apple Health."
        }
        await health.refresh(day: parseDate(input["date"]) ?? .now)
        var out = "Activity:\n"
        if let activity = health.activity {
            out += "  - Active energy burned: \(Int(activity.activeEnergy)) kcal\n"
            out += "  - Steps: \(Int(activity.steps))\n"
            out += "  - Exercise: \(Int(activity.exerciseMinutes)) min\n"
        } else {
            out += "  (no activity data)\n"
        }
        out += "Body composition (latest measurements):\n"
        let body = health.bodyComposition
        if body.isEmpty {
            out += "  (no body data — a smart scale like the Hume BodyPod syncs this via Apple Health)"
        } else {
            if let weight = body.weightKg {
                out += "  - Weight: \(String(format: "%.1f", weight.value)) kg (\(weight.date.formatted(date: .abbreviated, time: .omitted)))\n"
            }
            if let fat = body.bodyFatFraction {
                out += "  - Body fat: \(String(format: "%.1f", fat.value * 100))% (\(fat.date.formatted(date: .abbreviated, time: .omitted)))\n"
            }
            if let lean = body.leanMassKg {
                out += "  - Lean mass: \(String(format: "%.1f", lean.value)) kg (\(lean.date.formatted(date: .abbreviated, time: .omitted)))"
            }
        }
        return out
    }

    @MainActor
    private static func nutritionSummary(_ input: [String: Any], _ context: ModelContext) throws -> String {
        let day = parseDate(input["date"]) ?? .now
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        let meals = try context.fetch(descriptor)
        if meals.isEmpty { return "Nothing logged on \(start.formatted(date: .abbreviated, time: .omitted))." }
        let calories = meals.reduce(0) { $0 + $1.calories }
        let protein = meals.reduce(0.0) { $0 + $1.protein }
        let carbs = meals.reduce(0.0) { $0 + $1.carbs }
        let fat = meals.reduce(0.0) { $0 + $1.fat }
        let goal = AppSettings.shared.dailyCalorieGoal
        let list = meals.map { "- \($0.mealType): \($0.name) (\($0.calories) kcal)" }.joined(separator: "\n")
        return "Total: \(calories)/\(goal) kcal, protein \(Int(protein))g, carbs \(Int(carbs))g, fat \(Int(fat))g.\n\(list)"
    }

    @MainActor
    private static func financeOverview(_ context: ModelContext) throws -> String {
        let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
        var txDescriptor = FetchDescriptor<MoneyTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        txDescriptor.fetchLimit = 15
        let transactions = try context.fetch(txDescriptor)
        let subs = try context.fetch(FetchDescriptor<Subscription>(predicate: #Predicate { $0.isActive }))

        var out = "Accounts:\n"
        out += accounts.isEmpty ? "  (none linked yet)\n"
            : accounts.map { "  - \($0.name) (\($0.institution), \($0.type)): \($0.balance.asCurrency($0.currencyCode))" }.joined(separator: "\n") + "\n"
        out += "Recent transactions:\n"
        out += transactions.isEmpty ? "  (none)\n"
            : transactions.map { "  - \($0.date.formatted(date: .abbreviated, time: .omitted)) \($0.merchant): \($0.amount.asCurrency()) [\($0.category)]" }.joined(separator: "\n") + "\n"
        out += "Active subscriptions:\n"
        out += subs.isEmpty ? "  (none)"
            : subs.map { "  - \($0.name): \($0.amount.asCurrency())/\($0.billingCycle), next renewal \($0.nextRenewal.formatted(date: .abbreviated, time: .omitted))" }.joined(separator: "\n")
        let monthlyTotal = subs.reduce(0.0) { $0 + $1.monthlyEquivalent }
        out += "\nSubscriptions cost ≈ \(monthlyTotal.asCurrency()) per month."
        return out
    }
}
