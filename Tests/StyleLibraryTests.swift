import XCTest

final class StyleLibraryTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    private func design(_ hex: UInt32) -> CustomWidgetStyle {
        var style = CustomWidgetStyle.default
        style.squares = RGBAColor(hex: hex)
        return style
    }

    /// Three saved styles: Coral, Mint and Sky, none checked.
    private var three: StyleLibrary {
        var library = StyleLibrary.starting(with: design(0xFF7A59))
        library.styles[0].name = "Coral"
        library.add(design(0x6EE7B7), named: "Mint")
        library.add(design(0x7DD3FC), named: "Sky")
        return library
    }

    // MARK: - Carrying over the old custom style

    func testTheOldCustomStyleBecomesTheFirstSavedOne() {
        let earlier = design(0x22D3EE)
        let library = StyleLibrary.starting(with: earlier)

        XCTAssertEqual(library.styles.count, 1)
        XCTAssertEqual(library.styles[0].style, earlier)
        XCTAssertEqual(library.styles[0].name, "My Style")
    }

    func testTheCarriedOverStyleHasTheSameIDEverywhere() {
        // The app and the widget each build it before either has saved it.
        XCTAssertEqual(StyleLibrary.starting().styles[0].id, StyleLibrary.starting().styles[0].id)
        XCTAssertEqual(StyleLibrary.starting().styles[0].id, StyleLibrary.firstStyleID)
    }

    func testAWidgetSetToCustomBeforeThereWasAChoiceWearsTheFirstStyle() {
        let look = three.look(for: .custom, saved: nil)
        XCTAssertEqual(look.style, .custom)
        XCTAssertEqual(look.name, "Coral")
    }

    // MARK: - Picking a saved style

    func testAWidgetWearsTheStylePickedForIt() {
        let library = three
        let mint = library.styles[1]
        XCTAssertEqual(library.look(for: .custom, saved: mint.id).custom, mint.style)
    }

    func testADeletedStyleFallsBackToTheFirst() {
        var library = three
        let sky = library.styles[2]
        library[sky.id] = nil

        XCTAssertEqual(library.styles.count, 2)
        XCTAssertEqual(library.look(for: .custom, saved: sky.id).name, "Coral")
    }

    func testTheLastStyleCannotBeDeleted() {
        var library = StyleLibrary.starting()
        library[StyleLibrary.firstStyleID] = nil

        XCTAssertEqual(library.styles.count, 1)
        XCTAssertFalse(library.canRemove)
    }

    func testBuiltInStylesIgnoreTheLibrary() {
        let look = three.look(for: .terminal, saved: three.styles[1].id)
        XCTAssertEqual(look.style, .terminal)
        XCTAssertEqual(look.name, "Terminal")
    }

    // MARK: - Adding and copying

    func testNewStylesGetNamesThatArentTaken() {
        var library = StyleLibrary.starting()
        let second = library.add()
        let third = library.add(named: "Style 2")

        XCTAssertEqual(second?.name, "Style 2")
        XCTAssertEqual(third?.name, "Style 2 2")
    }

    func testEachNewStyleStartsFromADifferentLook() {
        var library = StyleLibrary.starting()
        let second = library.add()
        let third = library.add()

        XCTAssertNotEqual(second?.style, library.styles[0].style)
        XCTAssertNotEqual(second?.style, third?.style)
    }

    func testACopySitsBesideTheOriginal() {
        var library = three
        let copy = library.duplicate(library.styles[0].id)

        XCTAssertEqual(library.styles.map(\.displayName), ["Coral", "Coral copy", "Mint", "Sky"])
        XCTAssertEqual(copy?.style, library.styles[0].style)
        XCTAssertNotEqual(copy?.id, library.styles[0].id)
    }

    func testTheLibraryStopsGrowingWhenFull() {
        var library = StyleLibrary.starting()
        while library.canAdd { library.add() }

        XCTAssertEqual(library.styles.count, StyleLibrary.maxStyles)
        XCTAssertNil(library.add())
        XCTAssertNil(library.duplicate(library.styles[0].id))
    }

    func testAClearedNameStillShowsAsSomething() {
        XCTAssertEqual(SavedStyle(name: "   ").displayName, "Untitled")
    }

    // MARK: - Daily rotation

    func testTheRotationMovesOnByOneEachDay() {
        let library = three
        let names = (12...17).map { library.rotationPick(on: date(String(format: "2026-10-%02d", $0))).name }

        XCTAssertEqual(Set(names), ["Coral", "Mint", "Sky"])
        for (today, tomorrow) in zip(names, names.dropFirst()) {
            XCTAssertNotEqual(today, tomorrow)
        }
        XCTAssertEqual(names[0], names[3], "three styles come round again every three days")
    }

    func testTheRotationHoldsAllDay() {
        let library = three
        let morning = date("2026-10-12").addingTimeInterval(60)
        let night = date("2026-10-12").addingTimeInterval(24 * 3600 - 60)
        XCTAssertEqual(library.rotationPick(on: morning), library.rotationPick(on: night))
    }

    func testOnlyCheckedStylesTakeTurnsOnceAnyAre() {
        var library = three
        library.styles[0].inRotation = true
        library.styles[2].inRotation = true

        XCTAssertEqual(library.rotation.map(\.name), ["Coral", "Sky"])
        XCTAssertTrue(library.hasCheckedStyles)
    }

    func testWithNothingCheckedAllOfYourStylesTakeTurns() {
        XCTAssertEqual(three.rotation.map(\.name), ["Coral", "Mint", "Sky"])
        XCTAssertFalse(three.hasCheckedStyles)
    }

    func testOneCheckedStyleStaysPut() {
        var library = three
        library.toggleRotation(library.styles[1].id)
        let week = (12...18).map { library.rotationPick(on: date(String(format: "2026-10-%02d", $0))).name }
        XCTAssertEqual(Set(week), ["Mint"])
    }

    func testBuiltInStylesCanBeCheckedOneByOne() {
        var library = three
        library.toggleRotation(.paper)
        library.toggleRotation(.terminal)

        XCTAssertEqual(library.rotation.map(\.style), [.terminal, .paper], "in the gallery's order")
        XCTAssertTrue(library.isInRotation(.paper))

        library.toggleRotation(.paper)
        XCTAssertFalse(library.isInRotation(.paper))
        XCTAssertEqual(library.rotation.map(\.style), [.terminal])
    }

    func testOnlyRealBuiltInStylesCanBeChecked() {
        var library = three
        library.toggleRotation(.custom)
        library.toggleRotation(.rotation)
        XCTAssertTrue(library.rotatingBuiltIns.isEmpty)
    }

    func testAWidgetSetToRotationWearsThatDaysPick() {
        let library = three
        let day = date("2026-10-14")
        XCTAssertEqual(library.look(for: .rotation, on: day), library.rotationPick(on: day))
        XCTAssertNotEqual(library.look(for: .rotation, on: day).style, .rotation, "always something drawable")
    }

    // MARK: - Saved data

    func testTheLibrarySurvivesSaving() throws {
        var library = three
        library.styles[1].inRotation = true
        library.rotatingBuiltIns = [.ember]

        let decoded = try JSONDecoder().decode(StyleLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded, library)
    }

    func testASavedStyleMissingFieldsKeepsItsDesign() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","style":{"squares":{"red":1,"green":0,"blue":0,"opacity":1}}}"#
        let decoded = try JSONDecoder().decode(SavedStyle.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.id, StyleLibrary.firstStyleID)
        XCTAssertEqual(decoded.style.squares, RGBAColor(red: 1, green: 0, blue: 0))
        XCTAssertFalse(decoded.inRotation)
        XCTAssertEqual(decoded.displayName, "Untitled")
    }
}
