import Foundation

/// One square: how busy the day was, and whether an empty one is a day off.
struct StreakDay: Equatable, Sendable {
    var level: Int
    var off: DayOff? = nil
    /// The empty day a streak ended on. Styles can outline it in a color of
    /// its own, so every break stands out on the graph.
    var endedStreak = false

    var isActive: Bool { level > 0 }
}

/// A snapshot read through to today, with rest days and freezes applied.
///
/// Every number the widget, the app and the reminders show comes from here,
/// so they can't disagree about whether a streak is alive. Nothing is frozen
/// at fetch time: a snapshot cached yesterday is read as of now, and the days
/// since it was fetched count as empty.
struct StreakHistory {
    /// Oldest first, ending today. Column 0 of the graph is the first entry,
    /// which is a Sunday, the same as the snapshot's own levels.
    let days: [StreakDay]
    /// The date of the last entry in `days`.
    let endDate: Date?

    private let todayIndex: Int?
    private let protection: StreakProtection
    private let calendar: Calendar

    init(
        snapshot: ContributionSnapshot,
        protection: StreakProtection = .none,
        asOf now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.protection = protection
        self.calendar = calendar

        guard let snapshotEnd = snapshot.endDate else {
            days = snapshot.recentLevels.map { StreakDay(level: $0) }
            endDate = nil
            todayIndex = nil
            return
        }

        let today = calendar.startOfDay(for: now)
        let missing = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: snapshotEnd), to: today
        ).day ?? 0
        let levels = snapshot.recentLevels + Array(repeating: 0, count: max(missing, 0))
        // A snapshot can run a day past the phone's clock when GitHub's idea
        // of today is ahead of it. Then nothing is padded and today sits
        // before the last entry.
        let end = missing >= 0 ? today : snapshotEnd
        let off = protection.daysOff(levels: levels, endingOn: end, calendar: calendar)
        let todayPosition = levels.count - 1 + min(missing, 0)

        // Missed days are only called out from the day Pushed started
        // watching. A gap from before then wasn't a miss it could warn about.
        let trackedFrom = protection.trackedSince
            .flatMap { ContributionCalendar.dateFormatter.date(from: $0) }
            .flatMap { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: end).day }
            .map { levels.count - 1 - $0 }

        var built = zip(levels, off).map { StreakDay(level: $0, off: $1) }
        if let trackedFrom {
            Self.markStreakEnds(&built, from: trackedFrom, before: todayPosition)
        }
        days = built
        endDate = end
        todayIndex = todayPosition
    }

    /// Pushed days in a row before a gap counts as a streak ending. One day
    /// on its own isn't a streak, so a lone push and a quiet day aren't flagged.
    static let shortestStreak = 2

    /// Flags the first missed day after each run of `shortestStreak` or more
    /// pushed days, from `first` on. A run that began before then still
    /// counts toward its length. Days off carry a run along without adding to
    /// it, and today is never flagged: it isn't over.
    private static func markStreakEnds(_ days: inout [StreakDay], from first: Int, before today: Int) {
        var run = 0
        for index in days.indices where index < today {
            if days[index].isActive {
                run += 1
            } else if days[index].off == nil {
                days[index].endedStreak = index >= first && run >= shortestStreak
                run = 0
            }
        }
    }
}

// MARK: - The streak

extension StreakHistory {
    enum Today: Equatable {
        case pushed
        /// Nothing pushed, and nothing needed: today is a day off.
        case off(DayOff)
        case pending
    }

    /// The last day the streak was kept: the latest contribution, carried
    /// forward over any days off that follow it. Never today itself, since
    /// today isn't over.
    private var lastKeptIndex: Int? {
        guard let todayIndex, var index = days.lastIndex(where: \.isActive) else { return nil }
        while index + 1 < todayIndex, days[index + 1].off != nil { index += 1 }
        return index
    }

    /// The counter the notification ladder keys off:
    ///   0    pushed today
    ///   1    kept through yesterday; streak alive
    ///   2    missed exactly one full day
    ///   n    missed n-1 full days
    ///   nil  no contribution anywhere in the retained window.
    var gap: Int? {
        guard let todayIndex, let lastKeptIndex else { return nil }
        return todayIndex - lastKeptIndex
    }

    var pushedToday: Bool { gap == 0 }

    var today: Today {
        if pushedToday { return .pushed }
        if let todayIndex, days.indices.contains(todayIndex), let off = days[todayIndex].off {
            return .off(off)
        }
        return .pending
    }

    /// Days with a contribution, counting back from the last one and stepping
    /// over days off, which keep the streak going without adding to it. Zero
    /// once a full day has been missed.
    var streak: Int {
        guard let gap, gap <= 1 else { return 0 }
        return runLength
    }

    /// Length of the run that just ended, however long ago it ended. Powers
    /// "your 15-day streak ended" on the first dormant day.
    var streakBeforeBreak: Int { runLength }

    private var runLength: Int {
        guard var index = days.lastIndex(where: \.isActive) else { return 0 }
        var count = 0
        while index >= 0 {
            if days[index].isActive {
                count += 1
            } else if days[index].off == nil {
                break
            }
            index -= 1
        }
        return count
    }
}

// MARK: - Other numbers

extension StreakHistory {
    /// The longest run in the retained window, counted the same way as the
    /// current streak: pushed days, stepping over days off. Today being
    /// unfinished never ends a run.
    var bestStreak: Int {
        let last = todayIndex.map { min($0, days.count - 1) } ?? days.count - 1
        guard last >= 0 else { return 0 }
        var best = 0
        var run = 0
        for index in 0...last {
            let day = days[index]
            if day.isActive {
                run += 1
            } else if day.off == nil && index != todayIndex {
                run = 0
            }
            best = max(best, run)
        }
        return best
    }

    /// This week, Sunday through Saturday: the days so far, and nil for the
    /// ones still to come.
    var thisWeek: (days: [StreakDay?], todayIndex: Int) {
        guard let today = date(daysAgo: 0) else {
            return (Array(repeating: nil, count: 7), 0)
        }
        let todayIndex = calendar.component(.weekday, from: today) - 1
        let week = (0..<7).map { position -> StreakDay? in
            let daysAgo = todayIndex - position
            guard daysAgo >= 0 else { return nil }
            return day(daysAgo: daysAgo) ?? StreakDay(level: 0)
        }
        return (week, todayIndex)
    }

    /// Days pushed since Sunday.
    var pushedThisWeek: Int {
        thisWeek.days.compactMap { $0 }.filter(\.isActive).count
    }
}

// MARK: - What to draw

extension StreakHistory {
    /// The last N weeks, keeping the Sunday column alignment intact (the
    /// trailing partial week rides along so today is always included).
    func days(forWeeks weeks: Int) -> [StreakDay] {
        Array(days.suffix(weeks * 7 + days.count % 7))
    }

    /// Exactly `count` days ending today, oldest first.
    func days(last count: Int) -> [StreakDay] {
        let tail = days.suffix(count)
        return Array(repeating: StreakDay(level: 0), count: count - tail.count) + tail
    }
}

// MARK: - Claiming

extension StreakHistory {
    func date(daysAgo: Int) -> Date? {
        guard let todayIndex, let endDate else { return nil }
        let back = days.count - 1 - (todayIndex - daysAgo)
        return calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: endDate))
    }

    private func day(daysAgo: Int) -> StreakDay? {
        guard let todayIndex, days.indices.contains(todayIndex - daysAgo) else { return nil }
        return days[todayIndex - daysAgo]
    }

    /// Whether today (0) or yesterday (1) can be taken as a day off: it has
    /// to be empty, not already off, and the week or month has to have one
    /// left. Found by trying the claim and seeing whether it holds, so this
    /// can't drift from the rules that decide what's drawn.
    func canClaim(_ kind: DayOff, daysAgo: Int) -> Bool {
        guard StreakProtection.claimWindow.contains(daysAgo),
              let todayIndex, let endDate,
              let day = day(daysAgo: daysAgo), !day.isActive, day.off == nil,
              let date = date(daysAgo: daysAgo) else { return false }
        if kind == .freeze && !protection.freezeEnabled { return false }

        var trial = protection
        trial.claims[StreakProtection.key(date)] = kind
        let outcome = trial.daysOff(levels: days.map(\.level), endingOn: endDate, calendar: calendar)
        return outcome[todayIndex - daysAgo] == kind
    }

    /// The claim made by hand on that day, if there is one and the day is
    /// still inside the window where it can be taken back.
    func claim(daysAgo: Int) -> DayOff? {
        guard StreakProtection.claimWindow.contains(daysAgo),
              let date = date(daysAgo: daysAgo),
              let kind = protection.claims[StreakProtection.key(date)],
              day(daysAgo: daysAgo)?.off == kind else { return nil }
        return kind
    }

    /// Yesterday was missed, and covering it would bring the streak back.
    var canSaveStreak: Bool {
        gap == 2 && (canClaim(.rest, daysAgo: 1) || canClaim(.freeze, daysAgo: 1))
    }

    /// Rest days not yet spent this week. Counts the ones already used,
    /// today's included, against the week's allowance.
    var restDaysLeftThisWeek: Int {
        guard let todayIndex, days.indices.contains(todayIndex), let today = date(daysAgo: 0) else { return 0 }
        let allowance = min(protection.weekdays(on: today).count, StreakProtection.maxRestDays)
        let sinceSunday = calendar.component(.weekday, from: today) - 1
        let week = days[max(todayIndex - sinceSunday, 0)...todayIndex]
        return max(allowance - week.filter { $0.off == .rest }.count, 0)
    }

    /// The day this month's freeze went on, if it's been used.
    var freezeUsedThisMonth: Date? {
        guard let todayIndex, days.indices.contains(todayIndex), let today = date(daysAgo: 0) else { return nil }
        let dayOfMonth = calendar.component(.day, from: today)
        for daysAgo in 0..<dayOfMonth where day(daysAgo: daysAgo)?.off == .freeze {
            return date(daysAgo: daysAgo)
        }
        return nil
    }
}
