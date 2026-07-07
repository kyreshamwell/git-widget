import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var username: String = AppConfig.sharedDefaults.string(forKey: AppConfig.usernameDefaultsKey) ?? ""
    @State private var token: String = KeychainHelper.read(account: AppConfig.keychainAccount) ?? ""
    @State private var snapshot: ContributionSnapshot? = ContributionSnapshot.load()
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle
        case loading
        case success
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Personal Access Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Needs a classic token with the read:user scope. Create one at github.com/settings/tokens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Save & Test") {
                        save()
                    }
                    .disabled(username.isEmpty || token.isEmpty)

                    if status == .loading {
                        ProgressView()
                    } else if case .failed(let message) = status {
                        Text(message).foregroundStyle(.red).font(.caption)
                    } else if status == .success {
                        Text("Connected ✓").foregroundStyle(.green).font(.caption)
                    }
                }

                if let snapshot {
                    Section("Current Streak") {
                        LabeledContent("Streak", value: "\(snapshot.currentStreak) days")
                        LabeledContent("Committed today", value: snapshot.committedToday ? "Yes" : "Not yet")
                        LabeledContent("Total contributions", value: "\(snapshot.totalContributions)")
                        Text("Last synced \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("GitStreak")
        }
    }

    private func save() {
        AppConfig.sharedDefaults.set(username, forKey: AppConfig.usernameDefaultsKey)
        KeychainHelper.save(token, account: AppConfig.keychainAccount)
        status = .loading

        Task {
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
}

#Preview {
    ContentView()
}
