import WidgetKit

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: ContributionSnapshot?
    let style: WidgetStyle
    let layout: WidgetLayout
    /// Read when the entry is made, so editing the custom style in the app and
    /// reloading timelines is all it takes to repaint Custom widgets.
    let custom: CustomWidgetStyle

    init(
        date: Date,
        snapshot: ContributionSnapshot?,
        style: WidgetStyle = .classic,
        layout: WidgetLayout = .graph,
        custom: CustomWidgetStyle = AppConfig.customStyle
    ) {
        self.date = date
        self.snapshot = snapshot
        self.style = style
        self.layout = layout
        self.custom = custom
    }

    init(date: Date, snapshot: ContributionSnapshot?, configuration: WidgetOptionsIntent) {
        self.init(date: date, snapshot: snapshot, style: configuration.style, layout: configuration.layout)
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: ContributionSnapshot.load() ?? .sample())
    }

    /// The widget gallery and Edit Widget ask for this before anyone has
    /// connected an account, and "Open Pushed and add your token" is a poor
    /// way to show what a style looks like. Previews get sample data until
    /// there's real data to show.
    func snapshot(for configuration: WidgetOptionsIntent, in context: Context) async -> StreakEntry {
        let snapshot = ContributionSnapshot.load() ?? (context.isPreview ? .sample() : nil)
        return StreakEntry(date: Date(), snapshot: snapshot, configuration: configuration)
    }

    /// Doubles as the notification reconciliation hook. This is the only code
    /// in the app iOS runs on a schedule with fresh GitHub data, so it's what
    /// cancels "you haven't pushed today" once you actually have. No extra
    /// background budget needed, it was already running for the widget.
    func timeline(for configuration: WidgetOptionsIntent, in context: Context) async -> Timeline<StreakEntry> {
        #if DEBUG
        if DemoMode.isActive {
            let entry = StreakEntry(date: Date(), snapshot: ContributionSnapshot.load(), configuration: configuration)
            return Timeline(entries: [entry], policy: .never)
        }
        #endif

        let username = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey)
        let token = KeychainHelper.read(account: AppConfig.keychainAccount)

        guard let username, let token, !username.isEmpty, !token.isEmpty else {
            let entry = StreakEntry(date: Date(), snapshot: nil, configuration: configuration)
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        }

        let now = Date()
        var snapshot = ContributionSnapshot.load()

        // Every widget with its own options gets its own timeline call, and
        // the app reloads them all as a custom style is edited. Data fetched
        // moments ago by one of those calls, or by the app's own refresh, is
        // as fresh as a new request would be.
        let fetchedRecently = snapshot.map { now.timeIntervalSince($0.fetchedAt) < 120 } ?? false

        if !fetchedRecently {
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
                // Network hiccup: fall back to the last known snapshot so the
                // widget doesn't go blank. The planner's freshness guard takes
                // it from here if this keeps failing.
            }
        }

        let outcome = await NotificationCoordinator.reconcile(snapshot: snapshot, now: now)
        let entry = StreakEntry(date: now, snapshot: snapshot, configuration: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(now.addingTimeInterval(outcome.refreshInterval(now: now)))
        )
    }
}
