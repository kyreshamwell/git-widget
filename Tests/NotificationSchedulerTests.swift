import UserNotifications
import XCTest

private final class FakeCenter: NotificationCentering {
    var pending: [String] = []
    var authorized = true
    private(set) var added: [PlannedNotification] = []
    private(set) var removed: [String] = []

    func pendingIdentifiers() async -> [String] { pending }

    @discardableResult
    func add(_ planned: PlannedNotification) async -> Bool {
        added.append(planned)
        pending.append(planned.id)
        return true
    }

    func remove(identifiers: [String]) async {
        removed.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0) }
    }

    func isAuthorized() async -> Bool { authorized }
}

final class NotificationSchedulerTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private let cal = Calendar(identifier: .gregorian)

    private func now(_ hour: Int) -> Date {
        var components = cal.dateComponents([.year, .month, .day], from: formatter.date(from: "2026-08-04")!)
        components.hour = hour
        return cal.date(from: components)!
    }

    private var todayKey: String { formatter.string(from: now(9)) }
    private var yesterdayKey: String {
        formatter.string(from: cal.date(byAdding: .day, value: -1, to: now(9))!)
    }

    private func snapshot(now: Date, lastActiveDaysAgo: Int, streakLength: Int) -> ContributionSnapshot {
        var levels = Array(repeating: 0, count: 200)
        if streakLength > 0 {
            let lastIndex = 199 - lastActiveDaysAgo
            for index in max(0, lastIndex - streakLength + 1)...lastIndex { levels[index] = 2 }
        }
        return ContributionSnapshot(
            totalContributions: streakLength,
            recentLevels: levels,
            lastDate: formatter.string(from: now),
            fetchedAt: now
        )
    }

    private func context(
        hour: Int = 9,
        lastActiveDaysAgo: Int,
        streakLength: Int,
        lastCelebrated: Int = 0
    ) -> NotificationContext {
        var settings = NotificationSettings.default
        settings.enabled = true
        let moment = now(hour)
        return NotificationContext(
            snapshot: snapshot(now: moment, lastActiveDaysAgo: lastActiveDaysAgo, streakLength: streakLength),
            settings: settings,
            lastCelebratedStreak: lastCelebrated,
            now: moment
        )
    }

    // MARK: - The cancel mechanic

    func testCancelsTodaysSlotsOncePushed() async {
        let center = FakeCenter()
        center.pending = ["daily-midday-\(todayKey)", "daily-evening-\(todayKey)"]

        await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 0, streakLength: 12, lastCelebrated: 7))

        XCTAssertEqual(center.removed.sorted(), ["daily-evening-\(todayKey)", "daily-midday-\(todayKey)"])
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testMilestoneBaselineStopsRetroCelebratingOnFirstConnect() async {
        // Connecting with an existing 12-day streak must not fire "7 days
        // straight" for a milestone passed before the app was installed.
        let existing = snapshot(now: now(9), lastActiveDaysAgo: 0, streakLength: 12)
        XCTAssertEqual(NotificationPlanner.milestoneBaseline(for: existing, asOf: now(9)), 7)

        let center = FakeCenter()
        let outcome = await NotificationScheduler(center: center).reconcile(
            context(lastActiveDaysAgo: 0, streakLength: 12,
                    lastCelebrated: NotificationPlanner.milestoneBaseline(for: existing, asOf: now(9)))
        )
        XCTAssertTrue(outcome.added.isEmpty)
    }

    func testKeepsSlotsQueuedWhileStillUnpushed() async {
        let center = FakeCenter()
        center.pending = ["daily-midday-\(todayKey)", "daily-evening-\(todayKey)"]

        let outcome = await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 1, streakLength: 12))

        XCTAssertTrue(center.removed.isEmpty)
        XCTAssertTrue(outcome.added.isEmpty, "already pending — must not double-add")
    }

    func testSweepsYesterdaysLeftoverSlot() async {
        let center = FakeCenter()
        center.pending = ["daily-midday-\(yesterdayKey)"]

        await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 1, streakLength: 5))

        XCTAssertEqual(center.removed, ["daily-midday-\(yesterdayKey)"])
        XCTAssertTrue(center.added.contains { $0.id == "daily-midday-\(todayKey)" })
    }

    // MARK: - Fire-and-forget categories

    func testLeavesAQueuedMilestoneAloneAfterItIsRecorded() async {
        // The celebration is waiting out quiet hours; the plan no longer emits
        // it because lastCelebratedStreak already advanced. Deleting it here
        // would mean the milestone silently never arrives.
        let center = FakeCenter()
        center.pending = ["milestone-14"]

        await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 0, streakLength: 14, lastCelebrated: 14))

        XCTAssertTrue(center.removed.isEmpty)
        XCTAssertEqual(center.pending, ["milestone-14"])
    }

    func testLeavesQueuedTokenWarningsAlone() async {
        let center = FakeCenter()
        center.pending = ["token-expiring-10", "token-expiring-5"]

        await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 0, streakLength: 3))

        XCTAssertTrue(center.removed.isEmpty)
    }

    func testNeverTouchesIdentifiersItDoesNotOwn() async {
        let center = FakeCenter()
        center.pending = ["some-other-feature", "daily-midday-\(yesterdayKey)"]

        await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 0, streakLength: 3))

        XCTAssertFalse(center.removed.contains("some-other-feature"))
        XCTAssertTrue(center.pending.contains("some-other-feature"))
    }

    // MARK: - Off switches

    func testDisablingClearsEverythingManaged() async {
        let center = FakeCenter()
        center.pending = ["daily-midday-\(todayKey)", "milestone-14", "token-expiring-5", "unrelated"]

        var ctx = context(lastActiveDaysAgo: 1, streakLength: 12)
        ctx.settings.enabled = false
        await NotificationScheduler(center: center).reconcile(ctx)

        XCTAssertEqual(center.pending, ["unrelated"])
    }

    func testRevokedPermissionClearsEverythingManaged() async {
        let center = FakeCenter()
        center.authorized = false
        center.pending = ["daily-midday-\(todayKey)", "milestone-14"]

        await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 1, streakLength: 12))

        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertTrue(center.added.isEmpty)
    }

    func testResetDaySlotsDropsOnlyDaySlots() async {
        let center = FakeCenter()
        center.pending = ["daily-midday-\(todayKey)", "milestone-14", "token-expiring-1"]

        await NotificationScheduler(center: center).resetDaySlots()

        XCTAssertEqual(center.pending.sorted(), ["milestone-14", "token-expiring-1"])
    }

    // MARK: - Side effects reported back

    func testReportsWhichMilestoneWasCelebrated() async {
        let center = FakeCenter()
        let outcome = await NotificationScheduler(center: center)
            .reconcile(context(hour: 14, lastActiveDaysAgo: 0, streakLength: 30, lastCelebrated: 14))

        XCTAssertEqual(outcome.celebrated, 30)
        XCTAssertEqual(outcome.added, ["milestone-30"])
    }

    func testReportsAuthFailureAlertSoItCanCoolDown() async {
        let center = FakeCenter()
        var ctx = context(lastActiveDaysAgo: 1, streakLength: 12)
        ctx.authFailed = true

        let outcome = await NotificationScheduler(center: center).reconcile(ctx)

        XCTAssertTrue(outcome.alertedAuthFailure)
        XCTAssertEqual(outcome.added, ["token-expired"])
    }

    func testContentReachingTheCenterCarriesTheRealNumbers() async {
        let center = FakeCenter()
        await NotificationScheduler(center: center)
            .reconcile(context(lastActiveDaysAgo: 1, streakLength: 18))

        let midday = center.added.first { $0.id.hasPrefix("daily-midday") }
        XCTAssertEqual(midday?.title, "18-day streak")
        let evening = center.added.first { $0.id.hasPrefix("daily-evening") }
        XCTAssertEqual(evening?.title, "18 days on the line")
    }

    // MARK: - Trigger construction
    //
    // The planner picks a wall-clock time; an interval trigger counts elapsed
    // seconds instead, so a DST boundary between scheduling and firing moves a
    // 10am token warning to 9am or 11am.

    func testDistantFiresAreAnchoredToTheWallClockNotAnElapsedInterval() throws {
        let target = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let trigger = try XCTUnwrap(
            SystemNotificationCenter.trigger(for: target) as? UNCalendarNotificationTrigger
        )

        XCTAssertEqual(trigger.dateComponents.hour, Calendar.current.component(.hour, from: target))
        XCTAssertEqual(trigger.dateComponents.minute, Calendar.current.component(.minute, from: target))
        XCTAssertFalse(trigger.repeats)
    }

    func testImminentFiresKeepTheIntervalTrigger() throws {
        // Milestones are scheduled seconds out; matching those on calendar
        // components is a race against the second hand for no benefit.
        let trigger = try XCTUnwrap(
            SystemNotificationCenter.trigger(for: Date().addingTimeInterval(5))
                as? UNTimeIntervalNotificationTrigger
        )
        XCTAssertLessThanOrEqual(trigger.timeInterval, 5)
        XCTAssertGreaterThanOrEqual(trigger.timeInterval, 1)
    }

    func testAFireTimeAlreadyInThePastIsClampedRatherThanRejected() throws {
        let trigger = try XCTUnwrap(
            SystemNotificationCenter.trigger(for: Date().addingTimeInterval(-600))
                as? UNTimeIntervalNotificationTrigger
        )
        XCTAssertEqual(trigger.timeInterval, 1, "iOS rejects a non-positive interval outright")
    }
}
