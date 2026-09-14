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
        for style in WidgetStyle.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for mode in modes {
                    let theme = style.theme(for: scheme, renderingMode: mode)
                    XCTAssertEqual(theme.levels.count, 5, "\(style) needs levels 0 through 4")
                }
            }
        }
    }

    func testTintedHomeScreensGetTheMonochromeTheme() {
        for style in WidgetStyle.allCases {
            XCTAssertFalse(style.theme(for: .dark).isMonochrome)
            let tinted = style.theme(for: .dark, renderingMode: .accented)
            XCTAssertTrue(tinted.isMonochrome)
            XCTAssertFalse(tinted.glows, "glows turn to smudges once the color is gone")
            XCTAssertEqual(tinted.cornerFraction, style.theme(for: .dark).cornerFraction, "the style's shape survives")
        }
    }

    func testOnlyClassicFollowsThePhonesAppearance() {
        XCTAssertNil(WidgetStyle.classic.pinnedColorScheme())
        for style in WidgetStyle.allCases where style != .classic {
            XCTAssertNotNil(style.pinnedColorScheme(), "\(style) paints its own backdrop")
        }
    }

    func testOutOfRangeLevelsClampInsteadOfCrashing() {
        let theme = WidgetStyle.ember.theme(for: .dark)
        XCTAssertEqual(theme.color(for: -1), theme.color(for: 0))
        XCTAssertEqual(theme.color(for: 9), theme.color(for: 4))
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
