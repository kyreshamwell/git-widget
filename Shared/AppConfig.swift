import Foundation

enum AppConfig {
    static let appGroupID = "group.com.kyreshamwell.gitstreak"
    static let keychainAccessGroup = "com.kyreshamwell.gitstreak.shared"
    static let keychainAccount = "github-pat"
    static let usernameDefaultsKey = "github-username"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
