import SwiftUI
import WidgetKit
import XCTest

final class WidgetStyleTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    // MARK: - Themes

    func testEveryStyleHasAColorForEachLevelInEveryMode() {
        let modes: [WidgetRenderingMode] = [.fullColor, .accented, .vibrant]
        for style in WidgetStyle.designs {
            for scheme in [ColorScheme.light, .dark] {
                for mode in modes {
                    let theme = style.theme(for: scheme, renderingMode: mode)
                    XCTAssertEqual(theme.levels.count, 5, "\(style) needs levels 0 through 4")
                }
            }
        }
    }

    func testTintedHomeScreensGetTheMonochromeTheme() {
        for style in WidgetStyle.designs {
            XCTAssertFalse(style.theme(for: .dark).isMonochrome)
            let tinted = style.theme(for: .dark, renderingMode: .accented)
            XCTAssertTrue(tinted.isMonochrome)
            XCTAssertFalse(tinted.glows, "glows turn to smudges once the color is gone")
            XCTAssertEqual(tinted.cornerFraction, style.theme(for: .dark).cornerFraction, "the style's shape survives")
        }
    }

    func testOnlyClassicFollowsThePhonesAppearance() {
        XCTAssertNil(WidgetStyle.classic.pinnedColorScheme())
        for style in WidgetStyle.designs where style != .classic {
            XCTAssertNotNil(style.pinnedColorScheme(), "\(style) paints its own backdrop")
        }
    }

    func testOutOfRangeLevelsClampInsteadOfCrashing() {
        let theme = WidgetStyle.ember.theme(for: .dark)
        XCTAssertEqual(theme.color(for: -1), theme.color(for: 0))
        XCTAssertEqual(theme.color(for: 9), theme.color(for: 4))
    }

    // MARK: - Telling the levels apart

    /// What a level actually looks like on screen: its color laid over the
    /// backdrop, since several styles draw their squares part see-through.
    private func shown(_ color: Color, over backdrop: RGBAColor) -> RGBAColor {
        let top = RGBAColor(color)
        func mix(_ a: Double, _ b: Double) -> Double { a * top.opacity + b * (1 - top.opacity) }
        return RGBAColor(
            red: mix(top.red, backdrop.red), green: mix(top.green, backdrop.green), blue: mix(top.blue, backdrop.blue)
        )
    }

    /// Distance between two colors in OKLab, which tracks how different they
    /// look far better than comparing brightness alone: two colors of equal
    /// brightness and different hue still score as apart.
    private func difference(_ a: RGBAColor, _ b: RGBAColor) -> Double {
        func lab(_ c: RGBAColor) -> (Double, Double, Double) {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let (r, g, b) = (linear(c.red), linear(c.green), linear(c.blue))
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            return (
                0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            )
        }
        let (x, y) = (lab(a), lab(b))
        return sqrt(pow(x.0 - y.0, 2) + pow(x.1 - y.1, 2) + pow(x.2 - y.2, 2))
    }

    /// Every backdrop each built-in style can be seen on, with the scheme it
    /// goes with. Classic gets the system's light and dark widget platters.
    private var builtInBackdrops: [(style: WidgetStyle, scheme: ColorScheme, backdrop: RGBAColor)] {
        var all: [(WidgetStyle, ColorScheme, RGBAColor)] = [
            (.classic, .light, RGBAColor(hex: 0xFFFFFF)),
            (.classic, .dark, RGBAColor(hex: 0x1C1C1E)),
        ]
        for style in WidgetStyle.designs where !style.backdrop.isEmpty {
            for hex in style.backdrop {
                all.append((style, style.pinnedColorScheme() ?? .dark, RGBAColor(hex: hex)))
            }
        }
        return all
    }

    func testNoTwoNeighbouringLevelsLookAlike() {
        // A floor, not a target: GitHub's own dark palette sits just above
        // it. It catches a palette whose steps have collapsed into each other.
        for (style, scheme, backdrop) in builtInBackdrops {
            let levels = style.theme(for: scheme).levels.map { shown($0, over: backdrop) }
            for level in 1..<levels.count {
                XCTAssertGreaterThan(
                    difference(levels[level - 1], levels[level]), 0.07,
                    "\(style) levels \(level - 1) and \(level) are too close"
                )
            }
        }
    }

    func testEveryStyleGetsBrighterOrDarkerInOneDirection() {
        // Busier days move steadily away from the backdrop, never back toward it.
        for (style, scheme, backdrop) in builtInBackdrops {
            let contrasts = style.theme(for: scheme).levels.dropFirst().map {
                shown($0, over: backdrop).contrast(with: backdrop)
            }
            XCTAssertEqual(contrasts, contrasts.sorted(), "\(style) on \(scheme)")
        }
    }

    func testTerminalTellsAnEmptyDayFromAQuietOneByShape() {
        // Filled dark green against filled dim green was the problem. Empty
        // days are hollow now, and the first level is plainly lit.
        let theme = WidgetStyle.terminal.theme(for: .dark)
        XCTAssertTrue(theme.outlinesEmpty)
        for hex in WidgetStyle.terminal.backdrop {
            let backdrop = RGBAColor(hex: hex)
            XCTAssertGreaterThan(shown(theme.color(for: 1), over: backdrop).contrast(with: backdrop), 3)
        }
        XCTAssertFalse(theme.monochrome.outlinesEmpty, "a tinted home screen keeps its stepped fills")
    }

    func testTerminalGreensClimbInEvenSteps() {
        let backdrop = RGBAColor(hex: 0x0C1A10)
        let levels = WidgetStyle.terminal.theme(for: .dark).levels.dropFirst().map { shown($0, over: backdrop) }
        let steps = zip(levels, levels.dropFirst()).map { difference($0, $1) }
        XCTAssertEqual(steps.count, 3)
        XCTAssertLessThan(steps.max()! - steps.min()!, 0.03, "steps of \(steps)")
    }

    // MARK: - Sample data

    func testSampleSnapshotHasTheShapeOfARealOne() {
        // Jul 7 2026 is a Tuesday: expect 3 trailing partial days (Sun/Mon/Tue).
        let now = date("2026-07-07")
        let sample = ContributionSnapshot.sample(streak: 12, asOf: now)

        XCTAssertEqual(sample.recentLevels.count % 7, 3)
        XCTAssertEqual(sample.lastDate, "2026-07-07")
        XCTAssertEqual(sample.currentStreak(asOf: now), 12)
        XCTAssertTrue(sample.committedToday(asOf: now))
        XCTAssertGreaterThan(sample.totalContributions, 0)

        let firstDate = cal.date(byAdding: .day, value: -(sample.recentLevels.count - 1), to: now)!
        XCTAssertEqual(cal.component(.weekday, from: firstDate), 1, "grid column 0 must start on a Sunday")
    }

    func testSampleSnapshotAlignsOnEveryDayOfTheWeek() {
        // Saturday ends a full week, so it's the one day with no partial column.
        for day in 5...11 { // Jul 5 2026 (Sunday) through Jul 11 (Saturday)
            let now = date(String(format: "2026-07-%02d", day))
            let sample = ContributionSnapshot.sample(asOf: now)
            let firstDate = cal.date(byAdding: .day, value: -(sample.recentLevels.count - 1), to: now)!
            XCTAssertEqual(cal.component(.weekday, from: firstDate), 1, "misaligned on Jul \(day)")
            XCTAssertEqual(sample.recentLevels.count / 7, 52)
        }
    }

    func testSampleSnapshotIsTheSameEveryTime() {
        let now = date("2026-07-07")
        XCTAssertEqual(
            ContributionSnapshot.sample(asOf: now).recentLevels,
            ContributionSnapshot.sample(asOf: now).recentLevels,
            "previews would flicker between renders"
        )
    }

    // MARK: - Last seven days

    func testLastDaysEndsOnTheFinalEntryWhenTheSnapshotIsCurrent() {
        let snapshot = ContributionSnapshot.sample(streak: 12, asOf: date("2026-07-07"))
        let week = snapshot.levels(lastDays: 7, asOf: date("2026-07-07"))
        XCTAssertEqual(week, Array(snapshot.recentLevels.suffix(7)))
    }

    func testLastDaysCountsDaysSinceAStaleFetchAsEmpty() {
        // Fetched Jul 7, drawn Jul 9: the last two squares are Jul 8 and 9,
        // not a repeat of Jul 6 and 7 wearing today's position.
        let snapshot = ContributionSnapshot.sample(streak: 12, asOf: date("2026-07-07"))
        let week = snapshot.levels(lastDays: 7, asOf: date("2026-07-09"))
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(Array(week.suffix(2)), [0, 0])
        XCTAssertEqual(Array(week.prefix(5)), Array(snapshot.recentLevels.suffix(5)))
    }

    func testLastDaysPadsAShortHistory() {
        let snapshot = ContributionSnapshot(
            totalContributions: 2, recentLevels: [1, 2], lastDate: "2026-07-07", fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.levels(lastDays: 7, asOf: date("2026-07-07")), [0, 0, 0, 0, 0, 1, 2])
    }
}
