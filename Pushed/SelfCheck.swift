#if DEBUG
import Foundation
import UserNotifications

/// End-to-end check against the *real* UNUserNotificationCenter, driven by a
/// launch argument so it can run headless:
///
///     xcrun simctl launch --console-pty <device> com.kyreshamwell.pushed -PushedSelfCheck
///
/// Unit tests prove the planner picks the right notifications; this proves iOS
/// actually accepts them, holds them at the times we asked for, and drops them
/// again when the plan says to cancel. That last part is the whole mechanic
/// behind "don't nag someone who already pushed", and a fake center can't
/// prove it.
enum SelfCheck {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-PushedSelfCheck")
    }

    /// Authorization is a system alert that needs a human tap, so the check
    /// forces that one bit and exercises everything else for real.
    private struct AuthorizedCenter: NotificationCentering {
        let inner = SystemNotificationCenter()
        func pendingIdentifiers() async -> [String] { await inner.pendingIdentifiers() }
        @discardableResult
        func add(_ planned: PlannedNotification) async -> Bool { await inner.add(planned) }
        func remove(identifiers: [String]) async { await inner.remove(identifiers: identifiers) }
        func isAuthorized() async -> Bool { true }
    }

    private static var failures = 0

    private static func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        if passed {
            print("  PASS  \(name)")
        } else {
            failures += 1
            print("  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func run() async {
        print("\n===== Pushed notification self-check =====")

        let status = await SystemNotificationCenter.authorizationStatus()
        print("  authorization status: \(status.rawValue) (0=notDetermined 1=denied 2=authorized 3=provisional)")
        // Provisional grants silently — no alert to tap, so a headless run can
        // still exercise the real notification center. iOS drops requests from
        // an unauthorized app without raising an error, which is why an
        // unauthorized run shows up as "nothing queued" rather than a failure.
        if status == .notDetermined {
            let granted = await SystemNotificationCenter.requestProvisionalAuthorization()
            print("  provisional authorization -> \(granted ? "granted" : "denied")")
        }

        let center = AuthorizedCenter()
        let scheduler = NotificationScheduler(center: center)
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let today = ContributionCalendar.dateFormatter.string(from: now)

        // Slots a few minutes out so the plan produces genuinely future fire
        // dates rather than clamped ones.
        guard let middayAt = calendar.date(byAdding: .minute, value: 5, to: now),
              let eveningAt = calendar.date(byAdding: .minute, value: 10, to: now),
              calendar.isDate(middayAt, inSameDayAs: now),
              calendar.isDate(eveningAt, inSameDayAs: now) else {
            print("  SKIP  too close to midnight to run\n")
            exit(0)
        }

        var settings = NotificationSettings.default
        settings.enabled = true
        settings.middayHour = calendar.component(.hour, from: middayAt)
        settings.middayMinute = calendar.component(.minute, from: middayAt)
        settings.eveningHour = calendar.component(.hour, from: eveningAt)
        settings.eveningMinute = calendar.component(.minute, from: eveningAt)
        AppConfig.notificationSettings = settings
        AppConfig.resetNotificationState()

        await scheduler.removeAllManaged()

        // 1 — streak on the line: both slots queued, with the real number.
        print("\n[1] Streak at risk (13 days, nothing pushed today)")
        seed(lastActiveDaysAgo: 1, streakLength: 13)
        AppConfig.lastCelebratedStreak = 7
        await NotificationCoordinator.reconcile(center: center)

        var pending = await requests()
        if let error = SystemNotificationCenter.lastAddError {
            print("  iOS rejected an add: \(error)")
        }
        let midday = pending["daily-midday-\(today)"]
        let evening = pending["daily-evening-\(today)"]
        check("midday slot queued", midday != nil)
        check("evening slot queued", evening != nil)
        check("midday title carries the real streak", midday?.content.title == "13-day streak",
              "got \(midday?.content.title ?? "nil")")
        check("evening title carries the real streak",
              evening?.content.title == "Your 13-day streak ends at midnight",
              "got \(evening?.content.title ?? "nil")")

        if let fire = fireDate(midday) {
            let drift = abs(fire.timeIntervalSince(middayAt))
            check("midday fires at the configured time", drift < 90, "off by \(Int(drift))s")
        } else {
            check("midday fires at the configured time", false, "no trigger")
        }
        if let fire = fireDate(evening) {
            check("evening fires after midday", fire > (fireDate(midday) ?? now))
        }

        // 2 — the cancel mechanic. This is the one that matters.
        print("\n[2] Pushed today — slots must be withdrawn")
        seed(lastActiveDaysAgo: 0, streakLength: 14)
        AppConfig.lastCelebratedStreak = 14 // don't let a milestone muddy the read
        await NotificationCoordinator.reconcile(center: center)

        pending = await requests()
        check("midday withdrawn", pending["daily-midday-\(today)"] == nil)
        check("evening withdrawn", pending["daily-evening-\(today)"] == nil)

        // 3 — dormant day one names the streak that died, and stays to one slot.
        print("\n[3] Dormant day 1 after a 15-day streak")
        await scheduler.resetDaySlots()
        seed(lastActiveDaysAgo: 2, streakLength: 15)
        await NotificationCoordinator.reconcile(center: center)

        pending = await requests()
        check("single day slot queued",
              pending.keys.filter { $0.hasPrefix("daily-") }.count == 1,
              "got \(pending.keys.filter { $0.hasPrefix("daily-") }.sorted())")
        check("names the lost streak",
              pending["daily-midday-\(today)"]?.content.title == "Your 15-day streak ended",
              "got \(pending["daily-midday-\(today)"]?.content.title ?? "nil")")
        check("no evening deadline when nothing is at stake",
              pending["daily-evening-\(today)"] == nil)

        // 4 — token ladder lands on the right days.
        print("\n[4] Token expiring in 11 days")
        let expiry = calendar.date(byAdding: .day, value: 11, to: now)!
        AppConfig.tokenExpiry = expiry
        await scheduler.removeTokenNotifications()
        await NotificationCoordinator.reconcile(center: center)

        pending = await requests()
        check("10-day warning queued", pending["token-expiring-10"] != nil)
        check("5-day warning queued", pending["token-expiring-5"] != nil)
        check("1-day warning queued", pending["token-expiring-1"] != nil)
        if let fire = fireDate(pending["token-expiring-5"]) {
            let expectedDay = calendar.date(byAdding: .day, value: 6, to: now)!
            check("5-day warning lands on the right day",
                  calendar.isDate(fire, inSameDayAs: expectedDay),
                  "got \(fire)")
            check("5-day warning lands mid-morning",
                  calendar.component(.hour, from: fire) == 10,
                  "hour \(calendar.component(.hour, from: fire))")
        }

        // 5 — a dead token silences commit nudges.
        print("\n[5] Token rejected — commit nudges must go quiet")
        await scheduler.resetDaySlots()
        seed(lastActiveDaysAgo: 1, streakLength: 13)
        AppConfig.authFailed = true
        AppConfig.lastAuthAlertAt = nil
        await NotificationCoordinator.reconcile(center: center)

        pending = await requests()
        check("reconnect alert queued", pending["token-expired"] != nil)
        check("no nudges while data is untrusted",
              pending.keys.filter { $0.hasPrefix("daily-") }.isEmpty,
              "got \(pending.keys.filter { $0.hasPrefix("daily-") }.sorted())")

        // 6 — the part queueing alone can't prove: does it actually arrive?
        print("\n[6] Delivery (waiting ~8s for a real fire)")
        await scheduler.removeAllManaged()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        let probeID = "daily-delivery-probe"
        let accepted = await center.add(PlannedNotification(
            id: probeID,
            title: "13-day streak",
            body: "Nothing pushed yet today.",
            fireDate: now.addingTimeInterval(5)
        ))
        check("iOS accepted the request", accepted)

        try? await Task.sleep(nanoseconds: 8_000_000_000)

        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let probe = delivered.first { $0.request.identifier == probeID }
        check("notification actually fired", probe != nil,
              "delivered: \(delivered.map(\.request.identifier))")
        check("delivered copy is intact", probe?.request.content.title == "13-day streak")

        let stillPending = await requests()
        check("cleared from pending once delivered", stillPending[probeID] == nil)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // Leave the device clean.
        AppConfig.authFailed = false
        AppConfig.resetNotificationState()
        await scheduler.removeAllManaged()
        AppConfig.sharedDefaults.removeObject(forKey: ContributionSnapshot.defaultsKey)

        print("\n===== \(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED") =====\n")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    private static func seed(lastActiveDaysAgo: Int, streakLength: Int) {
        let span = 200
        var levels = Array(repeating: 0, count: span)
        let lastIndex = span - 1 - lastActiveDaysAgo
        if streakLength > 0, lastIndex >= 0 {
            for index in max(0, lastIndex - streakLength + 1)...lastIndex { levels[index] = 2 }
        }
        ContributionSnapshot(
            totalContributions: streakLength,
            recentLevels: levels,
            lastDate: ContributionCalendar.dateFormatter.string(from: Date()),
            fetchedAt: Date()
        ).save()
    }

    private static func requests() async -> [String: UNNotificationRequest] {
        let all = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Dictionary(uniqueKeysWithValues: all.map { ($0.identifier, $0) })
    }

    private static func fireDate(_ request: UNNotificationRequest?) -> Date? {
        (request?.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
    }
}
#endif
