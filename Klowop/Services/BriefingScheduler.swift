import Foundation
import BackgroundTasks
import UserNotifications
import SwiftData

/// Generates the daily briefing automatically via iOS background refresh:
/// the system wakes the app around the user's chosen hour, Claude writes the
/// briefing with full tool access, and it arrives as a notification. The text
/// is cached so the Today card shows it instantly on next open.
///
/// Note: BGAppRefresh timing is opportunistic — iOS runs it at or after the
/// requested time based on usage patterns, so the briefing can arrive a bit
/// late (or be skipped if the phone is off). The Today card's manual wand
/// always works as a fallback.
enum BriefingScheduler {
    static let taskID = "com.jaybznss.klowop.briefing"

    static let prompt = """
        Write my daily briefing. First use tools to check: today's calendar events, \
        my open to-dos, today's nutrition so far, my Apple Health activity if connected, \
        and any subscriptions renewing in the next 7 days. \
        Then write a friendly, skimmable briefing under 120 words — lead with the most \
        important thing, use short bullet points, and end with one practical suggestion.
        """

    // MARK: - Cache (read by TodayView)

    static var cachedBriefingForToday: String? {
        let timestamp = UserDefaults.standard.double(forKey: "cached_briefing_date")
        guard timestamp > 0,
              Calendar.current.isDateInToday(Date(timeIntervalSince1970: timestamp)) else { return nil }
        return UserDefaults.standard.string(forKey: "cached_briefing_text")
    }

    static func cache(_ text: String) {
        UserDefaults.standard.set(text, forKey: "cached_briefing_text")
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "cached_briefing_date")
    }

    // MARK: - Scheduling

    /// Asks iOS to wake us no earlier than the next occurrence of the chosen hour.
    static func scheduleNext() {
        guard AppSettings.shared.autoBriefingEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = nextFireDate()
        try? BGTaskScheduler.shared.submit(request)
    }

    static func nextFireDate() -> Date {
        let hour = AppSettings.shared.briefingHour
        let today = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        return today > .now ? today : Calendar.current.date(byAdding: .day, value: 1, to: today)!
    }

    // MARK: - Execution (called from the background task)

    @MainActor
    static func runNow() async {
        defer { scheduleNext() }
        guard AppSettings.shared.autoBriefingEnabled,
              BackendService.shared.isSignedIn else { return }
        do {
            let container = try AppGroup.makeModelContainer()
            let text = try await ClaudeAssistantService.shared.oneShot(
                prompt, context: container.mainContext)
            guard !text.isEmpty else { return }
            cache(text)

            let content = UNMutableNotificationContent()
            content.title = "☀️ Your daily briefing"
            content.body = String(text.prefix(1800))
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "daily-briefing", content: content, trigger: nil))
        } catch {
            // Background window may have closed or network failed — try again tomorrow.
        }
    }
}
