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

    /// Any single emoji, or `StreakIcon.none` for the bare number.
    static var streakIcon: String {
        get { StreakIcon.sanitized(sharedDefaults.string(forKey: streakIconKey)) }
        set { sharedDefaults.set(newValue, forKey: streakIconKey) }
    }

    /// Where the one custom style lived before there was a library. Only
    /// read now, to carry that design over.
    static let customStyleKey = "custom-widget-style"
    static let styleLibraryKey = "widget-style-library"

    /// The saved custom styles, shared with the widget.
    static var styleLibrary: StyleLibrary {
        get {
            if let data = sharedDefaults.data(forKey: styleLibraryKey),
               let library = try? JSONDecoder().decode(StyleLibrary.self, from: data),
               !library.styles.isEmpty {
                return library
            }
            let earlier = sharedDefaults.data(forKey: customStyleKey)
                .flatMap { try? JSONDecoder().decode(CustomWidgetStyle.self, from: $0) }
            return .starting(with: earlier ?? .default)
        }
        set { sharedDefaults.set(try? JSONEncoder().encode(newValue), forKey: styleLibraryKey) }
    }

    static let dayOffMarkKey = "day-off-mark"

    /// How rest days and freezes are marked, in the app and every widget.
    static var dayOffMark: DayOffMark {
        get { sharedDefaults.string(forKey: dayOffMarkKey).flatMap(DayOffMark.init) ?? .stripes }
        set { sharedDefaults.set(newValue.rawValue, forKey: dayOffMarkKey) }
    }

    static let streakProtectionKey = "streak-protection"

    /// Rest days and freezes. Shared, because the widget and the reminders
    /// work the streak out from it as well.
    static var streakProtection: StreakProtection {
        get {
            sharedDefaults.data(forKey: streakProtectionKey)
                .flatMap { try? JSONDecoder().decode(StreakProtection.self, from: $0) }
                ?? .initial
        }
        set { sharedDefaults.set(try? JSONEncoder().encode(newValue), forKey: streakProtectionKey) }
    }

    /// Claimed days and the day tracking began belong to one account's
    /// history. The chosen weekdays are a habit of the person holding the
    /// phone, so those stay.
    static func forgetAccountHistory() {
        var protection = streakProtection
        protection.claims = [:]
        protection.trackedSince = nil
        streakProtection = protection
    }

    /// Marks today as the day Pushed started watching this account.
    static func startTracking(on day: Date = Date()) {
        var protection = streakProtection
        protection.trackedSince = StreakProtection.key(day)
        streakProtection = protection
    }

    /// Accounts connected before there was a start date have none saved. The
    /// day the app was installed is the closest thing on record: its
    /// Documents folder is made then. App only; the widget has its own.
    static func backfillTrackingStart() {
        guard streakProtection.trackedSince == nil,
              let username = sharedDefaults.string(forKey: usernameDefaultsKey), !username.isEmpty
        else { return }
        let installed = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ))
        .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.creationDate] as? Date }
        startTracking(on: installed ?? Date())
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: - Notifications
    //
    // Lives in the shared container because the widget extension reconciles
    // notifications too — its timeline refresh is the background hook that
    // cancels a nudge once you've actually pushed.

    enum Keys {
        static let notificationsEnabled = "notifications-enabled"
        static let middayHour = "notif-midday-hour"
        static let middayMinute = "notif-midday-minute"
        static let eveningHour = "notif-evening-hour"
        static let eveningMinute = "notif-evening-minute"
        static let milestonesEnabled = "notif-milestones-enabled"
        static let tokenAlertsEnabled = "notif-token-alerts-enabled"
        static let lastCelebratedStreak = "last-celebrated-streak"
        static let lastAuthAlertAt = "last-auth-alert-at"
        static let tokenExpiry = "github-token-expiry"
        static let authFailed = "github-auth-failed"
    }

    /// `integer(forKey:)` can't tell "unset" from "zero", which matters for an
    /// hour of 0 — so unset falls through to the documented default.
    private static func storedInt(_ key: String, default fallback: Int) -> Int {
        (sharedDefaults.object(forKey: key) as? Int) ?? fallback
    }

    private static func storedBool(_ key: String, default fallback: Bool) -> Bool {
        (sharedDefaults.object(forKey: key) as? Bool) ?? fallback
    }

    static var notificationSettings: NotificationSettings {
        get {
            NotificationSettings(
                enabled: storedBool(Keys.notificationsEnabled, default: false),
                middayHour: storedInt(Keys.middayHour, default: 13),
                middayMinute: storedInt(Keys.middayMinute, default: 0),
                eveningHour: storedInt(Keys.eveningHour, default: 20),
                eveningMinute: storedInt(Keys.eveningMinute, default: 0),
                milestonesEnabled: storedBool(Keys.milestonesEnabled, default: true),
                tokenAlertsEnabled: storedBool(Keys.tokenAlertsEnabled, default: true)
            )
        }
        set {
            let defaults = sharedDefaults
            defaults.set(newValue.enabled, forKey: Keys.notificationsEnabled)
            defaults.set(newValue.middayHour, forKey: Keys.middayHour)
            defaults.set(newValue.middayMinute, forKey: Keys.middayMinute)
            defaults.set(newValue.eveningHour, forKey: Keys.eveningHour)
            defaults.set(newValue.eveningMinute, forKey: Keys.eveningMinute)
            defaults.set(newValue.milestonesEnabled, forKey: Keys.milestonesEnabled)
            defaults.set(newValue.tokenAlertsEnabled, forKey: Keys.tokenAlertsEnabled)
        }
    }

    static var lastCelebratedStreak: Int {
        get { sharedDefaults.integer(forKey: Keys.lastCelebratedStreak) }
        set { sharedDefaults.set(newValue, forKey: Keys.lastCelebratedStreak) }
    }

    static var lastAuthAlertAt: Date? {
        get { sharedDefaults.object(forKey: Keys.lastAuthAlertAt) as? Date }
        set { sharedDefaults.set(newValue, forKey: Keys.lastAuthAlertAt) }
    }

    static var tokenExpiry: Date? {
        get { sharedDefaults.object(forKey: Keys.tokenExpiry) as? Date }
        set { sharedDefaults.set(newValue, forKey: Keys.tokenExpiry) }
    }

    static var authFailed: Bool {
        get { sharedDefaults.bool(forKey: Keys.authFailed) }
        set { sharedDefaults.set(newValue, forKey: Keys.authFailed) }
    }

    /// Wipes everything notification-related. Used on disconnect so a new
    /// account doesn't inherit the previous one's milestones or token dates.
    static func resetNotificationState() {
        let defaults = sharedDefaults
        for key in [
            Keys.lastCelebratedStreak, Keys.lastAuthAlertAt,
            Keys.tokenExpiry, Keys.authFailed,
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
