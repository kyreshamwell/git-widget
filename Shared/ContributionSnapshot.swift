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
// Note these read only the retained window (up to 52 weeks), so a streak longer
// than ~366 days reports as the window length. Not worth extra storage.
extension ContributionSnapshot {
    private var gregorian: Calendar { Calendar(identifier: .gregorian) }

    /// Most recent day with any contribution, or nil if the window is empty.
    var lastContributionDate: Date? {
        guard let end = endDate,
              let index = recentLevels.lastIndex(where: { $0 > 0 }) else { return nil }
        let daysBack = recentLevels.count - 1 - index
        return gregorian.date(byAdding: .day, value: -daysBack, to: end)
    }

    /// The counter the whole notification ladder keys off:
    ///   0  — pushed today
    ///   1  — pushed yesterday; streak alive but at risk
    ///   2  — missed exactly one full day
    ///   n  — missed n-1 full days
    /// nil — no contribution anywhere in the retained window.
    func daysSinceLastContribution(asOf now: Date) -> Int? {
        guard let last = lastContributionDate else { return nil }
        return gregorian.dateComponents(
            [.day],
            from: gregorian.startOfDay(for: last),
            to: gregorian.startOfDay(for: now)
        ).day
    }

    var daysSinceLastContribution: Int? { daysSinceLastContribution(asOf: Date()) }

    func committedToday(asOf now: Date) -> Bool {
        daysSinceLastContribution(asOf: now) == 0
    }

    var committedToday: Bool { committedToday(asOf: Date()) }

    /// Consecutive contribution days counting back from the last active day —
    /// but only if that day is today or yesterday. Two days of silence means
    /// the streak is gone, so this returns 0.
    func currentStreak(asOf now: Date) -> Int {
        guard let gap = daysSinceLastContribution(asOf: now), gap <= 1 else { return 0 }
        return runEndingAtLastContribution
    }

    var currentStreak: Int { currentStreak(asOf: Date()) }

    /// Length of the run that just ended, regardless of how long ago it ended.
    /// Powers "your 15-day streak ended" on the first dormant day.
    var streakBeforeBreak: Int { runEndingAtLastContribution }

    private var runEndingAtLastContribution: Int {
        guard var index = recentLevels.lastIndex(where: { $0 > 0 }) else { return 0 }
        var count = 0
        while index >= 0 && recentLevels[index] > 0 {
            count += 1
            index -= 1
        }
        return count
    }
}
