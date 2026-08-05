import WidgetKit

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: ContributionSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: ContributionSnapshot.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: Date(), snapshot: ContributionSnapshot.load()))
    }

    /// Doubles as the notification reconciliation hook. This is the only code
    /// in the app iOS runs on a schedule with fresh GitHub data, so it's what
    /// cancels "you haven't pushed today" once you actually have — no extra
    /// background budget needed, it was already running for the widget.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let username = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey)
        let token = KeychainHelper.read(account: AppConfig.keychainAccount)

        guard let username, let token, !username.isEmpty, !token.isEmpty else {
            let entry = StreakEntry(date: Date(), snapshot: nil)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
            return
        }

        Task {
            let now = Date()
            var snapshot = ContributionSnapshot.load()

            do {
                let fetch = try await GitHubContributionsService.fetch(username: username, token: token)
                let fresh = ContributionSnapshot.from(fetch.calendar)
                fresh.save()
                snapshot = fresh

                if let expiry = fetch.tokenExpiry { AppConfig.tokenExpiry = expiry }
                AppConfig.authFailed = false
            } catch GitHubServiceError.unauthorized {
                AppConfig.authFailed = true
            } catch {
                // Network hiccup — fall back to the last known snapshot so the
                // widget doesn't go blank. The planner's freshness guard takes
                // it from here if this keeps failing.
            }

            let outcome = await NotificationCoordinator.reconcile(snapshot: snapshot, now: now)
            let entry = StreakEntry(date: now, snapshot: snapshot)
            completion(Timeline(
                entries: [entry],
                policy: .after(now.addingTimeInterval(outcome.refreshInterval(now: now)))
            ))
        }
    }
}
