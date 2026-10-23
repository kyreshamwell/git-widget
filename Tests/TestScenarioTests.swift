import XCTest

/// The pretend streaks behind the Testing picker. These read and write the
/// shared settings, so each test leaves them as it found them.
final class TestScenarioTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private var savedProtection: StreakProtection!

    override func setUp() {
        super.setUp()
        TestScenario.reset()
        savedProtection = AppConfig.streakProtection
    }

    override func tearDown() {
        TestScenario.reset()
        AppConfig.streakProtection = savedProtection
        super.tearDown()
    }

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    private func weekendsOff() -> StreakProtection {
        StreakProtection(schedules: [.init(from: "2026-10-01", weekdays: [1, 7])])
    }

    func testOffShowsTheRealData() {
        let real = ContributionSnapshot.sample(asOf: date("2026-10-15"))
        XCTAssertEqual(TestScenario.off.snapshot(replacing: real)?.recentLevels, real.recentLevels)
    }

    func testMissedYesterdayCanBeSavedWithTheFreeze() {
        AppConfig.streakProtection = .initial
        TestScenario.switchTo(.missedYesterday)
        let now = date("2026-10-15") // a Thursday
        let history = TestScenario.missedYesterday.snapshot(replacing: nil, now: now)!
            .history(protection: AppConfig.streakProtection, asOf: now)

        XCTAssertEqual(history.gap, 2)
        XCTAssertTrue(history.canClaim(.freeze, daysAgo: 1))
        XCTAssertGreaterThan(history.streakBeforeBreak, 1)
    }

    func testRestWeekdaysShowAsDaysOffInsideThePretendRun() {
        AppConfig.streakProtection = weekendsOff()
        TestScenario.switchTo(.pushedToday)
        let now = date("2026-10-15")
        let history = TestScenario.pushedToday.snapshot(replacing: nil, now: now)!
            .history(protection: AppConfig.streakProtection, asOf: now)

        XCTAssertEqual(history.today, .pushed)
        XCTAssertTrue(history.days(last: 14).contains { $0.off == .rest }, "the weekends in the run are days off")
        XCTAssertGreaterThanOrEqual(history.streak, 9, "and the streak carries over them")
    }

    func testStartingOverGivesTheFreezeBack() {
        AppConfig.streakProtection = .initial
        TestScenario.switchTo(.missedYesterday)
        var used = AppConfig.streakProtection
        used.claim(.freeze, on: date("2026-10-14"))
        AppConfig.streakProtection = used

        TestScenario.startOver()
        XCTAssertTrue(AppConfig.streakProtection.claims.isEmpty)
    }

    func testSwitchingOffPutsTheRealDaysOffBack() {
        var real = weekendsOff()
        real.claims = ["2026-10-08": .freeze]
        AppConfig.streakProtection = real

        TestScenario.switchTo(.waitingOnToday)
        XCTAssertTrue(AppConfig.streakProtection.claims.isEmpty, "tests start fresh")
        TestScenario.switchTo(.off)

        XCTAssertEqual(AppConfig.streakProtection, real)
    }

    func testWhileTestingRestDaysReachBackOverPastWeeks() {
        var chosen = StreakProtection()
        chosen.setWeekdays([1, 7], asOf: date("2026-10-15"))
        let testing = TestScenario.normalized(chosen)

        XCTAssertEqual(testing.weekdays(on: date("2026-09-05")), [1, 7])
    }

    // MARK: - Switching itself off

    func testATestSwitchesItselfOffAfterTwoDays() {
        let start = date("2026-10-15")
        TestScenario.switchTo(.missedYesterday, now: start)

        XCTAssertEqual(TestScenario.current(asOf: start.addingTimeInterval(47 * 3600)), .missedYesterday)
        XCTAssertEqual(TestScenario.current(asOf: start.addingTimeInterval(49 * 3600)), .off)
        XCTAssertNil(
            TestScenario.off.snapshot(replacing: nil, now: start),
            "off hands back the real data, here none"
        )
    }

    func testAnExpiredTestPutsTheRealDaysOffBack() {
        var real = weekendsOff()
        real.claims = ["2026-10-08": .freeze]
        AppConfig.streakProtection = real
        let start = date("2026-10-15")
        TestScenario.switchTo(.waitingOnToday, now: start)
        XCTAssertNotEqual(AppConfig.streakProtection, real)

        TestScenario.expireIfNeeded(now: start.addingTimeInterval(3 * 24 * 3600))
        XCTAssertEqual(AppConfig.streakProtection, real)
        XCTAssertNil(TestScenario.endsAt(asOf: start.addingTimeInterval(3 * 24 * 3600)))
    }

    func testExpiringEarlyDoesNothing() {
        let start = date("2026-10-15")
        TestScenario.switchTo(.pushedToday, now: start)
        let testing = AppConfig.streakProtection

        TestScenario.expireIfNeeded(now: start.addingTimeInterval(3600))
        XCTAssertEqual(AppConfig.streakProtection, testing)
        XCTAssertEqual(TestScenario.current(asOf: start.addingTimeInterval(3600)), .pushedToday)
    }

    func testPickingAgainStartsTheClockOver() {
        let start = date("2026-10-15")
        TestScenario.switchTo(.pushedToday, now: start)
        TestScenario.switchTo(.missedYesterday, now: start.addingTimeInterval(40 * 3600))

        XCTAssertEqual(TestScenario.current(asOf: start.addingTimeInterval(60 * 3600)), .missedYesterday)
        XCTAssertEqual(TestScenario.endsAt(asOf: start.addingTimeInterval(60 * 3600)), start.addingTimeInterval((40 + 48) * 3600))
    }

    func testATestWithNoStartTimeIsTreatedAsOver() {
        // What an earlier TestFlight build left behind: a scenario, no start time.
        AppConfig.sharedDefaults.set(TestScenario.missedYesterday.rawValue, forKey: "test-scenario")
        AppConfig.sharedDefaults.removeObject(forKey: "test-scenario-started")

        XCTAssertEqual(TestScenario.current, .off)
        TestScenario.expireIfNeeded()
        XCTAssertNil(AppConfig.sharedDefaults.string(forKey: "test-scenario"))
    }

    func testResettingWhenNothingIsRunningChangesNothing() {
        let real = weekendsOff()
        AppConfig.streakProtection = real
        TestScenario.reset()
        TestScenario.expireIfNeeded()
        XCTAssertEqual(AppConfig.streakProtection, real)
    }
}
