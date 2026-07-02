import Foundation
import Observation

/// App-wide configuration. Secrets live in the Keychain, preferences in UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: "backend_url") }
    }
    var googleClientID: String {
        didSet { UserDefaults.standard.set(googleClientID, forKey: "google_client_id") }
    }
    var plaidServerURL: String {
        didSet { UserDefaults.standard.set(plaidServerURL, forKey: "plaid_server_url") }
    }
    var dailyCalorieGoal: Int {
        didSet {
            UserDefaults.standard.set(dailyCalorieGoal, forKey: "daily_calorie_goal")
            // Mirrored to the app group so the widget can show the same goal.
            UserDefaults(suiteName: AppGroup.id)?.set(dailyCalorieGoal, forKey: "daily_calorie_goal")
        }
    }
    var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: "user_name") }
    }
    var autoBriefingEnabled: Bool {
        didSet { UserDefaults.standard.set(autoBriefingEnabled, forKey: "auto_briefing_enabled") }
    }
    var briefingHour: Int {
        didSet { UserDefaults.standard.set(briefingHour, forKey: "briefing_hour") }
    }
    var usdaAPIKey: String {
        didSet { UserDefaults.standard.set(usdaAPIKey, forKey: "usda_api_key") }
    }

    private init() {
        backendURL = UserDefaults.standard.string(forKey: "backend_url")
            ?? "https://klowop-production.up.railway.app"
        // The iOS OAuth client ID is public by design (PKCE, no secret) — bake it
        // in so users never have to type developer configuration.
        let storedClientID = UserDefaults.standard.string(forKey: "google_client_id") ?? ""
        googleClientID = storedClientID.isEmpty
            ? "467064468765-di6kj8ltouoh029l5c2me3mfij2gr035.apps.googleusercontent.com"
            : storedClientID
        plaidServerURL = UserDefaults.standard.string(forKey: "plaid_server_url") ?? "http://localhost:8484"
        let goal = UserDefaults.standard.integer(forKey: "daily_calorie_goal")
        dailyCalorieGoal = goal == 0 ? 2200 : goal
        userName = UserDefaults.standard.string(forKey: "user_name") ?? ""
        usdaAPIKey = UserDefaults.standard.string(forKey: "usda_api_key") ?? ""
        autoBriefingEnabled = UserDefaults.standard.bool(forKey: "auto_briefing_enabled")
        let hour = UserDefaults.standard.integer(forKey: "briefing_hour")
        briefingHour = hour == 0 ? 8 : hour
    }
}
