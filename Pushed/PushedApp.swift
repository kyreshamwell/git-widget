import BackgroundTasks
import SwiftUI
import UserNotifications
import WidgetKit

/// Without a delegate, iOS silently discards notifications that come due while
/// the app is open. Showing the banner anyway matters more than keeping the UI
/// unobstructed: a reminder that arrives invisibly is indistinguishable from a
/// reminder that never fired, which is exactly how a working feature gets
/// reported as broken.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@main
struct PushedApp: App {
    static let refreshTaskID = "com.kyreshamwell.pushed.refresh"

    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared

        // Backup reconciliation path for anyone who hasn't added the widget —
        // without a widget there's no timeline refresh, so this is the only
        // background hook left. iOS grants these opportunistically, which is
        // exactly why it's the backup and not the primary.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: PushedApp.refreshTaskID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            PushedApp.handle(refreshTask)
        }

        #if DEBUG
        if SelfCheck.isRequested {
            Task { await SelfCheck.run() }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Foregrounding is the most accurate reconciliation available —
                // fresh data, no background budget in the way.
                Task { await NotificationCoordinator.reconcile() }
            case .background:
                PushedApp.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh() // queue the next one before doing any work

        let work = Task {
            let username = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey)
            let token = KeychainHelper.read(account: AppConfig.keychainAccount)
            var snapshot = ContributionSnapshot.load()

            if let username, let token, !username.isEmpty, !token.isEmpty {
                do {
                    let fetch = try await GitHubContributionsService.fetch(username: username, token: token)
                    let fresh = ContributionSnapshot.from(fetch.calendar)
                    fresh.save()
                    snapshot = fresh
                    if let expiry = fetch.tokenExpiry { AppConfig.tokenExpiry = expiry }
                    AppConfig.authFailed = false
                    WidgetCenter.shared.reloadAllTimelines()
                } catch GitHubServiceError.unauthorized {
                    AppConfig.authFailed = true
                } catch {
                    // Keep the cached snapshot; the freshness guard handles it.
                }
            }

            await NotificationCoordinator.reconcile(snapshot: snapshot)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = { work.cancel() }
    }
}
