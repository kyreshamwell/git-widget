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
    var custom: CustomWidgetStyle = AppConfig.customStyle
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
            switch (layout, family) {
            case (.graph, .systemSmall): graphSmall(snapshot)
            case (.graph, _): graphChart(snapshot)
            case (.streak, .systemSmall): streakSmall(snapshot)
            case (.streak, .systemLarge): streakLarge(snapshot)
            case (.streak, _): streakMedium(snapshot)
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
    private func graphSmall(_ snapshot: ContributionSnapshot) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(levels: snapshot.levels(forWeeks: min(weeks, 9)), style: style)
            footer(snapshot, compact: true)
        }
    }

    /// Medium and large: the chart front and center with GitHub-style axis
    /// labels, over the range chosen in the app (up to a full year).
    private func graphChart(_ snapshot: ContributionSnapshot) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(
                levels: snapshot.levels(forWeeks: weeks),
                endDate: snapshot.endDate,
                showsLabels: true,
                style: style
            )
            footer(snapshot)
        }
    }

    /// The small family is ~155pt wide, which can't hold a streak label, a dot
    /// and "committed today" without truncating the last one. The dot already
    /// carries that state, so at this size the words are dropped rather than
    /// clipped mid-syllable.
    private func footer(_ snapshot: ContributionSnapshot, compact: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(StreakIcon.label(streak: snapshot.currentStreak, icon: icon, compact: compact))
                .font(.caption.bold())
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            StatusDot(pushed: snapshot.committedToday, theme: theme)
                .frame(width: 7, height: 7)
            if !compact {
                Text(snapshot.committedToday ? "committed today" : "not yet today")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(snapshot))
    }

    // MARK: - Big streak layout

    private func streakSmall(_ snapshot: ContributionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                iconView(size: 22)
                Spacer(minLength: 0)
                StatusDot(pushed: snapshot.committedToday, theme: theme)
                    .frame(width: 9, height: 9)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            streakNumber(snapshot.currentStreak, size: 46)
            Text("day streak")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
            WeekStrip(
                levels: snapshot.levels(lastDays: 7, asOf: Date()),
                pushedToday: snapshot.committedToday,
                theme: theme
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(snapshot))
    }

    private func streakMedium(_ snapshot: ContributionSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                iconView(size: 24)
                Spacer(minLength: 0)
                streakNumber(snapshot.currentStreak, size: 50)
                Text("day streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 0)
                statusLine(snapshot)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(snapshot))

            // Capped so the squares stay big enough to read beside the number.
            ContributionGridView(
                levels: snapshot.levels(forWeeks: min(weeks, 12)),
                endDate: snapshot.endDate,
                style: style
            )
        }
    }

    private func streakLarge(_ snapshot: ContributionSnapshot) -> some View {
        // Capped for the same reason as medium: past about four months the
        // squares shrink into a thin strip with empty space above and below.
        let window = snapshot.levels(forWeeks: min(weeks, 17))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                iconView(size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    streakNumber(snapshot.currentStreak, size: 52)
                    Text("day streak")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 8)
                statusLine(snapshot)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(snapshot))

            ContributionGridView(
                levels: window,
                endDate: snapshot.endDate,
                showsLabels: true,
                style: style
            )

            HStack(alignment: .firstTextBaseline) {
                stat(snapshot.totalContributions.formatted(), "contributions this year")
                Spacer(minLength: 8)
                stat("\(window.filter { $0 > 0 }.count) of \(window.count)", "days active", alignment: .trailing)
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

    private func statusLine(_ snapshot: ContributionSnapshot) -> some View {
        HStack(spacing: 5) {
            StatusDot(pushed: snapshot.committedToday, theme: theme)
                .frame(width: 7, height: 7)
            Text(snapshot.committedToday ? "committed today" : "not yet today")
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
    private func statusDescription(_ snapshot: ContributionSnapshot) -> String {
        let streak = snapshot.currentStreak
        return "\(streak) day\(streak == 1 ? "" : "s") streak. "
            + (snapshot.committedToday ? "Committed today." : "Not committed yet today.")
    }
}

/// A filled dot once you've pushed. "Not yet" is a second color where the
/// theme can promise one that stands apart, and a hollow ring where it can't
/// (a tinted home screen, or a custom square color).
struct StatusDot: View {
    let pushed: Bool
    let theme: WidgetTheme

    var body: some View {
        if theme.ringsPending && !pushed {
            Circle().strokeBorder(theme.pending, lineWidth: 1.5)
        } else {
            Circle().fill(pushed ? theme.pushed : theme.pending)
        }
    }
}

/// The last seven days in a row, today on the right. Today is ringed until
/// you push, since it's the one square a streak widget is really about.
struct WeekStrip: View {
    let levels: [Int]
    let pushedToday: Bool
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(levels.indices, id: \.self) { index in
                let shape = CellShape(cornerFraction: theme.cornerFraction)
                shape
                    .fill(theme.color(for: levels[index]))
                    .overlay {
                        if index == levels.count - 1 && !pushedToday {
                            shape.strokeBorder(theme.pending, lineWidth: 1.5)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .widgetAccentable(levels[index] > 0)
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
    var custom: CustomWidgetStyle = AppConfig.customStyle

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
            custom: custom
        )
        .frame(width: size.width, height: size.height)
        .background { WidgetBackground(style: style, custom: custom) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
