import SwiftUI
import UIKit
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var username: String = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey) ?? ""
    @State private var token: String = KeychainHelper.read(account: AppConfig.keychainAccount) ?? ""
    @State private var snapshot: ContributionSnapshot? = ContributionSnapshot.load()
    @State private var widgetWeeks: Int = AppConfig.widgetWeeks
    @State private var streakIcon: String = AppConfig.streakIcon
    @State private var status: Status = .idle
    @State private var notifications: NotificationSettings = AppConfig.notificationSettings
    @State private var permissionDenied = false
    @State private var tokenExpiry: Date? = AppConfig.tokenExpiry

    enum Status: Equatable {
        case idle
        case loading
        case success
        case failed(String)
    }

    private var isConnected: Bool {
        !username.isEmpty && !token.isEmpty && snapshot != nil
    }

    var body: some View {
        NavigationStack {
            if isConnected {
                Form {
                    if let snapshot {
                        graphSection(snapshot)
                        statsSection(snapshot)
                        widgetSection
                    }
                    notificationSection
                    accountSection
                    if BuildEnvironment.showsDebugTools {
                        Section {
                            NavigationLink("Notification debug") { DebugNotificationsView() }
                        }
                    }
                }
                .navigationTitle("Pushed")
                .refreshable { await refresh() }
                .task { await refreshPermissionState() }
            } else {
                setupView
                    .navigationTitle("Pushed")
            }
        }
        // Turning notifications back on happens in iOS Settings, i.e. outside
        // this app — so the only moment we can notice is the return trip. `.task`
        // alone doesn't re-run on foreground, which left the red "notifications
        // are off" warning up until the next cold launch.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshPermissionState() }
        }
    }

    private func refreshPermissionState() async {
        let denied = await SystemNotificationCenter.authorizationStatus() == .denied
        await MainActor.run { permissionDenied = denied }
    }

    // MARK: - Setup (first launch / signed out)

    private var setupView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect your GitHub")
                        .font(.title3.bold())
                    Text("Pushed shows your contribution graph on your home screen. It needs two things: your GitHub username and an access token so it can read your contribution data. Setup takes about a minute.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Step 1 · Your username") {
                Link(destination: URL(string: "https://github.com/settings/profile")!) {
                    Label("Open your GitHub profile settings", systemImage: "arrow.up.right.square")
                }
                bullets([
                    "Your username is at the top of that page, under Public profile",
                    "It's also the name in your profile link: github.com/username",
                    "In the GitHub app: tap your profile picture — it's the grey @name under your display name",
                ])
            }

            Section {
                Link(destination: URL(string: "https://github.com/settings/tokens/new?scopes=read:user&description=Contribution%20Widget")!) {
                    Label("Open GitHub token settings", systemImage: "arrow.up.right.square")
                }
                bullets([
                    "Tap the link above — the permission it needs is already checked for you",
                    "Scroll to the bottom and tap the green Generate token button",
                    "Tap the copy icon next to the long code that appears",
                    "That code is your token — GitHub shows it only once, so copy it before leaving the page",
                ])
            } header: {
                Text("Step 2 · Your token")
            } footer: {
                Text("The token is read-only — it can see your contribution stats, never your code. It's stored in the iOS Keychain, the same place Safari keeps your passwords.")
            }

            Section("Step 3 · Connect") {
                TextField("GitHub username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Paste your token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await refresh() }
                } label: {
                    if status == .loading {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .disabled(username.isEmpty || token.isEmpty || status == .loading)

                if case .failed(let message) = status {
                    Text(message).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Step 4 · Add the widget") {
                bullets([
                    "Long-press anywhere on your home screen",
                    "Tap the + button in the top corner",
                    "Search for this app and pick a size",
                    "Done — it refreshes itself every couple of hours, no need to open this app again",
                ])
            }

            if BuildEnvironment.showsDebugTools {
                Section {
                    NavigationLink("Notification debug") { DebugNotificationsView() }
                }
            }
        }
    }

    /// Renders a list of strings as aligned bullet lines.
    private func bullets(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(line)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Graph

    private func graphSection(_ snapshot: ContributionSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ContributionGridView(
                    levels: snapshot.levels(forWeeks: widgetWeeks),
                    endDate: snapshot.endDate,
                    showsLabels: true
                )
                .frame(height: 104)

                HStack {
                    Text(rangeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    LegendView()
                }
            }
            .padding(.vertical, 4)

            DisclosureGroup("How to read this") {
                Text("""
                Each square is one day. Columns are weeks (oldest on the left), rows run Sunday to Saturday top to bottom — the same layout as your github.com profile.

                Color shows how active that day was relative to your own history: grey means no contributions, and the four greens are GitHub's intensity buckets (more contributions = darker). A "contribution" is a commit pushed to a default branch, an opened PR or issue, or a code review.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } header: {
            Text("Your Contributions")
        }
    }

    private func statsSection(_ snapshot: ContributionSnapshot) -> some View {
        Section("Stats") {
            LabeledContent("Current streak", value: "\(snapshot.currentStreak) day\(snapshot.currentStreak == 1 ? "" : "s")")
            LabeledContent("Committed today", value: snapshot.committedToday ? "Yes ✓" : "Not yet")
            LabeledContent("Contributions this year", value: "\(snapshot.totalContributions)")

            // Follows the time-range picker, so this always describes the exact
            // squares drawn above it. The old version hardcoded "26 wks" while
            // counting the full retained year, and ignored the picker entirely.
            let window = snapshot.levels(forWeeks: widgetWeeks)
            LabeledContent(
                "Green squares",
                value: "\(window.filter { $0 > 0 }.count) of \(window.count) days"
            )
            Text("Last synced \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)). Pull down to refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Widget settings

    private var rangeLabel: String {
        switch widgetWeeks {
        case 4: return "Last month"
        case 13: return "Last 3 months"
        case 26: return "Last 6 months"
        default: return "Last year"
        }
    }

    private var widgetSection: some View {
        Section {
            Picker("Time range", selection: $widgetWeeks) {
                Text("1 month").tag(4)
                Text("3 months").tag(13)
                Text("6 months").tag(26)
                Text("1 year").tag(52)
            }
            .onChange(of: widgetWeeks) { _, newValue in
                AppConfig.sharedDefaults.set(newValue, forKey: AppConfig.widgetWeeksKey)
                WidgetCenter.shared.reloadAllTimelines()
            }

            Picker("Streak icon", selection: $streakIcon) {
                ForEach(AppConfig.streakIconChoices, id: \.self) { choice in
                    Text(choice == "none" ? "Just the number" : choice).tag(choice)
                }
            }
            .onChange(of: streakIcon) { _, newValue in
                AppConfig.sharedDefaults.set(newValue, forKey: AppConfig.streakIconKey)
                WidgetCenter.shared.reloadAllTimelines()
            }
        } header: {
            Text("Widget")
        } footer: {
            Text("Time range applies to this graph and the home-screen widget. Fewer weeks = bigger squares.")
        }
    }

    // MARK: - Notifications

    private func time(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Builds the updated settings value and hands it straight to `apply`.
    /// Deliberately never reads `notifications` back after writing it —
    /// SwiftUI can return the pre-write value from @State inside the same
    /// closure, which silently persisted and scheduled the *old* time.
    private func timeBinding(
        hour: WritableKeyPath<NotificationSettings, Int>,
        minute: WritableKeyPath<NotificationSettings, Int>
    ) -> Binding<Date> {
        Binding(
            get: { time(hour: notifications[keyPath: hour], minute: notifications[keyPath: minute]) },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                var updated = notifications
                updated[keyPath: hour] = components.hour ?? 0
                updated[keyPath: minute] = components.minute ?? 0
                apply(updated)
            }
        )
    }

    private var notificationSection: some View {
        Section {
            Toggle("Daily reminders", isOn: Binding(
                get: { notifications.enabled },
                set: { wantsOn in
                    if wantsOn {
                        Task { await enableNotifications() }
                    } else {
                        var updated = notifications
                        updated.enabled = false
                        apply(updated)
                    }
                }
            ))

            if notifications.enabled {
                DatePicker(
                    "Midday check-in",
                    selection: timeBinding(hour: \.middayHour, minute: \.middayMinute),
                    displayedComponents: .hourAndMinute
                )

                DatePicker(
                    "Evening deadline",
                    selection: timeBinding(hour: \.eveningHour, minute: \.eveningMinute),
                    displayedComponents: .hourAndMinute
                )

                Toggle("Streak milestones", isOn: Binding(
                    get: { notifications.milestonesEnabled },
                    set: { var updated = notifications; updated.milestonesEnabled = $0; apply(updated) }
                ))

                Toggle("Token expiry warnings", isOn: Binding(
                    get: { notifications.tokenAlertsEnabled },
                    set: { var updated = notifications; updated.tokenAlertsEnabled = $0; apply(updated) }
                ))
            }

            if permissionDenied {
                Text("Notifications are turned off for Pushed in iOS Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            if notifications.enabled && !permissionDenied {
                Text(nextReminderDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Nothing fires on days you've already pushed. The midday check-in is a heads-up; the evening one only appears when a streak is genuinely on the line. Quiet days taper off on their own the longer you're away.")
        }
    }

    /// Shows exactly what will fire and when, using the same planner the
    /// scheduler runs. Without this, "nothing happened" is ambiguous between
    /// working-as-designed (you already pushed), a time that's already passed,
    /// and an actual bug — which is a miserable thing to debug from the outside.
    private var nextReminderDescription: String {
        let plan = NotificationPlanner.plan(
            NotificationContext(
                snapshot: snapshot,
                settings: notifications,
                tokenExpiry: AppConfig.tokenExpiry,
                lastCelebratedStreak: AppConfig.lastCelebratedStreak,
                authFailed: AppConfig.authFailed,
                lastAuthAlertAt: AppConfig.lastAuthAlertAt,
                now: Date()
            )
        ).filter { $0.id.hasPrefix("daily-") }

        guard let next = plan.min(by: { $0.fireDate < $1.fireDate }) else {
            if snapshot?.committedToday == true {
                return "Nothing today — you've already pushed. Reminders resume tomorrow."
            }
            if AppConfig.authFailed {
                return "Paused — reconnect your GitHub token first."
            }
            return "Nothing left today. Both times have already passed."
        }
        return "Next: \(next.fireDate.formatted(date: .omitted, time: .shortened)) — “\(next.title)”"
    }

    private func enableNotifications() async {
        let granted = await SystemNotificationCenter.requestAuthorization()
        await MainActor.run {
            permissionDenied = !granted
            var updated = notifications
            updated.enabled = granted
            apply(updated)
        }
    }

    /// Single write path for settings. Takes the new value explicitly rather
    /// than reading it back off @State, and drops the day slots before
    /// reconciling — they reuse the same identifiers, so the additive diff
    /// alone would leave the previous fire time in place.
    private func apply(_ settings: NotificationSettings) {
        notifications = settings
        AppConfig.notificationSettings = settings
        Task {
            await NotificationScheduler(center: SystemNotificationCenter()).resetDaySlots()
            await NotificationCoordinator.reconcile()
        }
    }

    // MARK: - Account (connected state)

    private var accountSection: some View {
        Section {
            LabeledContent("Signed in as", value: username)

            if let tokenExpiry {
                let days = Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: Date()),
                    to: Calendar.current.startOfDay(for: tokenExpiry)
                ).day ?? 0
                LabeledContent("Token expires") {
                    Text(days <= 0 ? "Expired" : "in \(days) day\(days == 1 ? "" : "s")")
                        .foregroundStyle(days <= 5 ? .red : days <= 10 ? .orange : .secondary)
                }
            }

            Button("Refresh now") {
                Task { await refresh() }
            }
            .disabled(status == .loading)

            Button("Disconnect", role: .destructive) {
                disconnect()
            }

            switch status {
            case .loading:
                ProgressView()
            case .failed(let message):
                Text(message).foregroundStyle(.red).font(.caption)
            case .success:
                Text("Connected ✓").foregroundStyle(.green).font(.caption)
            case .idle:
                EmptyView()
            }
        } header: {
            Text("GitHub Account")
        } footer: {
            Text("The widget refreshes itself every couple of hours in the background — no need to open this app. \"Refresh now\" is for when you just pushed and want the widget updated immediately.")
        }
    }

    private func disconnect() {
        KeychainHelper.delete(account: AppConfig.keychainAccount)
        AppConfig.sharedDefaults.removeObject(forKey: AppConfig.usernameDefaultsKey)
        AppConfig.sharedDefaults.removeObject(forKey: ContributionSnapshot.defaultsKey)
        AppConfig.resetNotificationState()
        username = ""
        token = ""
        snapshot = nil
        tokenExpiry = nil
        status = .idle
        Task { await NotificationScheduler(center: SystemNotificationCenter()).removeAllManaged() }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refresh() async {
        guard !username.isEmpty, !token.isEmpty else { return }

        // Reminder times and the streak icon are device preferences and stay
        // put. Milestone progress, token expiry and auth state belong to the
        // account — carrying them across a switch would suppress the new
        // account's milestones using the old one's history.
        let previous = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey)
        let switchedAccount = previous.map { $0.lowercased() != username.lowercased() } ?? false
        if switchedAccount {
            AppConfig.resetNotificationState()
            AppConfig.sharedDefaults.removeObject(forKey: ContributionSnapshot.defaultsKey)
            await NotificationScheduler(center: SystemNotificationCenter()).removeAllManaged()
        }

        let isFirstConnect = snapshot == nil || switchedAccount
        AppConfig.sharedDefaults.set(username, forKey: AppConfig.usernameDefaultsKey)

        // Bail before the network call rather than after: without the token in
        // the Keychain the widget and the background refresh have nothing to
        // read, so a "successful" fetch here would only paint a working app
        // around a widget that can never update.
        guard KeychainHelper.save(token, account: AppConfig.keychainAccount) else {
            let code = KeychainHelper.lastSaveStatus.map { " (Keychain error \($0))" } ?? ""
            await MainActor.run {
                status = .failed("Couldn't save your token to the iOS Keychain\(code). Try again, or reinstall the app if it keeps failing.")
            }
            return
        }
        await MainActor.run { status = .loading }

        do {
            let fetch = try await GitHubContributionsService.fetch(username: username, token: token)
            let newSnapshot = ContributionSnapshot.from(fetch.calendar)
            newSnapshot.save()

            AppConfig.authFailed = false
            if let expiry = fetch.tokenExpiry {
                AppConfig.tokenExpiry = expiry
                // A new token means new dates — drop the old ladder so it can
                // be rebuilt rather than warning about a token that's gone.
                await NotificationScheduler(center: SystemNotificationCenter()).removeTokenNotifications()
            }

            // Someone connecting mid-streak shouldn't be congratulated for a
            // milestone they passed before installing the app.
            if isFirstConnect {
                AppConfig.lastCelebratedStreak = NotificationPlanner.milestoneBaseline(
                    for: newSnapshot, asOf: Date()
                )
            }

            await NotificationCoordinator.reconcile(snapshot: newSnapshot)

            await MainActor.run {
                snapshot = newSnapshot
                tokenExpiry = AppConfig.tokenExpiry
                status = .success
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch GitHubServiceError.unauthorized {
            AppConfig.authFailed = true
            await NotificationCoordinator.reconcile()
            await MainActor.run {
                status = .failed("GitHub rejected that token — it may have expired. Generate a new one and paste it here.")
            }
        } catch GitHubServiceError.userNotFound {
            await MainActor.run {
                status = .failed("GitHub has no user named “\(username)”. Check the spelling — it's the name in your profile link, github.com/username.")
            }
        } catch GitHubServiceError.rateLimited {
            // Explicitly *not* an auth failure, so authFailed stays as it was
            // and the reminder ladder keeps running on the cached snapshot.
            await MainActor.run {
                status = .failed("GitHub is rate-limiting requests right now. Wait a few minutes and try again.")
            }
        } catch GitHubServiceError.apiError(let message) {
            await MainActor.run {
                status = .failed("GitHub returned an error: \(message)")
            }
        } catch {
            await MainActor.run {
                status = .failed("Couldn't reach GitHub. Check your connection and try again.")
            }
        }
    }
}

/// The Less → More legend, same as the one under GitHub's graph.
struct LegendView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(ContributionGridView.color(for: level, dark: colorScheme == .dark))
                    .frame(width: 9, height: 9)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
