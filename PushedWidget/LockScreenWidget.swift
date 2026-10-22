import SwiftUI
import WidgetKit

/// The streak on the Lock Screen, in the small spots beside and above the
/// clock. There's nothing to choose, so it has no Edit Widget options.
struct PushedLockWidget: Widget {
    let kind = "PushedLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockProvider()) { entry in
            LockScreenEntryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Streak")
        .description("Your streak, and whether today's push is in.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: ContributionSnapshot.load() ?? .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let snapshot = ContributionSnapshot.load() ?? (context.isPreview ? .sample() : nil)
        completion(StreakEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        Task {
            let refresh = await WidgetRefresh.run(now: Date())
            completion(Timeline(
                entries: refresh.entryDates.map { StreakEntry(date: $0, snapshot: refresh.snapshot) },
                policy: refresh.policy
            ))
        }
    }
}

private struct LockScreenEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        LockScreenView(
            snapshot: entry.snapshot,
            family: family,
            protection: entry.protection,
            now: entry.date
        )
    }
}
