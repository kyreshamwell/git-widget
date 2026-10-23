import Foundation

/// Why an empty day doesn't break the streak.
enum DayOff: String, Codable, Sendable {
    /// One of the week's rest days: a fixed weekday, or one moved to another
    /// day by claiming it.
    case rest
    /// The monthly freeze.
    case freeze
}

/// Rest days and the monthly freeze: the weekdays someone chose and the days
/// they claimed by hand.
///
/// Only those choices are stored. Which days end up protected is worked out
/// from them and the contribution data together (see `daysOff`), so a commit
/// that shows up late just turns the square green and hands the rest day back.
/// Nothing here can make a day look pushed: GitHub's squares stay GitHub's.
struct StreakProtection: Codable, Equatable, Sendable {
    /// Rest weekdays that apply from one day onward.
    struct Schedule: Codable, Equatable, Sendable {
        /// "yyyy-MM-dd".
        var from: String
        /// Calendar weekdays: 1 is Sunday, 7 is Saturday.
        var weekdays: [Int]
    }

    /// Oldest first. Kept as a history rather than one current value, so
    /// changing rest days never rewrites weeks that already happened.
    var schedules: [Schedule] = []
    /// Days claimed by hand, keyed "yyyy-MM-dd".
    var claims: [String: DayOff] = [:]
    /// Turning this off only stops new freezes. One already used still counts.
    var freezeEnabled = true
    /// "yyyy-MM-dd" of the day this account was connected. Before then Pushed
    /// wasn't watching, so no day earlier than this is ever called missed.
    /// Nil marks no missed days at all.
    var trackedSince: String? = nil

    /// Nothing chosen, nothing claimed and no freeze to use: the streak
    /// exactly as GitHub's own squares give it.
    static let none = StreakProtection(freezeEnabled: false)
    /// What everyone starts with: no rest days until some are chosen, and
    /// the monthly freeze there for the day it's needed.
    static let initial = StreakProtection()

    /// Rest days per week, counted Sunday to Saturday like the graph's columns.
    static let maxRestDays = 2
    static let freezesPerMonth = 1
    /// A day can be claimed on the day itself or the day after.
    static let claimWindow = 0...1

    /// Longer than the graph ever looks back, so nothing still drawn is lost.
    private static let daysKept = 400

    static func key(_ day: Date) -> String {
        ContributionCalendar.dateFormatter.string(from: day)
    }
}

// MARK: - Choosing rest days

extension StreakProtection {
    /// The rest weekdays in force on `day`.
    func weekdays(on day: Date) -> Set<Int> {
        let key = Self.key(day)
        return Set(schedules.last { $0.from <= key }?.weekdays ?? [])
    }

    /// The latest choice, which may not have started yet.
    var chosenWeekdays: Set<Int> {
        Set(schedules.last?.weekdays ?? [])
    }

    /// When the latest choice starts, if that's still ahead.
    func pendingStart(asOf now: Date) -> Date? {
        guard let latest = schedules.last, latest.from > Self.key(now) else { return nil }
        return ContributionCalendar.dateFormatter.date(from: latest.from)
    }

    /// A first choice starts today, and so does switching rest days off.
    /// Swapping one set for another waits for Sunday, so a week that's
    /// underway keeps the rest days it started with.
    ///
    /// Everything is measured against what was in force yesterday, which makes
    /// repeated edits on the same day land in the same place: picking two days
    /// one tap at a time, or unticking a day and ticking it back, can't leave
    /// a half-applied change behind.
    mutating func setWeekdays(
        _ weekdays: Set<Int>,
        asOf now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        let chosen = Array(weekdays.filter { (1...7).contains($0) }.sorted().prefix(Self.maxRestDays))
        let today = calendar.startOfDay(for: now)
        let todayKey = Self.key(today)

        schedules.removeAll { $0.from >= todayKey }
        let inForce = Set(schedules.last?.weekdays ?? [])
        guard Set(chosen) != inForce else { return }

        let weekday = calendar.component(.weekday, from: today)
        let startsToday = weekday == 1 || inForce.isEmpty || chosen.isEmpty
        let start = startsToday
            ? today
            : calendar.date(byAdding: .day, value: 8 - weekday, to: today) ?? today
        schedules.append(Schedule(from: Self.key(start), weekdays: chosen))
        prune(asOf: today, calendar: calendar)
    }
}

// MARK: - Claiming a day

extension StreakProtection {
    /// Records the claim. Whether it holds (the day is still empty, and the
    /// week or month has one left) is decided when the days are worked out,
    /// so ask `StreakHistory.canClaim` first.
    mutating func claim(
        _ kind: DayOff,
        on day: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        claims[Self.key(day)] = kind
        prune(asOf: day, calendar: calendar)
    }

    mutating func removeClaim(on day: Date) {
        claims[Self.key(day)] = nil
    }

    private mutating func prune(asOf day: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.daysKept, to: day) else { return }
        let cutoffKey = Self.key(cutoff)
        claims = claims.filter { $0.key >= cutoffKey }
        // Keep the one schedule still in force at the cutoff, drop any before it.
        if let inForce = schedules.lastIndex(where: { $0.from <= cutoffKey }), inForce > 0 {
            schedules.removeFirst(inForce)
        }
    }
}

// MARK: - Working out the days

extension StreakProtection {
    /// Which of these days are days off. `levels` runs oldest first and ends
    /// on `end`; the result lines up with it.
    ///
    /// Days are taken in order, so a week's rest days go to whichever empty
    /// days come first: a fixed weekday, or a claimed one. Once the week's
    /// allowance is spent, a later fixed day is left as an ordinary empty
    /// day. That's what makes claiming a day a move and not an extra.
    func daysOff(
        levels: [Int],
        endingOn end: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [DayOff?] {
        var result = [DayOff?](repeating: nil, count: levels.count)
        guard !levels.isEmpty, !(schedules.isEmpty && claims.isEmpty) else { return result }

        let endDay = calendar.startOfDay(for: end)
        let last = levels.count - 1
        func index(of key: String) -> Int? {
            guard let date = ContributionCalendar.dateFormatter.date(from: key),
                  let back = calendar.dateComponents(
                      [.day], from: calendar.startOfDay(for: date), to: endDay
                  ).day else { return nil }
            return last - back
        }

        // Dates are turned into positions once, so the walk below is plain
        // arithmetic over a year of days.
        let plans = schedules.compactMap { schedule in
            index(of: schedule.from).map { (start: $0, weekdays: Set(schedule.weekdays)) }
        }
        var claimed: [Int: (kind: DayOff, month: String)] = [:]
        for (key, kind) in claims {
            guard let position = index(of: key), levels.indices.contains(position) else { continue }
            claimed[position] = (kind, String(key.prefix(7)))
        }

        let endWeekday = calendar.component(.weekday, from: endDay)
        var restsThisWeek = 0
        var freezesByMonth: [String: Int] = [:]

        for position in levels.indices {
            let weekday = ((endWeekday - 1 - (last - position)) % 7 + 7) % 7 + 1
            if weekday == 1 { restsThisWeek = 0 }
            // A day with a contribution is never a day off, claimed or not.
            guard levels[position] == 0 else { continue }

            let fixed = plans.last { $0.start <= position }?.weekdays ?? []
            let allowance = min(fixed.count, Self.maxRestDays)
            let claim = claimed[position]

            if claim?.kind == .freeze {
                let month = claim?.month ?? ""
                if freezesByMonth[month, default: 0] < Self.freezesPerMonth {
                    freezesByMonth[month, default: 0] += 1
                    result[position] = .freeze
                }
            } else if claim?.kind == .rest || fixed.contains(weekday) {
                if restsThisWeek < allowance {
                    restsThisWeek += 1
                    result[position] = .rest
                }
            }
        }
        return result
    }
}

// MARK: - Saved data

extension StreakProtection {
    private enum CodingKeys: String, CodingKey {
        case schedules, claims, freezeEnabled, trackedSince
    }

    /// A field that's missing or unreadable takes its default, so a value
    /// saved by an older or newer build never costs someone their rest days.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schedules = (try? container.decodeIfPresent([Schedule].self, forKey: .schedules)) ?? []
        claims = (try? container.decodeIfPresent([String: DayOff].self, forKey: .claims)) ?? [:]
        freezeEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .freezeEnabled)) ?? true
        trackedSince = try? container.decodeIfPresent(String.self, forKey: .trackedSince)
    }
}
