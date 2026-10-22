import SwiftUI
import WidgetKit

/// Everything the home-screen widget draws. It lives in Shared rather than the
/// extension so the app's style gallery renders the exact same view.
struct StreakWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let snapshot: ContributionSnapshot?
    let family: WidgetFamily
    var style: WidgetStyle = .classic
    var layout: WidgetLayout = .graph
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon
    var custom: CustomWidgetStyle = .default
    var protection: StreakProtection = AppConfig.streakProtection
    /// The moment this is drawn for. A widget entry is laid out ahead of the
    /// time it goes on screen, so the entry's own date is passed in and the
    /// clock is never read here.
    var now = Date()
    /// The system's standard widget margins. The widget turns the automatic
    /// ones off and applies these itself, so each layout can choose its own.
    var margins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

    private var scheme: ColorScheme { style.pinnedColorScheme(custom: custom) ?? colorScheme }

    private var theme: WidgetTheme {
        style.theme(for: scheme, renderingMode: renderingMode, custom: custom)
    }

    /// The graph layout sits closer to the edges than the standard margins.
    /// Its squares are sized by whichever side runs out first, usually the
    /// width, so every point handed back at the sides becomes bigger squares.
    /// The labels and footer still clear the widget's rounded corners.
    private var insets: EdgeInsets {
        guard snapshot != nil, layout == .graph else { return margins }
        return EdgeInsets(
            top: margins.top * 0.75,
            leading: margins.leading * 0.6,
            bottom: margins.bottom * 0.75,
            trailing: margins.trailing * 0.6
        )
    }

    var body: some View {
        content
            .padding(insets)
            .fontDesign(theme.fontDesign)
            .environment(\.colorScheme, scheme)
            .environment(\.customWidgetStyle, custom)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            let history = snapshot.history(protection: protection, asOf: now)
            switch (layout, family) {
            case (.graph, .systemSmall): graphSmall(history)
            case (.graph, _): graphChart(history)
            case (.streak, .systemSmall): streakSmall(history)
            case (.streak, .systemLarge): streakLarge(history, total: snapshot.totalContributions)
            case (.streak, _): streakMedium(history)
            }
        } else {
            Text("Open Pushed and add your GitHub username + token.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Graph layout

    /// Small: the square shape fits fewer columns, so the chosen range is
    /// capped at 9 weeks and the axis labels are skipped.
    private func graphSmall(_ history: StreakHistory) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(days: history.days(forWeeks: min(weeks, 9)), style: style)
            footer(history, compact: true)
        }
    }

    /// Medium and large: the chart front and center with GitHub-style axis
    /// labels, over the range chosen in the app (up to a full year).
    private func graphChart(_ history: StreakHistory) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(
                days: history.days(forWeeks: weeks),
                endDate: history.endDate,
                showsLabels: true,
                style: style
            )
            footer(history)
        }
    }

    /// The small family is ~155pt wide, which can't hold a streak label, a dot
    /// and "committed today" without truncating the last one. The dot already
    /// carries that state, so at this size the words are dropped rather than
    /// clipped mid-syllable.
    private func footer(_ history: StreakHistory, compact: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(StreakIcon.label(streak: history.streak, icon: icon, compact: compact))
                .font(.caption.bold())
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            StatusDot(today: history.today, theme: theme)
                .frame(width: 7, height: 7)
            if !compact {
                Text(history.today.caption)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(history))
    }

    // MARK: - Big streak layout

    private func streakSmall(_ history: StreakHistory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                iconView(size: 22)
                Spacer(minLength: 0)
                StatusDot(today: history.today, theme: theme)
                    .frame(width: 9, height: 9)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            streakNumber(history.streak, size: 46)
            Text("day streak")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
            WeekStrip(days: history.days(last: 7), today: history.today, theme: theme)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(history))
    }

    private func streakMedium(_ history: StreakHistory) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                iconView(size: 24)
                Spacer(minLength: 0)
                streakNumber(history.streak, size: 50)
                Text("day streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 0)
                statusLine(history)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(history))

            // Capped so the squares stay big enough to read beside the number.
            ContributionGridView(
                days: history.days(forWeeks: min(weeks, 12)),
                endDate: history.endDate,
                style: style
            )
        }
    }

    private func streakLarge(_ history: StreakHistory, total: Int) -> some View {
        // Capped for the same reason as medium: past about four months the
        // squares shrink into a thin strip with empty space above and below.
        let window = history.days(forWeeks: min(weeks, 17))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                iconView(size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    streakNumber(history.streak, size: 52)
                    Text("day streak")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 8)
                statusLine(history)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(history))

            ContributionGridView(
                days: window,
                endDate: history.endDate,
                showsLabels: true,
                style: style
            )

            HStack(alignment: .firstTextBaseline) {
                stat(total.formatted(), "contributions this year")
                Spacer(minLength: 8)
                stat("\(window.filter(\.isActive).count) of \(window.count)", "days active", alignment: .trailing)
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func iconView(size: CGFloat) -> some View {
        if icon != StreakIcon.none {
            Text(icon).font(.system(size: size))
        }
    }

    private func streakNumber(_ value: Int, size: CGFloat) -> some View {
        Text("\(value)")
            .font(.system(size: size, weight: .bold, design: theme.fontDesign))
            .foregroundStyle(theme.numberFill)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .glow(theme.glows ? theme.color(for: 4) : nil, radius: 10)
            .contentTransition(.numericText())
            .widgetAccentable()
    }

    private func statusLine(_ history: StreakHistory) -> some View {
        HStack(spacing: 5) {
            StatusDot(today: history.today, theme: theme)
                .frame(width: 7, height: 7)
            Text(history.today.caption)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
    }

    private func stat(_ value: String, _ label: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
        }
    }

    /// The dot is all that says "pushed today?" at the small size, and a color
    /// says nothing to VoiceOver, so the label states it outright.
    private func statusDescription(_ history: StreakHistory) -> String {
        let streak = history.streak
        return "\(streak) day\(streak == 1 ? "" : "s") streak. \(history.today.spokenStatus)"
    }
}

extension StreakHistory.Today {
    /// The few words beside the status dot.
    var caption: String {
        switch self {
        case .pushed: "committed today"
        case .off(.rest): "rest day"
        case .off(.freeze): "streak frozen"
        case .pending: "not yet today"
        }
    }

    var spokenStatus: String {
        switch self {
        case .pushed: "Committed today."
        case .off(.rest): "Rest day today."
        case .off(.freeze): "Streak frozen today."
        case .pending: "Not committed yet today."
        }
    }
}

/// A filled dot once you've pushed. "Not yet" is a second color where the
/// theme can promise one that stands apart, and a hollow ring where it can't
/// (a tinted home screen, or a custom square color). A day off wears the same
/// outline and dot as its square in the graph.
struct StatusDot: View {
    let today: StreakHistory.Today
    let theme: WidgetTheme

    var body: some View {
        switch today {
        case .pushed:
            Circle().fill(theme.pushed)
        case .off:
            CellOutline(cornerFraction: 0.5, dotted: true)
                .fill(theme.pushed, style: FillStyle(eoFill: true))
        case .pending:
            if theme.ringsPending {
                Circle().strokeBorder(theme.pending, lineWidth: 1.5)
            } else {
                Circle().fill(theme.pending)
            }
        }
    }
}

/// The last seven days in a row, today on the right. Today is ringed until
/// you push, since it's the one square a streak widget is really about. On a
/// day off there's nothing owed, so it wears the day-off mark instead.
struct WeekStrip: View {
    let days: [StreakDay]
    let today: StreakHistory.Today
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days.indices, id: \.self) { index in
                DayCell(day: days[index], theme: theme)
                    .overlay {
                        if index == days.count - 1 && today == .pending {
                            CellShape(cornerFraction: theme.cornerFraction)
                                .strokeBorder(theme.pending, lineWidth: 1.5)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .widgetAccentable(days[index].isActive)
            }
        }
    }
}

/// A widget as it sits on the home screen, for showing styles inside the app,
/// where there's no widget container to supply margins and a backdrop.
struct WidgetPreviewCard: View {
    let snapshot: ContributionSnapshot?
    let family: WidgetFamily
    let style: WidgetStyle
    let layout: WidgetLayout
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon
    var custom: CustomWidgetStyle = .default
    var protection: StreakProtection = AppConfig.streakProtection
    var now = Date()

    /// Home-screen sizes on the larger iPhones, in points.
    static func size(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        default: CGSize(width: 364, height: 170)
        }
    }

    var body: some View {
        let size = Self.size(for: family)
        StreakWidgetView(
            snapshot: snapshot,
            family: family,
            style: style,
            layout: layout,
            weeks: weeks,
            icon: icon,
            custom: custom,
            protection: protection,
            now: now
        )
        .frame(width: size.width, height: size.height)
        .background { WidgetBackground(style: style, custom: custom) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
