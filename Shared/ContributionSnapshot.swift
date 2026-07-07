import Foundation

struct ContributionSnapshot: Codable {
    let totalContributions: Int
    let currentStreak: Int
    let committedToday: Bool
    let recentCounts: [Int] // last ~91 days, oldest first, for the mini heatmap
    let fetchedAt: Date

    static let defaultsKey = "latest-contribution-snapshot"

    static func from(_ calendar: ContributionCalendar) -> ContributionSnapshot {
        let recent = calendar.days.suffix(91).map(\.contributionCount)
        return ContributionSnapshot(
            totalContributions: calendar.totalContributions,
            currentStreak: calendar.currentStreak,
            committedToday: calendar.committedToday,
            recentCounts: Array(recent),
            fetchedAt: Date()
        )
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
