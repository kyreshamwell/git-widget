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
    /// The number the widget leads with.
    var stat: WidgetStat = .streak
    var icon: String = AppConfig.streakIcon
    var custom: CustomWidgetStyle = .default
    var protection: StreakProtection = AppConfig.streakProtection
    var dayOffMark: DayOffMark = AppConfig.dayOffMark
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

    /// Minimal styles keep the number and the squares and drop every word.
    private var showsWords: Bool { !theme.hidesText }

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
            .fontWidth(theme.fontWidth)
            .environment(\.dayOffMark, dayOffMark)
            .environment(\.colorScheme, scheme)
            .environment(\.customWidgetStyle, custom)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            let reading = Reading(history: snapshot.history(protection: protection, asOf: now), total: snapshot.totalContributions)
            switch (layout, family) {
            case (.graph, .systemSmall): graphSmall(reading)
            case (.graph, _): graphChart(reading)
            case (.streak, .systemSmall): streakSmall(reading)
            case (.streak, .systemLarge): streakLarge(reading)
            case (.streak, _): streakMedium(reading)
            case (.week, .systemSmall): weekSmall(reading)
            case (.week, .systemLarge): weekLarge(reading)
            case (.week, _): weekMedium(reading)
            }
        } else {
            Text("Open Pushed and add your GitHub username + token.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - The number

    /// Everything a layout draws from, worked out once.
    private struct Reading {
        let history: StreakHistory
        let total: Int
    }

    /// The chosen number, and the words that go with it at each size.
    private struct Headline {
        let value: String
        /// Under a big number: "day streak".
        let caption: String
        /// In the graph's footer, beside the icon.
        let footer: String
        /// The footer on a small widget.
        let compactFooter: String
    }

    private func headline(_ reading: Reading, for stat: WidgetStat) -> Headline {
        let history = reading.history
        switch stat {
        case .streak:
            let streak = history.streak
            return Headline(
                value: "\(streak)",
                caption: "day streak",
                footer: StreakIcon.label(streak: streak, icon: icon, compact: false),
                compactFooter: StreakIcon.label(streak: streak, icon: icon, compact: true)
            )
        case .best:
            let best = history.bestStreak
            return Headline(
                value: "\(best)",
                caption: "best streak",
                footer: "Best: \(best) day\(best == 1 ? "" : "s")",
                compactFooter: "Best \(best)"
            )
        case .week:
            let pushed = history.pushedThisWeek
            return Headline(
                value: "\(pushed)",
                caption: "day\(pushed == 1 ? "" : "s") this week",
                footer: "\(pushed) day\(pushed == 1 ? "" : "s") this week",
                compactFooter: "\(pushed) this week"
            )
        case .year:
            let total = reading.total.formatted()
            return Headline(
                value: total,
                caption: "this year",
                footer: "\(total) this year",
                compactFooter: total
            )
        }
    }

    // MARK: - Graph layout

    /// Small: the square shape fits fewer columns, so the chosen range is
    /// capped at 9 weeks and the axis labels are skipped.
    private func graphSmall(_ reading: Reading) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(days: reading.history.days(forWeeks: min(weeks, 9)), style: style)
            if showsWords {
                footer(reading, compact: true)
            }
        }
    }

    /// Medium and large: the chart front and center with GitHub-style axis
    /// labels, over the range chosen for this widget (up to a full year).
    private func graphChart(_ reading: Reading) -> some View {
        VStack(spacing: 6) {
            ContributionGridView(
                days: reading.history.days(forWeeks: weeks),
                endDate: reading.history.endDate,
                showsLabels: true,
                style: style
            )
            if showsWords {
                footer(reading)
            }
        }
    }

    /// The small family is ~155pt wide, which can't hold a streak label, a dot
    /// and "committed today" without truncating the last one. The dot already
    /// carries that state, so at this size the words are dropped rather than
    /// clipped mid-syllable.
    private func footer(_ reading: Reading, compact: Bool = false) -> some View {
        let headline = headline(reading, for: stat)
        return HStack(spacing: 4) {
            Text(compact ? headline.compactFooter : headline.footer)
                .font(.caption.bold())
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            StatusDot(today: reading.history.today, theme: theme)
                .frame(width: 7, height: 7)
            if !compact {
                Text(reading.history.today.caption)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    // MARK: - Big streak layout

    private func streakSmall(_ reading: Reading) -> some View {
        let history = reading.history
        return VStack(alignment: .leading, spacing: 0) {
            topRow(history, iconSize: 22, dot: 9)
            Spacer(minLength: 0)
            bigNumber(reading, size: 46, captionFont: .caption.weight(.semibold))
            Spacer(minLength: 8)
            WeekStrip(days: history.days(last: 7), today: history.today, theme: theme)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    private func streakMedium(_ reading: Reading) -> some View {
        let history = reading.history
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                if showsWords { iconView(size: 24) }
                Spacer(minLength: 0)
                bigNumber(reading, size: 50, captionFont: .subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if showsWords { statusLine(history) }
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(reading))

            // Capped so the squares stay big enough to read beside the number.
            ContributionGridView(
                days: history.days(forWeeks: min(weeks, 12)),
                endDate: history.endDate,
                style: style
            )
        }
    }

    private func streakLarge(_ reading: Reading) -> some View {
        let history = reading.history
        // Capped for the same reason as medium: past about four months the
        // squares shrink into a thin strip with empty space above and below.
        let window = history.days(forWeeks: min(weeks, 17))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if showsWords { iconView(size: 36) }
                bigNumber(reading, size: 52, captionFont: .subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if showsWords { statusLine(history) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(reading))

            ContributionGridView(
                days: window,
                endDate: history.endDate,
                showsLabels: true,
                style: style
            )

            if showsWords {
                HStack(alignment: .firstTextBaseline) {
                    // Whichever of the two isn't already the big number.
                    if stat == .year {
                        statBlock("\(history.bestStreak)", "best streak")
                    } else {
                        statBlock(reading.total.formatted(), "contributions this year")
                    }
                    Spacer(minLength: 8)
                    statBlock("\(window.filter(\.isActive).count) of \(window.count)", "days active", alignment: .trailing)
                }
            }
        }
    }

    // MARK: - This week layout

    private func weekSmall(_ reading: Reading) -> some View {
        let history = reading.history
        let week = history.thisWeek
        return VStack(alignment: .leading, spacing: 0) {
            topRow(history, iconSize: 22, dot: 9)
            Spacer(minLength: 0)
            bigNumber(reading, size: 42, captionFont: .caption.weight(.semibold))
            Spacer(minLength: 8)
            WeekRow(days: week.days, todayIndex: week.todayIndex, today: history.today, theme: theme, showsLetters: showsWords, gap: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusDescription(reading))
    }

    private func weekMedium(_ reading: Reading) -> some View {
        let history = reading.history
        let week = history.thisWeek
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if showsWords { iconView(size: 22) }
                numberText(headline(reading, for: stat).value, size: 34)
                if showsWords {
                    Text(headline(reading, for: stat).caption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if showsWords { statusLine(history) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(reading))

            WeekRow(days: week.days, todayIndex: week.todayIndex, today: history.today, theme: theme, showsLetters: showsWords, gap: 8)
        }
    }

    private func weekLarge(_ reading: Reading) -> some View {
        let history = reading.history
        let week = history.thisWeek
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if showsWords { iconView(size: 36) }
                bigNumber(reading, size: 52, captionFont: .subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if showsWords { statusLine(history) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusDescription(reading))

            WeekRow(days: week.days, todayIndex: week.todayIndex, today: history.today, theme: theme, showsLetters: showsWords, gap: 8)

            // The weeks before, smaller, so the big squares have context.
            ContributionGridView(
                days: history.days(forWeeks: min(weeks, 17)),
                endDate: history.endDate,
                showsLabels: true,
                style: style
            )

            if showsWords {
                // The two numbers that aren't the big one.
                let others = WidgetStat.allCases.filter { $0 != stat }.prefix(2)
                HStack(alignment: .firstTextBaseline) {
                    ForEach(Array(others.enumerated()), id: \.element) { index, other in
                        let line = headline(reading, for: other)
                        if index > 0 { Spacer(minLength: 8) }
                        statBlock(line.value, line.caption, alignment: index == 0 ? .leading : .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func topRow(_ history: StreakHistory, iconSize: CGFloat, dot: CGFloat) -> some View {
        HStack(alignment: .top) {
            if showsWords { iconView(size: iconSize) }
            Spacer(minLength: 0)
            StatusDot(today: history.today, theme: theme)
                .frame(width: dot, height: dot)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func iconView(size: CGFloat) -> some View {
        if icon != StreakIcon.none {
            Text(icon).font(.system(size: size))
        }
    }

    /// The chosen number with its caption underneath.
    private func bigNumber(_ reading: Reading, size: CGFloat, captionFont: Font) -> some View {
        let headline = headline(reading, for: stat)
        return VStack(alignment: .leading, spacing: 0) {
            numberText(headline.value, size: size)
            if showsWords {
                Text(headline.caption)
                    .font(captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func numberText(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: theme.numberWeight, design: theme.fontDesign))
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

    private func statBlock(_ value: String, _ label: String, alignment: HorizontalAlignment = .leading) -> some View {
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
    /// says nothing to VoiceOver, so the label states it outright. The streak
    /// is always said, whatever number the widget shows.
    private func statusDescription(_ reading: Reading) -> String {
        let streak = reading.history.streak
        var text = "\(streak) day\(streak == 1 ? "" : "s") streak. \(reading.history.today.spokenStatus)"
        if stat != .streak {
            let headline = headline(reading, for: stat)
            text += " \(headline.value) \(headline.caption)."
        }
        return text
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
/// (a tinted home screen, or a custom square color). A day off is a ring with
/// a dot, ice blue for a freeze: at this size stripes would be a smudge.
struct StatusDot: View {
    let today: StreakHistory.Today
    let theme: WidgetTheme

    var body: some View {
        switch today {
        case .pushed:
            Circle().fill(theme.pushed)
        case .off:
            CellOutline(cornerFraction: 0.5, dotted: true)
                .fill(today == .off(.freeze) ? theme.freeze : theme.pushed, style: FillStyle(eoFill: true))
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
        HStack(spacing: 4 * theme.spacing) {
            ForEach(days.indices, id: \.self) { index in
                DayCell(day: days[index], theme: theme)
                    .overlay {
                        if index == days.count - 1 && today == .pending {
                            CellShape(theme)
                                .strokeBorder(theme.pending, lineWidth: 1.5)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .widgetAccentable(days[index].isActive)
            }
        }
    }
}

/// This week, Sunday to Saturday, with the day letters under it. The days
/// still to come are drawn as faint dashed outlines, so the shape of the week
/// is there from Sunday on. Today is ringed until you push.
struct WeekRow: View {
    /// Seven days; nil for one that hasn't happened yet.
    let days: [StreakDay?]
    let todayIndex: Int
    let today: StreakHistory.Today
    let theme: WidgetTheme
    var showsLetters = true
    var gap: CGFloat = 6

    private static let letters: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar.veryShortWeekdaySymbols
    }()

    var body: some View {
        HStack(alignment: .top, spacing: gap * theme.spacing) {
            ForEach(days.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    cell(index)
                        .aspectRatio(1, contentMode: .fit)
                    if showsLetters {
                        Text(Self.letters[index])
                            .font(.caption2.weight(index == todayIndex ? .bold : .medium))
                            .foregroundStyle(index == todayIndex ? theme.primaryText : theme.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let shape = CellShape(theme)
        if let day = days[index] {
            DayCell(day: day, theme: theme)
                .overlay {
                    if index == todayIndex && today == .pending {
                        shape.strokeBorder(theme.pending, lineWidth: 1.5)
                    }
                }
                .widgetAccentable(day.isActive)
        } else {
            shape.strokeBorder(theme.color(for: 0), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
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
    var stat: WidgetStat = .streak
    var icon: String = AppConfig.streakIcon
    var custom: CustomWidgetStyle = .default
    var protection: StreakProtection = AppConfig.streakProtection
    var dayOffMark: DayOffMark = AppConfig.dayOffMark
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
            stat: stat,
            icon: icon,
            custom: custom,
            protection: protection,
            dayOffMark: dayOffMark,
            now: now
        )
        .frame(width: size.width, height: size.height)
        .background { WidgetBackground(style: style, custom: custom) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
