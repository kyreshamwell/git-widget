import XCTest

/// What's stored in the shared container, and what happens when it's missing
/// or unreadable: the cases someone updating from an earlier version, or
/// recovering from a bad write, actually lands in. Each test puts the keys it
/// touches back the way it found them.
final class AppConfigTests: XCTestCase {
    private let keys = [
        AppConfig.styleLibraryKey, AppConfig.customStyleKey, AppConfig.streakProtectionKey,
        AppConfig.dayOffMarkKey, AppConfig.usernameDefaultsKey,
    ]
    private var saved: [String: Any] = [:]
    private var defaults: UserDefaults { AppConfig.sharedDefaults }

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    // MARK: - Saved styles

    func testTheCustomStyleFromVersionOnePointOneCarriesOver() throws {
        var earlier = CustomWidgetStyle.default
        earlier.squares = RGBAColor(hex: 0x22D3EE)
        earlier.shape = .dot
        defaults.set(try JSONEncoder().encode(earlier), forKey: AppConfig.customStyleKey)

        let library = AppConfig.styleLibrary
        XCTAssertEqual(library.styles.count, 1)
        XCTAssertEqual(library.styles[0].style, earlier, "widgets set to Custom keep their look")
        XCTAssertEqual(library.styles[0].id, StyleLibrary.firstStyleID)
    }

    func testWithNothingSavedThereIsStillOneStyle() {
        let library = AppConfig.styleLibrary
        XCTAssertEqual(library.styles.count, 1)
        XCTAssertEqual(library.styles[0].style, .default)
    }

    func testAnUnreadableLibraryFallsBackInsteadOfLeavingWidgetsBlank() {
        defaults.set(Data("not json".utf8), forKey: AppConfig.styleLibraryKey)
        XCTAssertEqual(AppConfig.styleLibrary.styles.count, 1)
    }

    func testAnEmptyLibraryIsNeverHandedOut() throws {
        defaults.set(try JSONEncoder().encode(StyleLibrary(styles: [])), forKey: AppConfig.styleLibraryKey)
        XCTAssertFalse(AppConfig.styleLibrary.styles.isEmpty)
    }

    func testTheLibrarySurvivesBeingSaved() {
        var library = StyleLibrary.starting()
        library.add(named: "Mint")
        library.styles[1].inRotation = true
        library.rotatingBuiltIns = [.terminal]
        AppConfig.styleLibrary = library

        XCTAssertEqual(AppConfig.styleLibrary, library)
    }

    // MARK: - Rest days and missed days

    func testUnreadableRestDaysFallBackToTheStartingSettings() {
        defaults.set(Data("{".utf8), forKey: AppConfig.streakProtectionKey)
        XCTAssertEqual(AppConfig.streakProtection, .initial)
    }

    func testAnUnknownDayOffMarkFallsBackToStripes() {
        defaults.set("sparkles", forKey: AppConfig.dayOffMarkKey)
        XCTAssertEqual(AppConfig.dayOffMark, .stripes)

        AppConfig.dayOffMark = .dot
        XCTAssertEqual(AppConfig.dayOffMark, .dot)
    }

    func testForgettingAnAccountKeepsTheRestWeekdays() {
        AppConfig.streakProtection = StreakProtection(
            schedules: [.init(from: "2026-01-01", weekdays: [1, 7])],
            claims: ["2026-10-08": .freeze],
            trackedSince: "2026-09-01"
        )
        AppConfig.forgetAccountHistory()

        let after = AppConfig.streakProtection
        XCTAssertEqual(after.chosenWeekdays, [1, 7])
        XCTAssertTrue(after.claims.isEmpty)
        XCTAssertNil(after.trackedSince)
    }

    func testConnectingStartsTrackingThatDay() {
        let day = ContributionCalendar.dateFormatter.date(from: "2026-10-22")!
        AppConfig.startTracking(on: day)
        XCTAssertEqual(AppConfig.streakProtection.trackedSince, "2026-10-22")
    }

    func testTheStartDateIsOnlyFilledInForAnAccountAlreadyConnected() {
        AppConfig.backfillTrackingStart()
        XCTAssertNil(AppConfig.streakProtection.trackedSince, "nobody connected yet")

        defaults.set("someone", forKey: AppConfig.usernameDefaultsKey)
        AppConfig.backfillTrackingStart()
        XCTAssertNotNil(AppConfig.streakProtection.trackedSince)
    }

    func testFillingInTheStartDateNeverOverwritesOne() {
        defaults.set("someone", forKey: AppConfig.usernameDefaultsKey)
        AppConfig.startTracking(on: ContributionCalendar.dateFormatter.date(from: "2026-09-01")!)
        AppConfig.backfillTrackingStart()
        XCTAssertEqual(AppConfig.streakProtection.trackedSince, "2026-09-01")
    }
}
