import Foundation

/// Pretend streaks for trying the app on a real phone: the app, the widgets
/// and the reminders all read sample data in one of a few set-ups, while the
/// real data keeps refreshing underneath, untouched.
///
/// Only Xcode and TestFlight builds can turn it on (see `ContentView`). Two
/// things keep it from ever reaching an App Store install:
///  1. An App Store build clears it the moment the app launches.
///  2. It switches itself off two days after it was turned on. The widget and
///     the reminders check that themselves, since they can't tell a TestFlight
///     install from an App Store one and may run before the app is opened.
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
    private static let startedKey = "test-scenario-started"
    private static let savedProtectionKey = "test-scenario-saved-protection"
    private static let savedCelebratedKey = "test-scenario-saved-celebrated"

    /// How long a test runs before it switches itself off. Long enough to
    /// watch a midnight go by; picking a scenario again starts the clock over.
    static let lifetime: TimeInterval = 2 * 24 * 60 * 60

    /// What was picked, whether or not it has run its course.
    private static var stored: TestScenario {
        AppConfig.sharedDefaults.string(forKey: key).flatMap(TestScenario.init) ?? .off
    }

    static var current: TestScenario { current(asOf: Date()) }

    /// The scenario in force. Off once it has run its course, even before
    /// anything has cleaned up after it, and off if there's no record of when
    /// it began: a test of unknown age is treated as over.
    static func current(asOf now: Date) -> TestScenario {
        let scenario = stored
        guard scenario != .off,
              let started = AppConfig.sharedDefaults.object(forKey: startedKey) as? Date,
              now.timeIntervalSince(started) < lifetime else { return .off }
        return scenario
    }

    /// When the running test switches itself off, if one is running.
    static func endsAt(asOf now: Date = Date()) -> Date? {
        guard current(asOf: now) != .off,
              let started = AppConfig.sharedDefaults.object(forKey: startedKey) as? Date else { return nil }
        return started.addingTimeInterval(lifetime)
    }

    /// Puts the real rest days and milestones back once a test has run its
    /// course. Called wherever the app or the widget starts work, so a test
    /// that timed out never leaves its pretend state behind.
    static func expireIfNeeded(now: Date = Date()) {
        guard stored != .off, current(asOf: now) == .off else { return }
        end()
    }

    /// Pushed days in the pretend run, before any rest days are taken out.
    private static let runLength = 14

    /// The snapshot to draw and plan from: the real one, or while testing, a
    /// pretend run in the chosen set-up.
    ///
    /// Your rest weekdays are left empty inside the run, the way they would
    /// be for real, so the graph shows days off and the streak carries over
    /// them. The week before the run is empty too, so it starts from a clean
    /// break and its length is predictable.
    func snapshot(replacing real: ContributionSnapshot?, now: Date = Date()) -> ContributionSnapshot? {
        guard self != .off else { return real }
        let base = ContributionSnapshot.sample(streak: Self.runLength, quiet: quietDays, asOf: now)
        let rest = AppConfig.streakProtection.chosenWeekdays
        let calendar = Calendar(identifier: .gregorian)
        let last = base.recentLevels.count - 1

        let levels = base.recentLevels.enumerated().map { index, level -> Int in
            let daysAgo = last - index
            // Today stays pushed in "Pushed today", whatever day it is.
            guard daysAgo >= max(quietDays, 1) else { return level }
            if daysAgo < quietDays + Self.runLength {
                let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                return rest.contains(calendar.component(.weekday, from: day)) ? 0 : level
            }
            return daysAgo < quietDays + Self.runLength + 7 ? 0 : level
        }
        return ContributionSnapshot(
            totalContributions: base.totalContributions,
            recentLevels: levels,
            lastDate: base.lastDate,
            fetchedAt: base.fetchedAt
        )
    }

    /// Switching on keeps a copy of the real rest days, freezes and milestone
    /// progress. Switching off puts that copy back, so a freeze spent on a
    /// pretend miss, or a milestone celebrated for a pretend streak, never
    /// sticks to the real account.
    ///
    /// Every switch into a test starts it fresh: the freeze unused and no days
    /// claimed, with the rest weekdays you've chosen.
    static func switchTo(_ scenario: TestScenario, now: Date = Date()) {
        expireIfNeeded(now: now)
        guard scenario != .off else {
            reset()
            return
        }

        let defaults = AppConfig.sharedDefaults
        if stored == .off {
            defaults.set(try? JSONEncoder().encode(AppConfig.streakProtection), forKey: savedProtectionKey)
            defaults.set(AppConfig.lastCelebratedStreak, forKey: savedCelebratedKey)
        }
        defaults.set(scenario.rawValue, forKey: key)
        defaults.set(now, forKey: startedKey)
        startOver(now: now)
    }

    /// Puts the test back to where it began: the freeze unused, no days
    /// claimed, and milestones as they were. Rest weekdays stay as chosen.
    static func startOver(now: Date = Date()) {
        guard current(asOf: now) != .off else { return }
        var fresh = normalized(AppConfig.streakProtection)
        fresh.claims = [:]
        fresh.freezeEnabled = true
        AppConfig.streakProtection = fresh
        if AppConfig.sharedDefaults.object(forKey: savedCelebratedKey) != nil {
            AppConfig.lastCelebratedStreak = AppConfig.sharedDefaults.integer(forKey: savedCelebratedKey)
        }
    }

    /// While testing, rest weekdays apply to every day, past ones included,
    /// and changes take effect at once. For real they never reach back and a
    /// swap waits for Sunday, which would make a test drag on for days.
    static func normalized(_ protection: StreakProtection) -> StreakProtection {
        var testing = protection
        let chosen = protection.chosenWeekdays.sorted()
        testing.schedules = chosen.isEmpty ? [] : [.init(from: "2000-01-01", weekdays: chosen)]
        // The whole pretend year counts, so missed days show throughout it.
        testing.trackedSince = "2000-01-01"
        return testing
    }

    /// Ends testing and puts the real state back. Safe to call when it's off.
    static func reset() {
        guard stored != .off else { return }
        end()
    }

    private static func end() {
        restore()
        AppConfig.sharedDefaults.removeObject(forKey: key)
        AppConfig.sharedDefaults.removeObject(forKey: startedKey)
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
