import SwiftUI
import WidgetKit

struct PushedWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: StreakEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall:
                smallView(snapshot)
            default:
                chartView(snapshot)
            }
        } else {
            Text("Open Pushed and add your GitHub username + token.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Small: square shape fits fewer columns — cap the user's chosen range at
    /// 9 weeks, and skip axis labels (no room at this size).
    private func smallView(_ snapshot: ContributionSnapshot) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(levels: snapshot.levels(forWeeks: min(AppConfig.widgetWeeks, 9)))
            footer(snapshot)
        }
    }

    /// Medium/large: chart front and center with GitHub-style axis labels,
    /// range chosen in the app (up to a full year).
    private func chartView(_ snapshot: ContributionSnapshot) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(
                levels: snapshot.levels(forWeeks: AppConfig.widgetWeeks),
                endDate: snapshot.endDate,
                showsLabels: true
            )
            footer(snapshot)
        }
    }

    private func footer(_ snapshot: ContributionSnapshot) -> some View {
        let icon = AppConfig.streakIcon
        return HStack(spacing: 4) {
            Text(icon == "none"
                 ? "\(snapshot.currentStreak)-day streak"
                 : "\(icon) \(snapshot.currentStreak)")
                .font(.caption.bold())
            Spacer()
            Circle()
                .fill(snapshot.committedToday ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(snapshot.committedToday ? "committed today" : "not yet today")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct PushedWidget: Widget {
    let kind = "PushedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PushedWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Contribution Graph")
        .description("Your GitHub contribution graph and commit streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct PushedWidgetBundle: WidgetBundle {
    var body: some Widget {
        PushedWidget()
    }
}
