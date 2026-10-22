import Foundation

/// Pretend streaks for trying the app on a real phone: the app, the widgets
/// and the reminders all read sample data in one of a few set-ups, while the
/// real data keeps refreshing underneath, untouched.
///
/// Only Xcode and TestFlight builds can turn it on (see `ContentView`). The
/// widget can't reliably tell a TestFlight install from an App Store one, so
/// it simply follows what the app stored, and an App Store build clears it at
/// launch.
enum TestScenario: String, CaseIterable, Identifiable {
    case off
    case pushedToday
    case waitingOnToday
    case missedYesterday

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .pushedToday: "Pushed today"
        case .waitingOnToday: "Waiting on today"
        case .missedYesterday: "Missed yesterday"
        }
    }

    /// How many days at the end of the sample are left empty, today included.
    private var quietDays: Int {
        switch self {
        case .off, .pushedToday: 0
        case .waitingOnToday: 1
        case .missedYesterday: 2
        }
    }

    private static let key = "test-scenario"
    private static let savedProtectionKey = "test-scenario-saved-protection"
    private static let savedCelebratedKey = "test-scenario-saved-celebrated"

    static var current: TestScenario {
        AppConfig.sharedDefaults.string(forKey: key).flatMap(TestScenario.init) ?? .off
    }

    /// The snapshot to draw and plan from: the real one, or while testing, a
    /// sample with a 12-day streak in the chosen set-up.
    func snapshot(replacing real: ContributionSnapshot?, now: Date = Date()) -> ContributionSnapshot? {
        self == .off ? real : .sample(streak: 12, quiet: quietDays, asOf: now)
    }

    /// Switching on keeps a copy of the real rest days, freezes and milestone
    /// progress. Switching off puts that copy back, so a freeze spent on a
    /// pretend miss, or a milestone celebrated for a pretend streak, never
    /// sticks to the real account.
    static func switchTo(_ scenario: TestScenario) {
        let defaults = AppConfig.sharedDefaults
        let wasTesting = current != .off

        if !wasTesting && scenario != .off {
            defaults.set(try? JSONEncoder().encode(AppConfig.streakProtection), forKey: savedProtectionKey)
            defaults.set(AppConfig.lastCelebratedStreak, forKey: savedCelebratedKey)
        } else if wasTesting && scenario == .off {
            restore()
        }
        defaults.set(scenario.rawValue, forKey: key)
    }

    /// Ends testing and puts the real state back. Safe to call when it's off.
    static func reset() {
        guard current != .off else { return }
        restore()
        AppConfig.sharedDefaults.removeObject(forKey: key)
    }

    private static func restore() {
        let defaults = AppConfig.sharedDefaults
        if let data = defaults.data(forKey: savedProtectionKey),
           let protection = try? JSONDecoder().decode(StreakProtection.self, from: data) {
            AppConfig.streakProtection = protection
        }
        if defaults.object(forKey: savedCelebratedKey) != nil {
            AppConfig.lastCelebratedStreak = defaults.integer(forKey: savedCelebratedKey)
        }
        defaults.removeObject(forKey: savedProtectionKey)
        defaults.removeObject(forKey: savedCelebratedKey)
    }
}
