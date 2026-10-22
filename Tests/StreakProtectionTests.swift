import XCTest

final class StreakProtectionTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private let cal = Calendar(identifier: .gregorian)

    // MARK: - Helpers

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    /// A snapshot whose last day is `end`. `pattern` is one character per day,
    /// oldest first: "#" pushed, "." empty. Spaces only separate weeks.
    private func snapshot(endingOn end: String, _ pattern: String) -> ContributionSnapshot {
        let levels = pattern.filter { $0 != " " }.map { $0 == "#" ? 2 : 0 }
        return ContributionSnapshot(
            totalContributions: levels.reduce(0, +),
            recentLevels: levels,
            lastDate: end,
            fetchedAt: date(end)
        )
    }

    /// Rest days in force since long before any of the test dates.
    private func resting(_ weekdays: Int..., claims: [String: DayOff] = [:]) -> StreakProtection {
        StreakProtection(
            schedules: [.init(from: "2026-01-01", weekdays: weekdays)],
            claims: claims
        )
    }

    private func marks(_ history: StreakHistory) -> String {
        String(history.days.map { day -> Character in
            switch day.off {
            case .rest: "r"
            case .freeze: "f"
            case nil: day.isActive ? "#" : "."
            }
        })
    }

    // Oct 2026: the 4th, 11th and 18th are Sundays.
    private let sunday = 1, wednesday = 4, saturday = 7

    // MARK: - Fixed rest days

    func testAWeekendOffKeepsTheStreakWithoutAddingToIt() {
        // Mon-Fri pushed, Sat and Sun off, Mon-Fri pushed, read on Saturday.
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .#####.")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-17"))

        XCTAssertEqual(marks(history), "r#####r" + "r#####r")
        XCTAssertEqual(history.streak, 10, "ten days pushed; the days off don't count")
        XCTAssertEqual(history.today, .off(.rest))
        XCTAssertEqual(history.gap, 1, "alive, with nothing owed today")
    }

    func testWithoutRestDaysTheSameWeekendBreaksTheStreak() {
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .#####.")
        let history = snap.history(asOf: date("2026-10-17"))

        XCTAssertEqual(history.streak, 5)
        XCTAssertEqual(history.today, .pending)
    }

    func testPushingOnARestDayIsAnOrdinaryGreenSquare() {
        // Sunday the 11th was pushed. It counts, and it isn't marked off.
        let snap = snapshot(endingOn: "2026-10-12", ".#####. ##")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-12"))

        XCTAssertEqual(marks(history), "r#####r" + "##")
        XCTAssertEqual(history.streak, 7)
        XCTAssertEqual(history.today, .pushed)
    }

    func testRestDaysNeverReachBackBeforeTheyWereChosen() {
        // Chosen on Monday the 12th: the weekend just gone stays a gap.
        let snap = snapshot(endingOn: "2026-10-12", ".#####. .#")
        var protection = StreakProtection()
        protection.setWeekdays([sunday, saturday], asOf: date("2026-10-12"))
        let history = snap.history(protection: protection, asOf: date("2026-10-12"))

        XCTAssertEqual(marks(history), ".#####." + ".#")
        XCTAssertEqual(history.streak, 1)
    }

    func testARestDayAfterAMissDoesNotBringTheStreakBack() {
        // Only Sundays are off. Saturday the 10th was missed, so the run that
        // ended Friday is over even though Sunday is a day off.
        let snap = snapshot(endingOn: "2026-10-12", ".#####. ..")
        let history = snap.history(protection: resting(sunday), asOf: date("2026-10-12"))

        XCTAssertEqual(marks(history), "r#####." + "r.")
        XCTAssertEqual(history.streak, 0)
        XCTAssertEqual(history.streakBeforeBreak, 5)
        XCTAssertEqual(history.gap, 3)
    }

    func testTheGapCountsFromTheLastDayOffNotTheLastPush() {
        // Pushed Friday, weekend off, then Monday and Tuesday missed. On
        // Wednesday that's two days quiet, not four.
        let snap = snapshot(endingOn: "2026-10-14", ".#####. ....")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-14"))

        XCTAssertEqual(history.gap, 3)
        XCTAssertEqual(history.streak, 0)
        XCTAssertEqual(history.streakBeforeBreak, 5)
    }

    func testAStaleSnapshotStillReadsTodayAsARestDay() {
        // Fetched Friday night, drawn on Saturday morning with no refresh.
        let snap = snapshot(endingOn: "2026-10-16", ".#####. .#####")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-17"))

        XCTAssertEqual(history.days.count, 14, "padded out to today")
        XCTAssertEqual(history.today, .off(.rest))
        XCTAssertEqual(history.streak, 10)
        XCTAssertEqual(history.endDate, date("2026-10-17"))
    }

    // MARK: - Two a week

    func testClaimingADayMovesARestDayAndLeavesTheLaterOneUncovered() {
        // Sunday used one. Wednesday is claimed, which spends the other, so
        // Saturday is an ordinary empty day.
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .##.##.")
        let protection = resting(sunday, saturday, claims: ["2026-10-14": .rest])
        let history = snap.history(protection: protection, asOf: date("2026-10-18"))

        XCTAssertEqual(marks(history), "r#####r" + "r##r##." + "r")
        XCTAssertEqual(history.streak, 0, "Saturday was missed")
        XCTAssertEqual(history.streakBeforeBreak, 9)
    }

    func testARestDayNotNeededIsStillThereToMove() {
        // Sunday was pushed, so both are left: Wednesday and Saturday.
        let snap = snapshot(endingOn: "2026-10-17", ".#####. ###.##.")
        let protection = resting(sunday, saturday, claims: ["2026-10-14": .rest])
        let history = snap.history(protection: protection, asOf: date("2026-10-17"))

        XCTAssertEqual(marks(history), "r#####r" + "###r##r")
        XCTAssertEqual(history.streak, 10)
    }

    func testAThirdDayInOneWeekIsNotCovered() {
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .#.#.#.")
        let protection = resting(sunday, saturday, claims: ["2026-10-13": .rest, "2026-10-15": .rest])
        let history = snap.history(protection: protection, asOf: date("2026-10-17"))

        // Sunday and Tuesday take the two. Thursday's claim and Saturday don't hold.
        XCTAssertEqual(marks(history), "r#####r" + "r#r#.#.")
    }

    func testTheAllowanceMatchesHowManyDaysWereChosen() {
        // One fixed day means one a week: with Sunday used, Wednesday can't be claimed.
        let snap = snapshot(endingOn: "2026-10-14", ".#####. .##.")
        let history = snap.history(protection: resting(sunday), asOf: date("2026-10-14"))

        XCTAssertFalse(history.canClaim(.rest, daysAgo: 0))
        XCTAssertEqual(history.restDaysLeftThisWeek, 0)
    }

    func testARestDayCannotBeClaimedWithNoneChosen() {
        let snap = snapshot(endingOn: "2026-10-14", ".#####. ###.")
        let claimedAnyway = StreakProtection(claims: ["2026-10-14": .rest])

        XCTAssertFalse(snap.history(asOf: date("2026-10-14")).canClaim(.rest, daysAgo: 0))
        XCTAssertEqual(snap.history(protection: claimedAnyway, asOf: date("2026-10-14")).today, .pending)
    }

    func testEachWeekStartsWithAFreshAllowance() {
        let snap = snapshot(endingOn: "2026-10-18", "..####. .#####. .")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-18"))

        XCTAssertEqual(marks(history), "r.####r" + "r#####r" + "r")
        XCTAssertEqual(history.restDaysLeftThisWeek, 1, "Sunday so far; Saturday's is still ahead")
    }

    // MARK: - The freeze

    func testAFreezeCoversOneDayAMonth() {
        // No rest days at all: two freezes claimed in October, only the first holds.
        let snap = snapshot(endingOn: "2026-10-16", "#####.###.#")
        let protection = StreakProtection(claims: ["2026-10-11": .freeze, "2026-10-15": .freeze])
        let history = snap.history(protection: protection, asOf: date("2026-10-16"))

        XCTAssertEqual(marks(history), "#####f###.#")
        XCTAssertEqual(history.streak, 1)
        XCTAssertEqual(history.freezeUsedThisMonth, date("2026-10-11"))
    }

    func testANewMonthBringsANewFreeze() {
        // Frozen Sep 30 and again Oct 2.
        let snap = snapshot(endingOn: "2026-10-03", "###.#.#")
        let protection = StreakProtection(claims: ["2026-09-30": .freeze, "2026-10-02": .freeze])
        let history = snap.history(protection: protection, asOf: date("2026-10-03"))

        XCTAssertEqual(marks(history), "###f#f#")
        XCTAssertEqual(history.streak, 5)
    }

    func testAFreezeIsSeparateFromTheWeeksRestDays() {
        // Sunday and Saturday off, plus Wednesday frozen: three days off, streak intact.
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .##.##.")
        let protection = resting(sunday, saturday, claims: ["2026-10-14": .freeze])
        let history = snap.history(protection: protection, asOf: date("2026-10-17"))

        XCTAssertEqual(marks(history), "r#####r" + "r##f##r")
        XCTAssertEqual(history.streak, 9)
    }

    func testTurningFreezesOffKeepsOneAlreadyUsed() {
        let snap = snapshot(endingOn: "2026-10-16", "#####.####.")
        var protection = StreakProtection(claims: ["2026-10-11": .freeze])
        protection.freezeEnabled = false
        let history = snap.history(protection: protection, asOf: date("2026-10-16"))

        XCTAssertEqual(history.streak, 9)
        XCTAssertFalse(history.canClaim(.freeze, daysAgo: 0), "no new ones while it's off")
    }

    // MARK: - Honest squares

    func testACommitThatShowsUpLateHandsTheDayBack() {
        // Wednesday was claimed, then GitHub reported a push for it after all.
        // It's green, and Saturday is covered again.
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .#####.")
        let protection = resting(sunday, saturday, claims: ["2026-10-14": .rest])
        let history = snap.history(protection: protection, asOf: date("2026-10-17"))

        XCTAssertEqual(marks(history), "r#####r" + "r#####r")
        XCTAssertEqual(history.streak, 10)
    }

    func testAFreezeOnADayThatTurnsGreenIsNotSpent() {
        let snap = snapshot(endingOn: "2026-10-16", "######.###.")
        let protection = StreakProtection(claims: ["2026-10-06": .freeze])
        let history = snap.history(protection: protection, asOf: date("2026-10-16"))

        XCTAssertNil(history.freezeUsedThisMonth)
        XCTAssertTrue(history.canClaim(.freeze, daysAgo: 0))
    }

    // MARK: - Claiming

    func testOnlyTodayAndYesterdayCanBeClaimed() {
        let snap = snapshot(endingOn: "2026-10-15", ".#####. .#...")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-15"))

        XCTAssertTrue(history.canClaim(.rest, daysAgo: 0))
        XCTAssertTrue(history.canClaim(.rest, daysAgo: 1))
        XCTAssertFalse(history.canClaim(.rest, daysAgo: 2), "Tuesday's window has closed")
        XCTAssertFalse(history.canClaim(.freeze, daysAgo: 2))
    }

    func testADayAlreadyPushedOrAlreadyOffHasNothingToClaim() {
        // Saturday the 17th: today is a rest day, yesterday was pushed.
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .#####.")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-17"))

        XCTAssertFalse(history.canClaim(.rest, daysAgo: 0))
        XCTAssertFalse(history.canClaim(.freeze, daysAgo: 0))
        XCTAssertFalse(history.canClaim(.freeze, daysAgo: 1))
    }

    func testCoveringYesterdayBringsTheStreakBack() {
        // Wednesday the 14th was missed. Read on Thursday.
        let snap = snapshot(endingOn: "2026-10-15", ".#####. .##..")
        var protection = resting(sunday, saturday)
        let before = snap.history(protection: protection, asOf: date("2026-10-15"))

        XCTAssertEqual(before.streak, 0)
        XCTAssertEqual(before.gap, 2)
        XCTAssertTrue(before.canSaveStreak)

        protection.claim(.rest, on: before.date(daysAgo: 1)!)
        let after = snap.history(protection: protection, asOf: date("2026-10-15"))

        XCTAssertEqual(after.streak, 7)
        XCTAssertEqual(after.gap, 1)
        XCTAssertEqual(after.claim(daysAgo: 1), .rest)
        XCTAssertFalse(after.canSaveStreak, "nothing left to save")
    }

    func testAStreakTwoDaysGoneCannotBeSaved() {
        let snap = snapshot(endingOn: "2026-10-16", ".#####. .##...")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-16"))

        XCTAssertEqual(history.gap, 3)
        XCTAssertFalse(history.canSaveStreak)
    }

    func testWithNothingLeftTheStreakCannotBeSaved() {
        // Sunday and Tuesday took the week's two, and October's freeze is gone.
        let snap = snapshot(endingOn: "2026-10-15", ".###.#. .#...")
        let protection = resting(sunday, saturday, claims: ["2026-10-08": .freeze, "2026-10-13": .rest])
        let history = snap.history(protection: protection, asOf: date("2026-10-15"))

        XCTAssertEqual(history.gap, 2)
        XCTAssertFalse(history.canSaveStreak)
    }

    func testAClaimCanBeTakenBackOnlyWhileItsWindowIsOpen() {
        let snap = snapshot(endingOn: "2026-10-15", ".#####. .#.#.")
        let protection = resting(sunday, saturday, claims: ["2026-10-13": .freeze, "2026-10-15": .rest])
        let history = snap.history(protection: protection, asOf: date("2026-10-15"))

        XCTAssertEqual(history.claim(daysAgo: 0), .rest)
        XCTAssertNil(history.claim(daysAgo: 2), "Tuesday's freeze is settled")
    }

    // MARK: - Changing rest days

    func testAFirstChoiceStartsToday() {
        var protection = StreakProtection()
        protection.setWeekdays([saturday], asOf: date("2026-10-14"))

        XCTAssertEqual(protection.weekdays(on: date("2026-10-14")), [saturday])
        XCTAssertNil(protection.pendingStart(asOf: date("2026-10-14")))
    }

    func testPickingTwoDaysOneTapAtATimeStartsBothToday() {
        var protection = StreakProtection()
        protection.setWeekdays([saturday], asOf: date("2026-10-14"))
        protection.setWeekdays([saturday, sunday], asOf: date("2026-10-14"))

        XCTAssertEqual(protection.weekdays(on: date("2026-10-14")), [sunday, saturday])
        XCTAssertEqual(protection.schedules.count, 1)
    }

    func testChangingRestDaysWaitsForSunday() {
        var protection = resting(sunday, saturday)
        protection.setWeekdays([6, saturday], asOf: date("2026-10-14")) // a Wednesday

        XCTAssertEqual(protection.weekdays(on: date("2026-10-17")), [sunday, saturday], "this week is unchanged")
        XCTAssertEqual(protection.weekdays(on: date("2026-10-18")), [6, saturday])
        XCTAssertEqual(protection.pendingStart(asOf: date("2026-10-14")), date("2026-10-18"))
        XCTAssertEqual(protection.chosenWeekdays, [6, saturday])
    }

    func testUntickingADayAndTickingItBackLeavesNothingBehind() {
        let original = resting(sunday, saturday)
        var protection = original
        protection.setWeekdays([sunday], asOf: date("2026-10-14"))
        protection.setWeekdays([], asOf: date("2026-10-14"))
        protection.setWeekdays([sunday], asOf: date("2026-10-14"))
        protection.setWeekdays([sunday, saturday], asOf: date("2026-10-14"))

        XCTAssertEqual(protection, original)
    }

    func testSwitchingRestDaysOffStartsToday() {
        var protection = resting(sunday, saturday)
        protection.setWeekdays([], asOf: date("2026-10-14"))

        XCTAssertEqual(protection.weekdays(on: date("2026-10-13")), [sunday, saturday], "the past is untouched")
        XCTAssertTrue(protection.weekdays(on: date("2026-10-14")).isEmpty)
        XCTAssertTrue(protection.weekdays(on: date("2026-10-17")).isEmpty)
    }

    func testAChangeMadeOnASundayAppliesToTheWeekItStarts() {
        var protection = resting(sunday, saturday)
        protection.setWeekdays([wednesday, saturday], asOf: date("2026-10-18"))

        XCTAssertEqual(protection.weekdays(on: date("2026-10-18")), [wednesday, saturday])
        XCTAssertEqual(protection.weekdays(on: date("2026-10-17")), [sunday, saturday])
    }

    func testChangingRestDaysLeavesEarlierWeeksAsTheyWere() {
        // Sat and Sun until the 18th, then only Saturday. The earlier Sundays stay off.
        let snap = snapshot(endingOn: "2026-10-19", ".#####. .#####. .#")
        var protection = resting(sunday, saturday)
        protection.setWeekdays([saturday], asOf: date("2026-10-14"))
        let history = snap.history(protection: protection, asOf: date("2026-10-19"))

        XCTAssertEqual(marks(history), "r#####r" + "r#####r" + ".#")
        XCTAssertEqual(history.streak, 1)
    }

    func testNoMoreThanTwoRestDaysCanBeChosen() {
        var protection = StreakProtection()
        protection.setWeekdays([1, 2, 3, 7], asOf: date("2026-10-14"))
        XCTAssertEqual(protection.chosenWeekdays.count, StreakProtection.maxRestDays)
    }

    // MARK: - What gets drawn

    func testTheGraphStillStartsOnASundayOncePaddedToToday() {
        // Two full weeks fetched on Saturday the 10th, drawn the next Tuesday.
        let snap = snapshot(endingOn: "2026-10-10", ".#####. .#####.")
        let history = snap.history(asOf: date("2026-10-13"))
        let shown = history.days(forWeeks: 1)

        XCTAssertEqual(shown.count, 7 + 3, "last full week, plus Sunday to Tuesday")
        XCTAssertEqual(shown.suffix(3).map(\.level), [0, 0, 0])
    }

    func testTheLastSevenDaysCarryTheirDaysOff() {
        let snap = snapshot(endingOn: "2026-10-17", ".#####. .#####.")
        let history = snap.history(protection: resting(sunday, saturday), asOf: date("2026-10-17"))
        let week = history.days(last: 7)

        XCTAssertEqual(week.map(\.off), [.rest, nil, nil, nil, nil, nil, .rest])
        XCTAssertEqual(week.map(\.isActive), [false, true, true, true, true, true, false])
    }

    // MARK: - Saved data

    func testChoicesSurviveSaving() throws {
        var protection = resting(sunday, saturday, claims: ["2026-10-14": .freeze])
        protection.freezeEnabled = false

        let decoded = try JSONDecoder().decode(StreakProtection.self, from: JSONEncoder().encode(protection))
        XCTAssertEqual(decoded, protection)
    }

    func testMissingFieldsFallBackWithoutLosingTheRest() throws {
        let json = #"{"schedules":[{"from":"2026-01-01","weekdays":[1,7]}]}"#
        let decoded = try JSONDecoder().decode(StreakProtection.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.chosenWeekdays, [1, 7])
        XCTAssertTrue(decoded.claims.isEmpty)
        XCTAssertTrue(decoded.freezeEnabled)
    }

    func testOldClaimsAndSchedulesAreDroppedOnceOutOfSight() {
        var protection = StreakProtection(
            schedules: [
                .init(from: "2023-01-01", weekdays: [1]),
                .init(from: "2024-01-01", weekdays: [1, 7]),
            ],
            claims: ["2024-03-03": .freeze]
        )
        protection.claim(.rest, on: date("2026-10-14"))

        XCTAssertEqual(protection.claims, ["2026-10-14": .rest])
        XCTAssertEqual(protection.schedules, [.init(from: "2024-01-01", weekdays: [1, 7])])
    }
}
