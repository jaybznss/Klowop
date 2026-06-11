import Foundation
import UserNotifications
import SwiftData
import Observation

/// Local reminders: 30 minutes before agenda events and the day before a
/// subscription renews. Rescheduled from current data whenever the app
/// goes to the background.
@Observable
final class NotificationService {
    static let shared = NotificationService()

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notifications_enabled") }
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
    }

    func requestAuthorization() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isEnabled = granted
    }

    /// Replaces all pending reminders with ones derived from current data.
    @MainActor
    func rescheduleAll(context: ModelContext) async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let now = Date.now
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        // Events: 30 minutes before start, next 7 days.
        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate > now && $0.startDate < horizon },
            sortBy: [SortDescriptor(\.startDate)]))) ?? []
        for event in events.prefix(40) {
            let fireDate = event.startDate.addingTimeInterval(-30 * 60)
            guard fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = "Starts at \(event.startDate.formatted(date: .omitted, time: .shortened))"
            + (event.location.map { " · \($0)" } ?? "")
            content.sound = .default
            schedule(content, at: fireDate, id: "event-\(event.persistentModelID.hashValue)")
        }

        // Subscriptions: 9 AM the day before renewal, next 7 days.
        let subscriptions = (try? context.fetch(FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.isActive && $0.nextRenewal > now && $0.nextRenewal < horizon }))) ?? []
        for sub in subscriptions.prefix(20) {
            let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: sub.nextRenewal)!
            guard let fireDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore),
                  fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(sub.name) renews tomorrow"
            content.body = "\(sub.amount.asCurrency()) per \(sub.billingCycle.replacingOccurrences(of: "ly", with: "")). Cancel it if you no longer use it."
            content.sound = .default
            schedule(content, at: fireDate, id: "sub-\(sub.persistentModelID.hashValue)")
        }
    }

    private func schedule(_ content: UNMutableNotificationContent, at date: Date, id: String) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
