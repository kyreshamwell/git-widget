import Foundation

extension ContributionSnapshot {
    /// A believable year ending today: busy weekdays, lighter weekends, a quiet
    /// stretch in the middle and a live streak at the end. Deterministic, so
    /// previews don't reshuffle between renders.
    ///
    /// Stands in wherever real data can't: the widget gallery before anyone
    /// has connected, the in-app style previews, and demo screenshots.
    static func sample(streak: Int = 12, asOf now: Date = Date()) -> ContributionSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: now) // Sunday = 1
        // 52 full weeks plus this week so far, the same shape `from(_:)` keeps.
        let dayCount = 52 * 7 + (weekday == 7 ? 0 : weekday)

        var levels: [Int] = []
        var total = 0
        for index in 0..<dayCount {
            let daysAgo = dayCount - 1 - index
            let dayOfWeek = ((weekday - 1 - daysAgo) % 7 + 7) % 7 // 0 = Sunday
            let active: Bool
            if daysAgo < streak {
                active = true
            } else if daysAgo == streak || (140...150).contains(daysAgo) {
                active = false // the break before this streak, and a holiday
            } else {
                let isWeekend = dayOfWeek == 0 || dayOfWeek == 6
                active = noise(daysAgo) < (isWeekend ? 0.25 : 0.72)
            }

            // Weighted toward the lighter greens, like most real graphs.
            let level = active ? [1, 1, 1, 2, 2, 2, 3, 3, 4][Int(noise(daysAgo &* 31 &+ 7) * 9)] : 0
            levels.append(level)
            total += [0, 2, 5, 9, 14][level]
        }

        return ContributionSnapshot(
            totalContributions: total,
            recentLevels: levels,
            lastDate: ContributionCalendar.dateFormatter.string(from: now),
            fetchedAt: now
        )
    }

    /// A stable value in 0..<1 for each seed (SplitMix64).
    private static func noise(_ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }
}
