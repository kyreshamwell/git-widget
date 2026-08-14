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
            footer(snapshot, compact: true)
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

    /// The small family is ~155pt wide, which can't hold a streak label, a dot
    /// and "committed today" without truncating the last one. The dot already
    /// carries that state — green for pushed, orange for not — so at this size
    /// the words are dropped rather than clipped mid-syllable.
    private func footer(_ snapshot: ContributionSnapshot, compact: Bool = false) -> some View {
        let icon = AppConfig.streakIcon
        let streak = snapshot.currentStreak
        let label = icon == "none"
            ? (compact ? "\(streak) day\(streak == 1 ? "" : "s")" : "\(streak)-day streak")
            : "\(icon) \(streak)"

        return HStack(spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Circle()
                .fill(snapshot.committedToday ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            if !compact {
                Text(snapshot.committedToday ? "committed today" : "not yet today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        // The dot is the only thing carrying "pushed today?" at the small size,
        // and a colour says nothing to VoiceOver — so the footer states it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(streak) day\(streak == 1 ? "" : "s") streak. "
            + (snapshot.committedToday ? "Committed today." : "Not committed yet today.")
        )
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
