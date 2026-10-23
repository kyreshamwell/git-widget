import WidgetKit

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: ContributionSnapshot?
    /// Always a style that can be drawn: Daily Rotation and the saved style
    /// picked in Edit Widget have been turned into the real thing by now.
    let style: WidgetStyle
    let layout: WidgetLayout
    /// How many weeks of graph, already settled between this widget's Range
    /// and the app's time range.
    let weeks: Int
    let stat: WidgetStat
    /// Read when the entry is made, so editing a saved style in the app and
    /// reloading timelines is all it takes to repaint the widgets wearing it.
    let custom: CustomWidgetStyle
    /// Rest days and freezes, read the same way.
    let protection: StreakProtection

    init(
        date: Date,
        snapshot: ContributionSnapshot?,
        style: WidgetStyle = .classic,
        layout: WidgetLayout = .graph,
        weeks: Int = AppConfig.widgetWeeks,
        stat: WidgetStat = .streak,
        custom: CustomWidgetStyle = .default,
        protection: StreakProtection = AppConfig.streakProtection
    ) {
        self.date = date
        self.snapshot = snapshot
        self.style = style
        self.layout = layout
        self.weeks = weeks
        self.stat = stat
        self.custom = custom
        self.protection = protection
    }

    /// The look is worked out for the entry's own date, so an entry made for
    /// midnight already wears tomorrow's turn of the rotation.
    init(date: Date, snapshot: ContributionSnapshot?, configuration: WidgetOptionsIntent) {
        let look = AppConfig.styleLibrary.look(
            for: configuration.style,
            saved: configuration.saved.flatMap { UUID(uuidString: $0.id) },
            on: date
        )
        self.init(
            date: date,
            snapshot: snapshot,
            style: look.style,
            layout: configuration.layout,
            weeks: configuration.range.weeks ?? AppConfig.widgetWeeks,
            stat: configuration.stat,
            custom: look.custom
        )
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

    func timeline(for configuration: WidgetOptionsIntent, in context: Context) async -> Timeline<StreakEntry> {
        let refresh = await WidgetRefresh.run(now: Date())
        return Timeline(
            entries: refresh.entryDates.map {
                StreakEntry(date: $0, snapshot: refresh.snapshot, configuration: configuration)
            },
            policy: refresh.policy
        )
    }
}

/// The work behind every Pushed widget's timeline: fresh data if it's due,
/// and when to come back.
///
/// Doubles as the notification reconciliation hook. This is the only code in
/// the app iOS runs on a schedule with fresh GitHub data, so it's what cancels
/// "you haven't pushed today" once you actually have. No extra background
/// budget needed, it was already running for the widget.
struct WidgetRefresh {
    let snapshot: ContributionSnapshot?
    let entryDates: [Date]
    let policy: TimelineReloadPolicy

    static func run(now: Date) async -> WidgetRefresh {
        TestScenario.expireIfNeeded(now: now)

        #if DEBUG
        if DemoMode.isActive {
            return WidgetRefresh(snapshot: ContributionSnapshot.load(), entryDates: entryDates(from: now), policy: .never)
        }
        #endif

        let username = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey)
        let token = KeychainHelper.read(account: AppConfig.keychainAccount)

        guard let username, let token, !username.isEmpty, !token.isEmpty else {
            return WidgetRefresh(snapshot: nil, entryDates: [now], policy: .after(now.addingTimeInterval(3600)))
        }

        var snapshot = ContributionSnapshot.load()

        // Every widget with its own options gets its own timeline call, and
        // the app reloads them all as a style is edited. Data fetched moments
        // ago by one of those calls, or by the app's own refresh, is as fresh
        // as a new request would be.
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
        return WidgetRefresh(
            snapshot: TestScenario.current.snapshot(replacing: snapshot, now: now),
            entryDates: entryDates(from: now),
            policy: .after(now.addingTimeInterval(outcome.refreshInterval(now: now)))
        )
    }

    /// Now, and the coming midnight. Each entry is drawn for its own date, so
    /// the second one already shows the new day: yesterday's "committed
    /// today" is gone and a rest day is marked the moment it starts, even if
    /// iOS is late with the next refresh.
    static func entryDates(from now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Date] {
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return [now]
        }
        return [now, midnight]
    }
}
