import Foundation

enum AppConfig {
    static let appGroupID = "group.com.kyreshamwell.pushed"
    static let keychainAccessGroup = "com.kyreshamwell.pushed.shared"
    static let keychainAccount = "github-pat"
    static let usernameDefaultsKey = "github-username"
    static let widgetWeeksKey = "widget-weeks" // how many weeks the widget displays

    static var widgetWeeks: Int {
        let stored = sharedDefaults.integer(forKey: widgetWeeksKey)
        return stored == 0 ? 26 : stored
    }

    static let streakIconKey = "streak-icon"
    static let streakIconChoices = ["🔥", "⚡", "🌱", "⭐", "none"]

    static var streakIcon: String {
        sharedDefaults.string(forKey: streakIconKey) ?? "🔥"
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
