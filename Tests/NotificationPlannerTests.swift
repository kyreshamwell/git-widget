import XCTest

final class NotificationPlannerTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private let cal = Calendar(identifier: .gregorian)

    // MARK: - Helpers

    /// A snapshot whose green run ends `lastActiveDaysAgo` days before `now`.
    /// `lastActiveDaysAgo: 0` = pushed today, `1` = pushed yesterday (streak
    /// alive), `2` = missed exactly one full day.
    private func makeSnapshot(
        now: Date,
        lastActiveDaysAgo: Int,
        streakLength: Int,
        fetchedAt: Date? = nil,
        span: Int = 400
    ) -> ContributionSnapshot {
        var levels = Array(repeating: 0, count: span)
        if streakLength > 0 {
            let lastIndex = span - 1 - lastActiveDaysAgo
            for index in max(0, lastIndex - streakLength + 1)...lastIndex { levels[index] = 2 }
        }
        return ContributionSnapshot(
            totalContributions: streakLength,
            recentLevels: levels,
            lastDate: formatter.string(from: now),
            fetchedAt: fetchedAt ?? now
        )
    }

    private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = cal.dateComponents([.year, .month, .day], from: formatter.date(from: day)!)
        components.hour = hour
        components.minute = minute
        return cal.date(from: components)!
    }

    private func context(
        now: Date,
        lastActiveDaysAgo: Int,
        streakLength: Int,
        fetchedAt: Date? = nil
    ) -> NotificationContext {
        var settings = NotificationSettings.default
        settings.enabled = true
        return NotificationContext(
            snapshot: makeSnapshot(
                now: now,
                lastActiveDaysAgo: lastActiveDaysAgo,
                streakLength: streakLength,
                fetchedAt: fetchedAt
            ),
            settings: settings,
            now: now
        )
    }

    private func find(_ plan: [PlannedNotification], slot: String) -> PlannedNotification? {
        plan.first { $0.id.hasPrefix("daily-\(slot)") }
    }

    // MARK: - Number accuracy
    //
    // The whole point of the design: a notification may never show a streak
    // number the snapshot doesn't actually support.

    func testMiddayReportsExactStreakNotABucketLabel() {
        for streak in [1, 2, 3, 6, 7, 12, 13, 14, 29, 30, 47] {
            let plan = NotificationPlanner.plan(
                context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: streak)
            )
            let midday = find(plan, slot: "midday")
            XCTAssertNotNil(midday, "streak \(streak) should get a midday nudge")
            XCTAssertTrue(
                midday!.title.contains("\(streak)"),
                "streak \(streak) produced title \"\(midday!.title)\" — number missing or wrong"
            )
        }
    }

    func testStreakCountsThroughYesterdayNotToday() {
        // 13 green days ending yesterday, nothing today. Must say 13 — not 12
        // (dropping yesterday) and not 14 (counting today optimistically).
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: 13)
        )
        XCTAssertEqual(find(plan, slot: "midday")?.title, "13-day streak")
        XCTAssertEqual(find(plan, slot: "evening")?.title, "Your 13-day streak ends at midnight")
    }

    func testMiddayAndEveningNeverDisagreeOnTheNumber() {
        for streak in [2, 5, 9, 13, 14, 21, 40] {
            let plan = NotificationPlanner.plan(
                context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: streak)
            )
            let midday = find(plan, slot: "midday")!
            let evening = find(plan, slot: "evening")!
            XCTAssertTrue(midday.title.contains("\(streak)"))
            XCTAssertTrue(
                evening.title.contains("\(streak)"),
                "evening title \"\(evening.title)\" lost the number for streak \(streak)"
            )
        }
    }

    func testEveningCopyBucketFlipsBetween13And14() {
        let thirteen = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: 13)
        )
        let fourteen = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: 14)
        )
        XCTAssertEqual(find(thirteen, slot: "evening")?.title, "Your 13-day streak ends at midnight")
        XCTAssertEqual(find(fourteen, slot: "evening")?.title, "14 days on the line")
    }

    func testStaleSnapshotProducesSilenceNotAWrongNumber() {
        let now = at("2026-08-04", 9)
        let stale = context(
            now: now,
            lastActiveDaysAgo: 1,
            streakLength: 18,
            fetchedAt: now.addingTimeInterval(-25 * 3600)
        )
        XCTAssertTrue(NotificationPlanner.plan(stale).isEmpty)

        let fresh = context(
            now: now,
            lastActiveDaysAgo: 1,
            streakLength: 18,
            fetchedAt: now.addingTimeInterval(-2 * 3600)
        )
        XCTAssertFalse(NotificationPlanner.plan(fresh).isEmpty)
    }

    func testCommitNudgesNeverScheduleBeyondToday() {
        let now = at("2026-08-04", 9)
        for daysAgo in [1, 2, 3, 5, 8] {
            let plan = NotificationPlanner.plan(
                context(now: now, lastActiveDaysAgo: daysAgo, streakLength: 9)
            )
            for notification in plan where notification.id.hasPrefix("daily-") {
                XCTAssertTrue(
                    cal.isDate(notification.fireDate, inSameDayAs: now),
                    "\(notification.id) was scheduled off-day — tomorrow's streak isn't knowable today"
                )
            }
        }
    }

    func testHoursLeftIsDerivedFromTheActualFireTime() {
        var eight = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: 5)
        XCTAssertEqual(find(NotificationPlanner.plan(eight), slot: "evening")?.body, "About 4 hours left.")

        eight.settings.eveningHour = 22
        XCTAssertEqual(find(NotificationPlanner.plan(eight), slot: "evening")?.body, "About 2 hours left.")

        eight.settings.eveningHour = 23
        eight.settings.eveningMinute = 30
        XCTAssertEqual(find(NotificationPlanner.plan(eight), slot: "evening")?.body, "Less than an hour left.")
    }

    // MARK: - Committed today

    func testPushedTodaySilencesBothSlots() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 0, streakLength: 12)
        )
        XCTAssertNil(find(plan, slot: "midday"))
        XCTAssertNil(find(plan, slot: "evening"))
    }

    func testPushedTodayStillAllowsMilestone() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 0, streakLength: 14)
        )
        XCTAssertEqual(plan.map(\.id), ["milestone-14"])
    }

    // MARK: - Slot timing

    func testMiddaySkippedOnceItsTimeHasPassed() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 15), lastActiveDaysAgo: 1, streakLength: 9)
        )
        XCTAssertNil(find(plan, slot: "midday"), "1pm already passed — must not fire late")
        XCTAssertNotNil(find(plan, slot: "evening"))
    }

    func testBothSlotsSkippedLateAtNight() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 21), lastActiveDaysAgo: 1, streakLength: 9)
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testCustomTimesAreRespected() {
        var custom = context(now: at("2026-08-04", 6), lastActiveDaysAgo: 1, streakLength: 9)
        custom.settings.middayHour = 11
        custom.settings.middayMinute = 30
        let plan = NotificationPlanner.plan(custom)
        XCTAssertEqual(cal.component(.hour, from: find(plan, slot: "midday")!.fireDate), 11)
        XCTAssertEqual(cal.component(.minute, from: find(plan, slot: "midday")!.fireDate), 30)
    }

    func testFireTimeHoldsAcrossDaylightSavingBoundaries() {
        for day in ["2026-03-08", "2026-11-01", "2026-06-15"] {
            let plan = NotificationPlanner.plan(
                context(now: at(day, 6), lastActiveDaysAgo: 1, streakLength: 9)
            )
            let midday = find(plan, slot: "midday")!
            XCTAssertEqual(cal.component(.hour, from: midday.fireDate), 13, "hour drifted on \(day)")
        }
    }

    // MARK: - Dormant ladder

    func testFirstDormantDayNamesTheStreakThatDied() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 2, streakLength: 15)
        )
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].title, "Your 15-day streak ended")
        XCTAssertEqual(plan[0].body, "Start the next one today.")
    }

    func testFirstDormantDayStaysGentleForAShortStreak() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 2, streakLength: 3)
        )
        XCTAssertEqual(plan[0].title, "Yesterday's square is empty")
    }

    func testFirstDormantDayHasNoEveningSlot() {
        // Nothing left to lose tonight, so no midnight deadline to warn about.
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 2, streakLength: 15)
        )
        XCTAssertNil(find(plan, slot: "evening"))
        XCTAssertNotNil(find(plan, slot: "midday"))
    }

    func testSecondDormantDayUsesTheEveningSlot() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 3, streakLength: 15)
        )
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].title, "Not coding today?")
        XCTAssertTrue(plan[0].id.hasPrefix("daily-evening"))
    }

    func testDormantMidWeekCountsMissedDaysCorrectly() {
        // gap 5 means four full days missed, not five.
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 5, streakLength: 15)
        )
        XCTAssertEqual(plan[0].title, "4 days off")
    }

    func testDormantTaperDropsToEveryThirdDayAfterAWeek() {
        let speaks = (8...20).filter { NotificationPlanner.shouldSpeak(dormantGap: $0) }
        XCTAssertEqual(speaks, [8, 11, 14, 17, 20])
    }

    func testDormantTaperDropsToWeeklyAfterThreeWeeks() {
        let speaks = (22...50).filter { NotificationPlanner.shouldSpeak(dormantGap: $0) }
        XCTAssertEqual(speaks, [22, 29, 36, 43, 50])
    }

    func testDormantGoesFullySilentAfterSixtyDays() {
        XCTAssertFalse(NotificationPlanner.shouldSpeak(dormantGap: 61))
        XCTAssertFalse(NotificationPlanner.shouldSpeak(dormantGap: 200))
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 90, streakLength: 15)
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testNoContributionsAtAllProducesSilence() {
        let plan = NotificationPlanner.plan(
            context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: 0)
        )
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Milestones

    func testMilestoneFiresWhenReached() {
        var ctx = context(now: at("2026-08-04", 14), lastActiveDaysAgo: 0, streakLength: 14)
        ctx.lastCelebratedStreak = 7
        XCTAssertEqual(NotificationPlanner.plan(ctx).map(\.id), ["milestone-14"])
    }

    func testMilestoneDoesNotRefireOnLaterDaysOfTheSameStreak() {
        var ctx = context(now: at("2026-08-04", 14), lastActiveDaysAgo: 0, streakLength: 15)
        ctx.lastCelebratedStreak = 14
        XCTAssertTrue(NotificationPlanner.plan(ctx).isEmpty)
    }

    func testMilestoneCelebratesAgainAfterAStreakRebuild() {
        // Hit 14, broke it, climbed back to 7 — that 7 deserves its moment.
        var ctx = context(now: at("2026-08-04", 14), lastActiveDaysAgo: 0, streakLength: 7)
        ctx.lastCelebratedStreak = 14
        XCTAssertEqual(NotificationPlanner.plan(ctx).map(\.id), ["milestone-7"])
    }

    func testNonMilestoneStreakStaysQuiet() {
        var ctx = context(now: at("2026-08-04", 14), lastActiveDaysAgo: 0, streakLength: 12)
        ctx.lastCelebratedStreak = 7
        XCTAssertTrue(NotificationPlanner.plan(ctx).isEmpty)
    }

    func testMilestoneDetectedAtNightIsHeldUntilMorning() {
        var ctx = context(now: at("2026-08-04", 23, 40), lastActiveDaysAgo: 0, streakLength: 14)
        ctx.lastCelebratedStreak = 7
        let fire = NotificationPlanner.plan(ctx)[0].fireDate
        XCTAssertEqual(cal.component(.hour, from: fire), 8)
        XCTAssertTrue(cal.isDate(fire, inSameDayAs: at("2026-08-05", 8)))
    }

    func testMilestoneDetectedBeforeDawnIsHeldUntilMorning() {
        var ctx = context(now: at("2026-08-04", 3), lastActiveDaysAgo: 0, streakLength: 30)
        ctx.lastCelebratedStreak = 14
        let fire = NotificationPlanner.plan(ctx)[0].fireDate
        XCTAssertEqual(cal.component(.hour, from: fire), 8)
        XCTAssertTrue(cal.isDate(fire, inSameDayAs: at("2026-08-04", 8)))
    }

    func testMilestoneDuringDaylightFiresImmediately() {
        var ctx = context(now: at("2026-08-04", 14), lastActiveDaysAgo: 0, streakLength: 30)
        ctx.lastCelebratedStreak = 14
        let fire = NotificationPlanner.plan(ctx)[0].fireDate
        XCTAssertEqual(fire.timeIntervalSince(ctx.now), 5, accuracy: 1)
    }

    func testMilestonesDisabledSkipsCelebration() {
        var ctx = context(now: at("2026-08-04", 14), lastActiveDaysAgo: 0, streakLength: 14)
        ctx.settings.milestonesEnabled = false
        XCTAssertTrue(NotificationPlanner.plan(ctx).isEmpty)
    }

    // MARK: - Token lifecycle

    func testTokenLadderQueuesTenFiveAndOneDayWarnings() {
        var ctx = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 0, streakLength: 4)
        ctx.tokenExpiry = at("2026-08-16", 9)
        let ids = NotificationPlanner.plan(ctx).map(\.id).filter { $0.hasPrefix("token-") }
        XCTAssertEqual(ids, ["token-expiring-10", "token-expiring-5", "token-expiring-1"])
    }

    func testTokenLadderDropsLeadTimesThatAlreadyPassed() {
        var ctx = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 0, streakLength: 4)
        ctx.tokenExpiry = at("2026-08-07", 9) // three days out
        let ids = NotificationPlanner.plan(ctx).map(\.id).filter { $0.hasPrefix("token-") }
        XCTAssertEqual(ids, ["token-expiring-1"])
    }

    func testTokenWarningFireDatesLandOnTheRightDays() {
        var ctx = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 0, streakLength: 4)
        ctx.tokenExpiry = at("2026-08-16", 9)
        let plan = NotificationPlanner.plan(ctx)
        let byID = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0.fireDate) })
        XCTAssertTrue(cal.isDate(byID["token-expiring-10"]!, inSameDayAs: at("2026-08-06", 9)))
        XCTAssertTrue(cal.isDate(byID["token-expiring-5"]!, inSameDayAs: at("2026-08-11", 9)))
        XCTAssertTrue(cal.isDate(byID["token-expiring-1"]!, inSameDayAs: at("2026-08-15", 9)))
    }

    func testTokenWarningsFireMidMorningNotAtTheExpiryTimestamp() {
        var ctx = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 0, streakLength: 4)
        ctx.tokenExpiry = at("2026-08-16", 3) // token dies at 3am
        for warning in NotificationPlanner.plan(ctx) where warning.id.hasPrefix("token-") {
            XCTAssertEqual(
                cal.component(.hour, from: warning.fireDate), 10,
                "\(warning.id) would have woken someone at 3am"
            )
        }
    }

    func testTokenLeadTimeAlreadyPastIsDroppedButLaterRungsSurvive() {
        // Connecting with 10 days left: this morning's 10-day rung is gone, but
        // the 5- and 1-day warnings still land. Documented boundary, not a gap.
        var ctx = context(now: at("2026-08-04", 15), lastActiveDaysAgo: 0, streakLength: 4)
        ctx.tokenExpiry = at("2026-08-14", 15)
        let ids = NotificationPlanner.plan(ctx).map(\.id).filter { $0.hasPrefix("token-") }
        XCTAssertEqual(ids, ["token-expiring-5", "token-expiring-1"])
    }

    func testBrokenTokenSuppressesCommitNudges() {
        var ctx = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: 18)
        ctx.authFailed = true
        let plan = NotificationPlanner.plan(ctx)
        XCTAssertEqual(plan.map(\.id), ["token-expired"])
        XCTAssertNil(find(plan, slot: "midday"), "can't nag about data we can't read")
    }

    func testBrokenTokenAlertRespectsDailyCooldown() {
        let now = at("2026-08-04", 9)
        var recent = context(now: now, lastActiveDaysAgo: 1, streakLength: 18)
        recent.authFailed = true
        recent.lastAuthAlertAt = now.addingTimeInterval(-3600)
        XCTAssertTrue(NotificationPlanner.plan(recent).isEmpty)

        var stale = recent
        stale.lastAuthAlertAt = now.addingTimeInterval(-25 * 3600)
        XCTAssertEqual(NotificationPlanner.plan(stale).map(\.id), ["token-expired"])
    }

    func testTokenAlertsDisabledSkipsTheWholeLadder() {
        var ctx = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 0, streakLength: 4)
        ctx.tokenExpiry = at("2026-08-16", 9)
        ctx.settings.tokenAlertsEnabled = false
        XCTAssertTrue(NotificationPlanner.plan(ctx).filter { $0.id.hasPrefix("token-") }.isEmpty)
    }

    // MARK: - Master switch

    func testDisabledProducesAnEmptyPlan() {
        var ctx = context(now: at("2026-08-04", 9), lastActiveDaysAgo: 1, streakLength: 18)
        ctx.settings.enabled = false
        ctx.tokenExpiry = at("2026-08-16", 9)
        XCTAssertTrue(NotificationPlanner.plan(ctx).isEmpty)
    }
}
