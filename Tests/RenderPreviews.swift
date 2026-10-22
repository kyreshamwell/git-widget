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
}
