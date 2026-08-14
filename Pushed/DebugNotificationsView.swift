import SwiftUI
import UserNotifications

/// On-device verification surface. The planner's correctness is covered by unit
/// tests; what this proves is the part tests can't reach — that iOS actually
/// holds what we queued, at the time we said, with the copy we wrote.
struct DebugNotificationsView: View {
    @State private var pending: [UNNotificationRequest] = []
    @State private var fakeExpiry = Date().addingTimeInterval(10 * 86400)
    @State private var authFailed = AppConfig.authFailed
    @State private var lastAction = ""

    private let center = SystemNotificationCenter()

    var body: some View {
        Form {
            Section {
                if pending.isEmpty {
                    Text("Nothing queued.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pending, id: \.identifier) { request in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.identifier)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(request.content.title).font(.subheadline.bold())
                            Text(request.content.body).font(.caption)
                            Text(fireDescription(request))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Pending (\(pending.count))")
            } footer: {
                Text("What iOS is actually holding right now — the ground truth for whether scheduling and cancelling work.")
            }

            Section("Actions") {
                Button("Reconcile now") {
                    Task {
                        await NotificationCoordinator.reconcile()
                        await load()
                        lastAction = "Reconciled"
                    }
                }
                Button("Reload pending") { Task { await load() } }
                Button("Clear all managed", role: .destructive) {
                    Task {
                        await NotificationScheduler(center: center).removeAllManaged()
                        await load()
                    }
                }
            }

            Section {
                ForEach(samples, id: \.id) { sample in
                    Button("Fire: \(sample.title)") {
                        Task {
                            await center.add(PlannedNotification(
                                id: "daily-debug-\(UUID().uuidString)",
                                title: sample.title,
                                body: sample.body,
                                fireDate: Date().addingTimeInterval(10)
                            ))
                            await load()
                            lastAction = "Queued for 10s — background the app"
                        }
                    }
                }
            } header: {
                Text("Fire in 10 seconds")
            } footer: {
                Text("Background the app after tapping — iOS suppresses banners while the app is in the foreground.")
            }

            Section {
                ForEach(scenarios, id: \.label) { scenario in
                    Button(scenario.label) {
                        Task {
                            writeSyntheticSnapshot(
                                lastActiveDaysAgo: scenario.daysAgo,
                                streakLength: scenario.streak
                            )
                            await NotificationScheduler(center: center).resetDaySlots()
                            await NotificationCoordinator.reconcile()
                            await load()
                            lastAction = "State: \(scenario.label)"
                        }
                    }
                }
            } header: {
                Text("Simulate contribution state")
            } footer: {
                Text("Overwrites the cached snapshot with a synthetic one, then reconciles — the real planner path, without needing the right streak in real life. \"Pushed today\" should cancel both day slots.")
            }

            Section {
                DatePicker("Pretend expiry", selection: $fakeExpiry, displayedComponents: .date)
                Button("Apply and reconcile") {
                    Task {
                        AppConfig.tokenExpiry = fakeExpiry
                        await NotificationScheduler(center: center).removeTokenNotifications()
                        await NotificationCoordinator.reconcile()
                        await load()
                        lastAction = "Token ladder rebuilt"
                    }
                }
                Toggle("Force auth failure", isOn: $authFailed)
                    .onChange(of: authFailed) { _, value in
                        AppConfig.authFailed = value
                        if value { AppConfig.lastAuthAlertAt = nil }
                        Task {
                            await NotificationCoordinator.reconcile()
                            await load()
                        }
                    }
            } header: {
                Text("Token simulation")
            } footer: {
                Text("Set expiry 10 days out and reconcile — three warnings should appear above, dated 10, 5 and 1 days before. Verifies the ladder in seconds instead of over a week.")
            }

            if !lastAction.isEmpty {
                Section { Text(lastAction).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Notification debug")
        .task { await load() }
    }

    private var samples: [(id: String, title: String, body: String)] {
        [
            ("midday", "13-day streak", "Nothing pushed yet today."),
            ("evening", "Your 13-day streak ends at midnight", "About 4 hours left."),
            ("dormant", "Your 15-day streak ended", "Start the next one today."),
            ("milestone", "14 days straight", "Two weeks without a gap."),
            ("token", "Your GitHub token expires in 5 days", "Generate a new one so the widget keeps updating."),
        ]
    }

    private var scenarios: [(label: String, daysAgo: Int, streak: Int)] {
        [
            ("Pushed today (streak 14)", 0, 14),
            ("Streak at risk (13 days)", 1, 13),
            ("Streak at risk (30 days)", 1, 30),
            ("Dormant day 1 (lost 15)", 2, 15),
            ("Dormant day 2", 3, 15),
            ("Dormant 5 days", 5, 15),
            ("Dormant 40 days (tapered)", 40, 15),
        ]
    }

    private func writeSyntheticSnapshot(lastActiveDaysAgo: Int, streakLength: Int) {
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

    private func fireDescription(_ request: UNNotificationRequest) -> String {
        guard let next = SystemNotificationCenter.nextFireDate(of: request.trigger) else {
            return "no trigger"
        }
        return next.formatted(date: .abbreviated, time: .standard)
    }

    private func load() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        await MainActor.run {
            pending = requests.sorted {
                SystemNotificationCenter.nextFireDate(of: $0.trigger) ?? .distantFuture
                    < SystemNotificationCenter.nextFireDate(of: $1.trigger) ?? .distantFuture
            }
        }
    }
}
