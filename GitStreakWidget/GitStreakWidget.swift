import SwiftUI
import WidgetKit

struct GitStreakWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: StreakEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🔥 \(entry.snapshot?.currentStreak ?? 0)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("day streak")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.snapshot?.committedToday == true ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(entry.snapshot?.committedToday == true ? "Committed today" : "Not yet today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🔥 \(entry.snapshot?.currentStreak ?? 0)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.snapshot?.committedToday == true ? "Committed today ✓" : "No commit yet today")
                    .font(.caption2)
                    .foregroundStyle(entry.snapshot?.committedToday == true ? .green : .orange)
            }
            Spacer()
            if let counts = entry.snapshot?.recentCounts, !counts.isEmpty {
                ContributionGridView(counts: counts, columns: 13)
            } else {
                Text("Open the app and add your GitHub username + token to get started.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GitStreakWidget: Widget {
    let kind = "GitStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            GitStreakWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Git Streak")
        .description("Shows your current GitHub commit streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct GitStreakWidgetBundle: WidgetBundle {
    var body: some Widget {
        GitStreakWidget()
    }
}
