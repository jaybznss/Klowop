import Foundation
import Observation

/// App-wide configuration. Secrets live in the Keychain, preferences in UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var anthropicAPIKey: String {
        didSet { KeychainHelper.set(anthropicAPIKey, for: "anthropic_api_key") }
    }
    var googleClientID: String {
        didSet { UserDefaults.standard.set(googleClientID, forKey: "google_client_id") }
    }
    var plaidServerURL: String {
        didSet { UserDefaults.standard.set(plaidServerURL, forKey: "plaid_server_url") }
    }
    var dailyCalorieGoal: Int {
        didSet { UserDefaults.standard.set(dailyCalorieGoal, forKey: "daily_calorie_goal") }
    }
    var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: "user_name") }
    }

    private init() {
        anthropicAPIKey = KeychainHelper.get("anthropic_api_key") ?? ""
        googleClientID = UserDefaults.standard.string(forKey: "google_client_id") ?? ""
        plaidServerURL = UserDefaults.standard.string(forKey: "plaid_server_url") ?? "http://localhost:8484"
        let goal = UserDefaults.standard.integer(forKey: "daily_calorie_goal")
        dailyCalorieGoal = goal == 0 ? 2200 : goal
        userName = UserDefaults.standard.string(forKey: "user_name") ?? ""
    }
}
