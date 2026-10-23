import SwiftUI
import WidgetKit

/// The Lock Screen draws everything in one tint, so these lean on shape and
/// weight rather than color: a ring that closes once you've pushed, and the
/// same day-off mark as on the home screen.
///
/// Lives in Shared rather than the extension so it can be drawn outside a
/// widget too, the way the home-screen view is.
struct LockScreenView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: ContributionSnapshot?
    let family: WidgetFamily
    var protection: StreakProtection = AppConfig.streakProtection
    var now = Date()
    var icon: String = AppConfig.streakIcon
    var dayOffMark: DayOffMark = AppConfig.dayOffMark

    var body: some View {
        content.environment(\.dayOffMark, dayOffMark)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            let history = snapshot.history(protection: protection, asOf: now)
            switch family {
            case .accessoryCircular: circular(history)
            case .accessoryRectangular: rectangular(history)
            default: inline(history)
            }
        } else {
            switch family {
            case .accessoryInline: Text("Set up Pushed")
            default:
                Image(systemName: "square.grid.3x3.fill")
                    .font(.title3)
                    .accessibilityLabel("Open Pushed to connect your GitHub")
            }
        }
    }

    private func circular(_ history: StreakHistory) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            TodayRing(today: history.today)
                .padding(3)
            VStack(spacing: -1) {
                Text("\(history.streak)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(history.streak == 1 ? "day" : "days")
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .opacity(0.8)
            }
            .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(history.streak) day streak. \(history.today.spokenStatus)")
    }

    private func rectangular(_ history: StreakHistory) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(icon == StreakIcon.none ? "\(history.streak)-day streak" : "\(icon) \(history.streak)-day streak")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            Text(history.today.caption)
                .font(.caption)
                .lineLimit(1)
                .opacity(0.85)
            WeekStrip(
                days: history.days(last: 7),
                today: history.today,
                theme: WidgetStyle.classic.theme(for: .dark, renderingMode: renderingMode)
            )
            .frame(height: 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(history.streak) day streak. \(history.today.spokenStatus)")
    }

    /// One line above the clock: an image and some text is all it holds.
    private func inline(_ history: StreakHistory) -> some View {
        let status: String = switch history.today {
        case .pushed: "pushed"
        case .off(.rest): "rest day"
        case .off(.freeze): "frozen"
        case .pending: "not yet"
        }
        return Label("\(history.streak) day\(history.streak == 1 ? "" : "s") · \(status)", systemImage: "flame.fill")
    }
}

/// Closed once today's push is in. Faint while it's still owed, and dashed on
/// a day off, when nothing is.
private struct TodayRing: View {
    let today: StreakHistory.Today

    var body: some View {
        switch today {
        case .pushed:
            Circle().strokeBorder(lineWidth: 3).widgetAccentable()
        case .off:
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        case .pending:
            Circle().strokeBorder(lineWidth: 3).opacity(0.25)
        }
    }
}
