import Foundation

/// One notification the app wants iOS to hold. `id` is stable for a given
/// (kind, day) so re-planning produces the same identifier and the scheduler
/// can diff instead of piling up duplicates.
struct PlannedNotification: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

struct NotificationSettings: Equatable {
    var enabled: Bool = false
    var middayHour: Int = 13
    var middayMinute: Int = 0
    var eveningHour: Int = 20
    var eveningMinute: Int = 0
    var milestonesEnabled: Bool = true
    var tokenAlertsEnabled: Bool = true

    static let `default` = NotificationSettings()
}

/// Everything the planner is allowed to look at. Passing `now` explicitly is
/// what makes the whole ladder testable without touching the clock.
struct NotificationContext {
    var snapshot: ContributionSnapshot?
    var settings: NotificationSettings = .default
    var tokenExpiry: Date?
    var lastCelebratedStreak: Int = 0
    var authFailed: Bool = false
    var lastAuthAlertAt: Date?
    var now: Date = Date()
    var calendar: Calendar = Calendar(identifier: .gregorian)
}

/// Decides *what* should be scheduled. Pure — no UNUserNotificationCenter, no
/// network, no wall clock. Everything about number accuracy lives here.
///
/// Three rules keep the numbers honest:
///  1. Nothing is ever scheduled past today. Tomorrow's streak is unknowable
///     today (it depends on whether you push), so the window rolls forward on
///     each reconciliation instead of being guessed ahead of time.
///  2. Numbered copy requires a snapshot fetched within `maxSnapshotAge`. Stale
///     data produces silence, never a confident wrong number.
///  3. Every number is derived from the same snapshot the widget renders, so
///     the notification and the home screen cannot disagree.
enum NotificationPlanner {
    static let milestones = [3, 7, 14, 30, 50, 100, 200, 365]

    /// Past this, a cached snapshot is treated as unknown rather than current.
    static let maxSnapshotAge: TimeInterval = 24 * 60 * 60

    /// Celebrations are detected on a background refresh that could land at any
    /// hour, so they get held to daylight. Warnings don't need this — their
    /// fire times are user-chosen by definition.
    static let quietHoursEnd = 8
    static let quietHoursStart = 22

    /// Don't re-nag about a dead token more than once a day.
    static let authAlertCooldown: TimeInterval = 24 * 60 * 60

    /// Token warnings land mid-morning on their target day.
    static let tokenWarningHour = 10

    static func plan(_ context: NotificationContext) -> [PlannedNotification] {
        guard context.settings.enabled else { return [] }

        var planned: [PlannedNotification] = []
        planned.append(contentsOf: tokenNotifications(context))

        // A broken token means the contribution data can't be trusted. Nagging
        // someone to commit using numbers we can't verify is worse than silence.
        guard !context.authFailed else { return planned }

        planned.append(contentsOf: commitNotifications(context))
        return planned
    }

    // MARK: - Token lifecycle

    private static func tokenNotifications(_ context: NotificationContext) -> [PlannedNotification] {
        guard context.settings.tokenAlertsEnabled else { return [] }

        if context.authFailed {
            let cooledDown = context.lastAuthAlertAt.map {
                context.now.timeIntervalSince($0) >= authAlertCooldown
            } ?? true
            guard cooledDown else { return [] }
            return [PlannedNotification(
                id: "token-expired",
                title: "Pushed can't reach GitHub",
                body: "Your token stopped working. Tap to reconnect.",
                fireDate: context.now.addingTimeInterval(60)
            )]
        }

        guard let expiry = context.tokenExpiry else { return [] }

        // Each lead time is its own calendar-triggered notification, queued the
        // moment we learn the expiry date. These need no background execution —
        // iOS holds them even if the app is never opened again.
        return [10, 5, 1].compactMap { daysOut -> PlannedNotification? in
            // Anchored to 10am on the target day rather than to the expiry
            // timestamp minus N days — a token that dies at 03:00 shouldn't
            // wake anyone at 03:00 to say so. A lead time already in the past
            // is dropped; there's always a later rung still ahead unless the
            // token is inside its final day, which the 401 path covers.
            guard let target = context.calendar.date(byAdding: .day, value: -daysOut, to: expiry),
                  let fire = dateOn(target, hour: tokenWarningHour, minute: 0, calendar: context.calendar),
                  fire > context.now else { return nil }
            return PlannedNotification(
                id: "token-expiring-\(daysOut)",
                title: daysOut == 1 ? "Your GitHub token expires tomorrow" : "Your GitHub token expires in \(daysOut) days",
                body: "Generate a new one so the widget keeps updating.",
                fireDate: fire
            )
        }
    }

    // MARK: - Commit nudges

    private static func commitNotifications(_ context: NotificationContext) -> [PlannedNotification] {
        guard let snapshot = context.snapshot else { return [] }
        guard context.now.timeIntervalSince(snapshot.fetchedAt) < maxSnapshotAge else { return [] }
        guard let gap = snapshot.daysSinceLastContribution(asOf: context.now) else { return [] }

        // Pushed today: the day's work is done. Only a celebration can fire.
        if gap == 0 {
            return milestoneNotification(snapshot, context).map { [$0] } ?? []
        }

        return gap == 1
            ? streakAtRisk(snapshot, context)
            : dormant(snapshot, gap: gap, context: context)
    }

    /// Pushed yesterday, nothing today — there's a real streak on the line.
    /// Both slots fire, every day. This user has earned the volume.
    private static func streakAtRisk(
        _ snapshot: ContributionSnapshot,
        _ context: NotificationContext
    ) -> [PlannedNotification] {
        let streak = snapshot.currentStreak(asOf: context.now)
        var out: [PlannedNotification] = []

        if let fire = middayFire(context) {
            let body: String
            switch streak {
            case ..<3: body = "Nothing pushed yet today. Keep it going."
            case 3...6: body = "Today's square is still empty."
            case 7...29: body = "Nothing pushed yet today."
            default: body = "Don't let today be the gap."
            }
            out.append(PlannedNotification(
                id: dailyID("midday", context),
                title: streak >= 30 ? "\(streak) days" : "\(streak)-day streak",
                body: body,
                fireDate: fire
            ))
        }

        if let fire = eveningFire(context) {
            let hours = hoursUntilMidnight(from: fire, calendar: context.calendar)
            let remaining = hours <= 0 ? "Less than an hour left." : "About \(hours) hour\(hours == 1 ? "" : "s") left."
            let title: String
            let body: String
            switch streak {
            case 1:
                title = "Day one on the line"
                body = "One push tonight makes it two."
            case 2...13:
                title = "Your \(streak)-day streak ends at midnight"
                body = remaining
            case 14...29:
                title = "\(streak) days on the line"
                body = "Midnight. \(remaining)"
            default:
                title = "\(streak) days on the line"
                body = "\(remaining) Don't break it now."
            }
            out.append(PlannedNotification(
                id: dailyID("evening", context),
                title: title,
                body: body,
                fireDate: fire
            ))
        }

        return out
    }

    /// Streak is already gone, so there's no midnight deadline to warn about —
    /// one notification per firing day, and the frequency tapers the longer the
    /// silence runs. An app that nags daily for a month gets deleted before the
    /// comeback it was hoping for.
    private static func dormant(
        _ snapshot: ContributionSnapshot,
        gap: Int,
        context: NotificationContext
    ) -> [PlannedNotification] {
        guard shouldSpeak(dormantGap: gap) else { return [] }

        let missedDays = gap - 1
        let title: String
        let body: String
        let useEvening: Bool

        switch gap {
        case 2:
            // The streak died yesterday. Naming what was lost beats a generic
            // "you missed a day" — it's the difference between the app knowing
            // you and not.
            let previous = snapshot.streakBeforeBreak
            if previous >= 7 {
                title = "Your \(previous)-day streak ended"
                body = "Start the next one today."
            } else {
                title = "Yesterday's square is empty"
                body = "Today's isn't — yet."
            }
            useEvening = false
        case 3:
            title = "Not coding today?"
            body = "Two days quiet. One commit resets the clock."
            useEvening = true
        case 4...7:
            title = "\(missedDays) days off"
            body = "One commit starts a new streak."
            useEvening = false
        default:
            title = "Back on the grind?"
            body = "One push is all it takes."
            useEvening = false
        }

        let fire = useEvening ? eveningFire(context) : middayFire(context)
        guard let fire else { return [] }

        return [PlannedNotification(
            id: dailyID(useEvening ? "evening" : "midday", context),
            title: title,
            body: body,
            fireDate: fire
        )]
    }

    /// Frequency scales with engagement: daily through the first week, then
    /// every third day, then weekly, then silence.
    static func shouldSpeak(dormantGap gap: Int) -> Bool {
        switch gap {
        case ...1: return false
        case 2...7: return true
        case 8...21: return (gap - 8) % 3 == 0
        case 22...60: return (gap - 22) % 7 == 0
        default: return false
        }
    }

    // MARK: - Milestones

    private static func milestoneNotification(
        _ snapshot: ContributionSnapshot,
        _ context: NotificationContext
    ) -> PlannedNotification? {
        guard context.settings.milestonesEnabled else { return nil }

        let streak = snapshot.currentStreak(asOf: context.now)
        guard let reached = milestones.last(where: { $0 <= streak }) else { return nil }

        // Comparing against the last celebrated value (rather than "greater
        // than") means a streak that breaks and climbs back to 7 celebrates
        // again, while 15 days doesn't re-fire the 14-day badge.
        guard reached != context.lastCelebratedStreak else { return nil }

        return PlannedNotification(
            id: "milestone-\(reached)",
            title: reached == 365 ? "One full year" : "\(reached) days straight",
            body: milestoneBody(reached),
            fireDate: deliverableTime(context)
        )
    }

    /// The milestone to record as already-celebrated when an account is first
    /// connected. Someone who installs mid-streak shouldn't be congratulated
    /// for a mark they hit before the app existed — but their *next* one should
    /// still land.
    static func milestoneBaseline(for snapshot: ContributionSnapshot?, asOf now: Date) -> Int {
        guard let snapshot else { return 0 }
        let streak = snapshot.currentStreak(asOf: now)
        return milestones.last(where: { $0 <= streak }) ?? 0
    }

    private static func milestoneBody(_ milestone: Int) -> String {
        switch milestone {
        case 3: return "Three in a row. It's becoming a habit."
        case 7: return "A full week without a gap."
        case 14: return "Two weeks without a gap."
        case 30: return "A month of green squares."
        case 50: return "Fifty days. That's not luck."
        case 100: return "Triple digits."
        case 200: return "Two hundred days straight."
        default: return "365 days. Every single one."
        }
    }

    /// Now, unless now is inside quiet hours — then the next 8am.
    private static func deliverableTime(_ context: NotificationContext) -> Date {
        let cal = context.calendar
        let hour = cal.component(.hour, from: context.now)

        if hour >= quietHoursEnd && hour < quietHoursStart {
            return context.now.addingTimeInterval(5)
        }
        let day = hour >= quietHoursStart
            ? cal.date(byAdding: .day, value: 1, to: context.now) ?? context.now
            : context.now
        return dateOn(day, hour: quietHoursEnd, minute: 0, calendar: cal) ?? context.now
    }

    // MARK: - Fire times

    /// Today's slot, but only if it hasn't passed. Never tomorrow's — see rule 1.
    private static func middayFire(_ context: NotificationContext) -> Date? {
        todayAt(context.settings.middayHour, context.settings.middayMinute, context)
    }

    private static func eveningFire(_ context: NotificationContext) -> Date? {
        todayAt(context.settings.eveningHour, context.settings.eveningMinute, context)
    }

    private static func todayAt(_ hour: Int, _ minute: Int, _ context: NotificationContext) -> Date? {
        guard let fire = dateOn(context.now, hour: hour, minute: minute, calendar: context.calendar)
        else { return nil }
        return fire > context.now ? fire : nil
    }

    /// Builds the time on the *same* calendar day as `day`. Deliberately not
    /// `date(bySettingHour:of:)` — that searches forward, so asking for 1pm at
    /// 3pm hands back tomorrow's 1pm, which would sail past the "never schedule
    /// beyond today" rule. Going through components also keeps DST honest.
    private static func dateOn(_ day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func hoursUntilMidnight(from date: Date, calendar: Calendar) -> Int {
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        else { return 0 }
        return Int(midnight.timeIntervalSince(date) / 3600)
    }

    /// Scoped to the calendar day so a leftover from yesterday never matches
    /// today's plan — the scheduler's diff sweeps it away on its own.
    private static func dailyID(_ slot: String, _ context: NotificationContext) -> String {
        "daily-\(slot)-\(ContributionCalendar.dateFormatter.string(from: context.now))"
    }
}
