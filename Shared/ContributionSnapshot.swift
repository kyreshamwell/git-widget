import Foundation

struct ContributionSnapshot: Codable {
    let totalContributions: Int
    // GitHub intensity levels 0-4, oldest first, trimmed to whole weeks so
    // column 0 of the grid is a real Sunday-Saturday week like on github.com.
    let recentLevels: [Int]
    // "yyyy-MM-dd" of the final entry in recentLevels — anchors every square
    // to a real date so the grid can draw month/weekday labels.
    let lastDate: String
    let fetchedAt: Date

    static let defaultsKey = "latest-contribution-snapshot"

    var endDate: Date? {
        ContributionCalendar.dateFormatter.date(from: lastDate)
    }

    static func from(_ calendar: ContributionCalendar) -> ContributionSnapshot {
        // Keep up to a full year (52 weeks). GitHub's weeks run Sunday-Saturday
        // and the API returns days in that order; the final (current) week may be
        // partial, so size it from the last day's actual weekday rather than
        // assuming the whole array divides evenly into weeks.
        let days = calendar.days
        var trailingPartial = 0
        if let lastDay = days.last,
           let lastDate = ContributionCalendar.dateFormatter.date(from: lastDay.date) {
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: lastDate) // Sunday = 1
            trailingPartial = weekday == 7 ? 0 : weekday
        }
        let fullWeekCount = (days.count - trailingPartial) / 7
        let weeksToKeep = min(fullWeekCount, 52)
        let start = max(0, days.count - trailingPartial - weeksToKeep * 7)
        let recent = days[start...].map(\.level)

        return ContributionSnapshot(
            totalContributions: calendar.totalContributions,
            recentLevels: Array(recent),
            lastDate: days.last?.date ?? "",
            fetchedAt: Date()
        )
    }

    /// Last N weeks of levels, keeping the Sunday column alignment intact
    /// (the trailing partial week rides along so "today" is always included).
    func levels(forWeeks weeks: Int) -> [Int] {
        let partial = recentLevels.count % 7
        return Array(recentLevels.suffix(weeks * 7 + partial))
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppConfig.sharedDefaults.set(data, forKey: ContributionSnapshot.defaultsKey)
    }

    static func load() -> ContributionSnapshot? {
        guard let data = AppConfig.sharedDefaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ContributionSnapshot.self, from: data)
    }
}

// MARK: - Derived state
//
// Streak, dormancy and "committed today" are all *derived* from recentLevels
// rather than frozen at fetch time. A snapshot cached yesterday used to claim
// committedToday == true all through today; deriving them means a stale
// snapshot degrades to an honest answer instead of a confidently wrong one.
//
// The working out lives in `StreakHistory`, which also applies rest days and
// freezes. What's here is the same answers with none applied: the streak
// exactly as GitHub's own squares give it.
//
// Note these read only the retained window (up to 52 weeks), so a streak longer
// than ~366 days reports as the window length. Not worth extra storage.
extension ContributionSnapshot {
    func history(protection: StreakProtection = .none, asOf now: Date = Date()) -> StreakHistory {
        StreakHistory(snapshot: self, protection: protection, asOf: now)
    }

    /// See `StreakHistory.gap`.
    func daysSinceLastContribution(asOf now: Date) -> Int? {
        history(asOf: now).gap
    }

    var daysSinceLastContribution: Int? { daysSinceLastContribution(asOf: Date()) }

    func committedToday(asOf now: Date) -> Bool {
        history(asOf: now).pushedToday
    }

    var committedToday: Bool { committedToday(asOf: Date()) }

    func currentStreak(asOf now: Date) -> Int {
        history(asOf: now).streak
    }

    var currentStreak: Int { currentStreak(asOf: Date()) }

    /// Exactly `count` levels ending today, oldest first. A snapshot fetched on
    /// an earlier day has no entries for the days since, which count as empty,
    /// so the last element is always today and never a stale yesterday.
    func levels(lastDays count: Int, asOf now: Date) -> [Int] {
        history(asOf: now).days(last: count).map(\.level)
    }

    var streakBeforeBreak: Int { history().streakBeforeBreak }
}
