import Foundation

struct ContributionSnapshot: Codable {
    let totalContributions: Int
    let currentStreak: Int
    let committedToday: Bool
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
            currentStreak: calendar.currentStreak,
            committedToday: calendar.committedToday,
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
