import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var username: String = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey) ?? ""
    @State private var token: String = KeychainHelper.read(account: AppConfig.keychainAccount) ?? ""
    @State private var snapshot: ContributionSnapshot? = ContributionSnapshot.load()
    @State private var widgetWeeks: Int = AppConfig.widgetWeeks
    @State private var streakIcon: String = AppConfig.streakIcon
    @State private var status: Status = .idle

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
                    accountSection
                }
                .navigationTitle("Pushed")
                .refreshable { await refresh() }
            } else {
                setupView
                    .navigationTitle("Pushed")
            }
        }
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
                bullets([
                    "It's the name in your profile link: github.com/username",
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
            LabeledContent("Total this year", value: "\(snapshot.totalContributions)")
            LabeledContent("Active days (26 wks)", value: "\(snapshot.recentLevels.filter { $0 > 0 }.count)")
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

    // MARK: - Account (connected state)

    private var accountSection: some View {
        Section {
            LabeledContent("Signed in as", value: username)

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
        username = ""
        token = ""
        snapshot = nil
        status = .idle
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refresh() async {
        guard !username.isEmpty, !token.isEmpty else { return }
        AppConfig.sharedDefaults.set(username, forKey: AppConfig.usernameDefaultsKey)
        KeychainHelper.save(token, account: AppConfig.keychainAccount)
        await MainActor.run { status = .loading }

        do {
            let calendar = try await GitHubContributionsService.fetchCalendar(username: username, token: token)
            let newSnapshot = ContributionSnapshot.from(calendar)
            newSnapshot.save()
            await MainActor.run {
                snapshot = newSnapshot
                status = .success
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            await MainActor.run {
                status = .failed("Couldn't fetch contributions. Check username/token.")
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
