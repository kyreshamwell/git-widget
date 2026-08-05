import Foundation
import UserNotifications

/// Seam over UNUserNotificationCenter so the diffing logic can be tested with a
/// fake instead of a device.
protocol NotificationCentering {
    func pendingIdentifiers() async -> [String]
    /// Returns whether iOS accepted the request. A rejected add is silent
    /// otherwise, which would leave the app believing a reminder is queued when
    /// nothing is.
    @discardableResult
    func add(_ planned: PlannedNotification) async -> Bool
    func remove(identifiers: [String]) async
    func isAuthorized() async -> Bool
}

enum ManagedNotification {
    static let prefixes = ["daily-", "milestone-", "token-"]

    static func isManaged(_ identifier: String) -> Bool {
        prefixes.contains { identifier.hasPrefix($0) }
    }

    /// Only the day slots get actively cancelled. Milestones and token warnings
    /// are fire-and-forget: once queued they're allowed to ride, because the
    /// plan that produced them stops reproducing them the moment they're
    /// recorded as celebrated — and re-diffing would silently delete a
    /// celebration that's waiting out quiet hours.
    static func isCancellable(_ identifier: String) -> Bool {
        identifier.hasPrefix("daily-")
    }
}

struct ReconcileOutcome: Equatable {
    var added: [String] = []
    var removed: [String] = []
    var planned: [PlannedNotification] = []
    var celebrated: Int?
    var alertedAuthFailure = false

    /// How long the widget should wait before its next timeline refresh. Inside
    /// the run-up to a slot the cadence tightens, which shrinks the window in
    /// which you push but the app hasn't noticed yet — the one case that can
    /// produce a nudge for something you already did.
    func refreshInterval(now: Date) -> TimeInterval {
        let imminent = planned.contains {
            $0.id.hasPrefix("daily-") && $0.fireDate.timeIntervalSince(now) <= 3 * 3600
        }
        return imminent ? 30 * 60 : 2 * 3600
    }
}

/// Turns a plan into actual calls on the notification center. Adds anything
/// planned that isn't already queued, and cancels day slots that the plan no
/// longer wants — that cancellation is the mechanic that stops "you haven't
/// pushed today" from firing after you've pushed.
struct NotificationScheduler {
    let center: NotificationCentering

    @discardableResult
    func reconcile(_ context: NotificationContext) async -> ReconcileOutcome {
        let pending = await center.pendingIdentifiers()

        guard context.settings.enabled, await center.isAuthorized() else {
            let managed = pending.filter(ManagedNotification.isManaged)
            if !managed.isEmpty { await center.remove(identifiers: managed) }
            return ReconcileOutcome(removed: managed)
        }

        let plan = NotificationPlanner.plan(context)
        let plannedIDs = Set(plan.map(\.id))
        let pendingIDs = Set(pending)

        let stale = pending.filter {
            ManagedNotification.isCancellable($0) && !plannedIDs.contains($0)
        }
        if !stale.isEmpty { await center.remove(identifiers: stale) }

        var outcome = ReconcileOutcome(removed: stale, planned: plan)
        for item in plan where !pendingIDs.contains(item.id) {
            guard await center.add(item) else { continue }
            outcome.added.append(item.id)

            if item.id.hasPrefix("milestone-") {
                outcome.celebrated = Int(item.id.dropFirst("milestone-".count))
            }
            if item.id == "token-expired" {
                outcome.alertedAuthFailure = true
            }
        }
        return outcome
    }

    /// Settings changes reuse the same identifiers with different fire times,
    /// so the additive diff alone would leave the old time in place. Dropping
    /// the day slots first forces them to be re-added at the new time.
    func resetDaySlots() async {
        let stale = await center.pendingIdentifiers().filter(ManagedNotification.isCancellable)
        if !stale.isEmpty { await center.remove(identifiers: stale) }
    }

    func removeAllManaged() async {
        let managed = await center.pendingIdentifiers().filter(ManagedNotification.isManaged)
        if !managed.isEmpty { await center.remove(identifiers: managed) }
    }

    func removeTokenNotifications() async {
        let token = await center.pendingIdentifiers().filter { $0.hasPrefix("token-") }
        if !token.isEmpty { await center.remove(identifiers: token) }
    }
}

// MARK: - Real center

struct SystemNotificationCenter: NotificationCentering {
    private var center: UNUserNotificationCenter { .current() }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    @discardableResult
    func add(_ planned: PlannedNotification) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default

        let interval = max(1, planned.fireDate.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: planned.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            SystemNotificationCenter.lastAddError = error.localizedDescription
            return false
        }
    }

    /// Kept so a rejected add can be inspected rather than vanishing.
    nonisolated(unsafe) static var lastAddError: String?

    func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Grants quietly, with no permission alert — notifications land in
    /// Notification Center instead of on screen. Used by the headless
    /// self-check so it can exercise the real center without a human tap.
    static func requestProvisionalAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .provisional])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: - Coordinator

/// Builds the planner's context from stored state, reconciles, then writes back
/// the bits that must not repeat (which milestone was celebrated, when we last
/// complained about a dead token). Called from the widget timeline refresh, app
/// foreground, and the background refresh task.
enum NotificationCoordinator {
    @discardableResult
    static func reconcile(
        snapshot: ContributionSnapshot? = ContributionSnapshot.load(),
        center: NotificationCentering = SystemNotificationCenter(),
        now: Date = Date()
    ) async -> ReconcileOutcome {
        let context = NotificationContext(
            snapshot: snapshot,
            settings: AppConfig.notificationSettings,
            tokenExpiry: AppConfig.tokenExpiry,
            lastCelebratedStreak: AppConfig.lastCelebratedStreak,
            authFailed: AppConfig.authFailed,
            lastAuthAlertAt: AppConfig.lastAuthAlertAt,
            now: now
        )

        let outcome = await NotificationScheduler(center: center).reconcile(context)

        if let celebrated = outcome.celebrated {
            AppConfig.lastCelebratedStreak = celebrated
        }
        if outcome.alertedAuthFailure {
            AppConfig.lastAuthAlertAt = now
        }
        return outcome
    }
}
