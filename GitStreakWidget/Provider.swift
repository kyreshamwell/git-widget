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

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let username = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey)
        let token = KeychainHelper.read(account: AppConfig.keychainAccount)

        guard let username, let token, !username.isEmpty, !token.isEmpty else {
            let entry = StreakEntry(date: Date(), snapshot: nil)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
            return
        }

        Task {
            let nextRefresh = Date().addingTimeInterval(2 * 3600)
            do {
                let calendar = try await GitHubContributionsService.fetchCalendar(username: username, token: token)
                let snapshot = ContributionSnapshot.from(calendar)
                snapshot.save()
                let entry = StreakEntry(date: Date(), snapshot: snapshot)
                completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
            } catch {
                // Fall back to the last known snapshot so the widget doesn't go blank on a network hiccup.
                let entry = StreakEntry(date: Date(), snapshot: ContributionSnapshot.load())
                completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
            }
        }
    }
}
