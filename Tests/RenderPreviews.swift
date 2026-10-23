import SwiftUI
import WidgetKit
import XCTest

/// Not a test of behavior: draws the widget in every style to PNG files so a
/// change to how squares look can be checked by eye without a home screen.
/// Skipped unless a folder is given:
///
///     TEST_RUNNER_PUSHED_RENDER_DIR=/tmp/pushed-renders xcodebuild test \
///         -only-testing:PushedTests/RenderPreviews ...
@MainActor
final class RenderPreviews: XCTestCase {
    private var outputFolder: URL? {
        ProcessInfo.processInfo.environment["PUSHED_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func write(_ view: some View, named name: String, to folder: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "\(name) didn't render")
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// The sample year with its weekends emptied out, so with Saturday and
    /// Sunday as rest days there's a mix of days off, pushes and real gaps.
    private func weekendsOff(_ sample: ContributionSnapshot, asOf now: Date) -> ContributionSnapshot {
        let cal = Calendar(identifier: .gregorian)
        let last = sample.recentLevels.count - 1
        let levels = sample.recentLevels.enumerated().map { index, level -> Int in
            let day = cal.date(byAdding: .day, value: index - last, to: now)!
            let weekday = cal.component(.weekday, from: day)
            return weekday == 1 || weekday == 7 ? 0 : level
        }
        return ContributionSnapshot(
            totalContributions: sample.totalContributions,
            recentLevels: levels,
            lastDate: sample.lastDate,
            fetchedAt: sample.fetchedAt
        )
    }

    func testRenderEveryStyle() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A Saturday, so today itself is a rest day in the second set.
        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-17")!
        let sample = ContributionSnapshot.sample(asOf: now)
        let resting = StreakProtection(
            schedules: [.init(from: "2026-06-01", weekdays: [1, 7])],
            claims: ["2026-10-07": .freeze]
        )
        let sets: [(String, ContributionSnapshot, StreakProtection)] = [
            ("plain", sample, .none),
            ("rest", weekendsOff(sample, asOf: now), resting),
        ]
        let families: [(WidgetFamily, String)] = [(.systemSmall, "small"), (.systemMedium, "medium"), (.systemLarge, "large")]

        for (setName, snapshot, protection) in sets {
            for (family, familyName) in [(WidgetFamily.accessoryCircular, "circular"), (.accessoryRectangular, "rectangular"), (.accessoryInline, "inline")] {
                let size: CGSize = family == .accessoryCircular ? CGSize(width: 72, height: 72)
                    : family == .accessoryRectangular ? CGSize(width: 172, height: 76) : CGSize(width: 234, height: 26)
                let lock = LockScreenView(snapshot: snapshot, family: family, protection: protection, now: now, icon: "🔥")
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .padding(16)
                    .background(Color(hex: 0x1B2A44))
                try write(lock, named: "\(setName)-lock-\(familyName)", to: folder)
            }
            for style in WidgetStyle.designs {
                for layout in WidgetLayout.allCases {
                    for (family, familyName) in families {
                        let card = WidgetPreviewCard(
                            snapshot: snapshot,
                            family: family,
                            style: style,
                            layout: layout,
                            weeks: family == .systemLarge ? 52 : 26,
                            icon: "🔥",
                            custom: .default,
                            protection: protection,
                            now: now
                        )
                        .padding(24)
                        .background(Color(hex: 0x101014))
                        try write(card, named: "\(setName)-\(style.rawValue)-\(layout.rawValue)-\(familyName)", to: folder)
                    }
                }
            }
        }
    }

    /// The per-widget options and the extra style controls, side by side.
    func testRenderCustomizationOptions() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A Wednesday, so the week layout has days done and days to come.
        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-21")!
        let snapshot = weekendsOff(.sample(asOf: now), asOf: now)
        let protection = StreakProtection(schedules: [.init(from: "2026-06-01", weekdays: [1, 7])])

        func card(
            _ name: String, family: WidgetFamily = .systemMedium, style: WidgetStyle = .classic,
            layout: WidgetLayout = .graph, weeks: Int = 26, stat: WidgetStat = .streak,
            custom: CustomWidgetStyle = .default
        ) throws {
            let view = WidgetPreviewCard(
                snapshot: snapshot, family: family, style: style, layout: layout, weeks: weeks,
                stat: stat, icon: "🔥", custom: custom, protection: protection, now: now
            )
            .padding(24)
            .background(Color(hex: 0x101014))
            try write(view, named: name, to: folder)
        }

        try card("range-1-month", weeks: 4)
        try card("range-1-year", weeks: 52)

        for stat in WidgetStat.allCases {
            try card("show-graph-\(stat.rawValue)", style: .aurora, stat: stat)
            try card("show-streak-\(stat.rawValue)", style: .aurora, layout: .streak, stat: stat)
        }

        for style in [WidgetStyle.classic, .terminal, .ember] {
            try card("week-small-\(style.rawValue)", family: .systemSmall, style: style, layout: .week)
            try card("week-medium-\(style.rawValue)", style: style, layout: .week)
            try card("week-large-\(style.rawValue)", family: .systemLarge, style: style, layout: .week)
        }

        var picked = CustomWidgetStyle.starters[1]
        picked.emptySquares = RGBAColor(hex: 0x1F4D47)
        try card("custom-empty-color", style: .custom, custom: picked)
        var roomy = CustomWidgetStyle.default
        roomy.spacing = .roomy
        try card("custom-roomy", style: .custom, weeks: 13, custom: roomy)
        var tight = CustomWidgetStyle.default
        tight.spacing = .tight
        try card("custom-tight", style: .custom, weeks: 13, custom: tight)
        var minimal = CustomWidgetStyle.starters[4]
        minimal.minimal = true
        try card("custom-minimal-graph", style: .custom, custom: minimal)
        try card("custom-minimal-streak", style: .custom, layout: .streak, custom: minimal)
        try card("custom-minimal-week", family: .systemSmall, style: .custom, layout: .week, custom: minimal)
    }

    /// A freeze and rest days in each way of marking them, and the extra
    /// shapes and type for custom styles.
    func testRenderMarksShapesAndType() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Wednesday the 21st. Sunday is a rest day, Tuesday the 20th frozen.
        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-21")!
        let rested = weekendsOff(.sample(asOf: now), asOf: now)
        var levels = rested.recentLevels
        levels[levels.count - 2] = 0
        let snapshot = ContributionSnapshot(
            totalContributions: rested.totalContributions, recentLevels: levels,
            lastDate: rested.lastDate, fetchedAt: rested.fetchedAt
        )
        let protection = StreakProtection(
            schedules: [.init(from: "2026-06-01", weekdays: [1, 7])],
            claims: ["2026-10-20": .freeze]
        )

        func card(
            _ name: String, family: WidgetFamily = .systemMedium, style: WidgetStyle = .classic,
            layout: WidgetLayout = .graph, weeks: Int = 13, custom: CustomWidgetStyle = .default,
            mark: DayOffMark = .ring
        ) throws {
            let view = WidgetPreviewCard(
                snapshot: snapshot, family: family, style: style, layout: layout, weeks: weeks,
                icon: "🔥", custom: custom, protection: protection, dayOffMark: mark, now: now
            )
            .padding(24)
            .background(Color(hex: 0x101014))
            try write(view, named: name, to: folder)
        }

        for mark in DayOffMark.allCases {
            for style in [WidgetStyle.classic, .terminal, .aurora, .paper] {
                try card("mark-\(mark.rawValue)-\(style.rawValue)-week", style: style, layout: .week, mark: mark)
                try card("mark-\(mark.rawValue)-\(style.rawValue)-graph", style: style, mark: mark)
            }
        }

        for shape in CellShapeChoice.allCases {
            var custom = CustomWidgetStyle.starters[shape == .heart ? 4 : 2]
            custom.shape = shape
            try card("shape-\(shape.rawValue)-graph", style: .custom, custom: custom)
            try card("shape-\(shape.rawValue)-week", family: .systemSmall, style: .custom, layout: .week, custom: custom)
        }

        for font in FontChoice.allCases {
            for weight in [WeightChoice.light, .heavy] {
                var custom = CustomWidgetStyle.default
                custom.font = font
                custom.weight = weight
                try card("type-\(font.rawValue)-\(weight.rawValue)", family: .systemSmall, style: .custom, layout: .streak, custom: custom)
            }
        }
    }

    /// Missed days in red next to the rest of a custom style.
    func testRenderMissedDays() throws {
        guard let folder = outputFolder else { throw XCTSkip("set PUSHED_RENDER_DIR to draw the previews") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let now = ContributionCalendar.dateFormatter.date(from: "2026-10-21")!
        let snapshot = weekendsOff(.sample(asOf: now), asOf: now)
        // Watching since the start of August: earlier gaps stay plain.
        let protection = StreakProtection(
            schedules: [.init(from: "2026-06-01", weekdays: [1, 7])],
            claims: ["2026-10-20": .freeze],
            trackedSince: "2026-08-01"
        )
        for (index, base) in [CustomWidgetStyle.default, CustomWidgetStyle.starters[3]].enumerated() {
            var custom = base
            custom.missedSquares = RGBAColor(hex: custom.usesLightText ? 0xE5484D : 0xD93D42)
            for (family, name, layout) in [(WidgetFamily.systemMedium, "graph", WidgetLayout.graph), (.systemLarge, "large", .graph), (.systemMedium, "week", .week)] {
                let view = WidgetPreviewCard(
                    snapshot: snapshot, family: family, style: .custom, layout: layout, weeks: 26,
                    icon: "🔥", custom: custom, protection: protection, now: now
                )
                .padding(24)
                .background(Color(hex: 0x101014))
                try write(view, named: "missed-\(index)-\(name)", to: folder)
            }
        }
    }
}
