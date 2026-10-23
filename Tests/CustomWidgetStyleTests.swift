import SwiftUI
import XCTest

final class CustomWidgetStyleTests: XCTestCase {
    private func solid(_ hex: UInt32) -> CustomWidgetStyle {
        var style = CustomWidgetStyle.default
        style.usesGradient = false
        style.background = RGBAColor(hex: hex)
        return style
    }

    // MARK: - Saving

    func testADesignSurvivesSaving() throws {
        var style = CustomWidgetStyle.default
        style.squares = RGBAColor(hex: 0x22D3EE)
        style.usesGradient = false
        style.shape = .dot
        style.font = .serif
        style.glows = false

        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded, style)
    }

    func testMissingOrUnknownFieldsFallBackWithoutLosingTheRest() throws {
        // A future version's shape, and no background saved at all.
        let json = #"{"squares":{"red":1,"green":0,"blue":0,"opacity":1},"shape":"triangle"}"#
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.squares, RGBAColor(red: 1, green: 0, blue: 0), "the readable choice is kept")
        XCTAssertEqual(decoded.shape, CustomWidgetStyle.default.shape)
        XCTAssertEqual(decoded.background, CustomWidgetStyle.default.background)
    }

    func testColorsSurviveTheColorPickerRoundTrip() {
        let original = RGBAColor(hex: 0xFF7A59)
        let back = RGBAColor(original.color)
        XCTAssertEqual(back.red, original.red, accuracy: 0.001)
        XCTAssertEqual(back.green, original.green, accuracy: 0.001)
        XCTAssertEqual(back.blue, original.blue, accuracy: 0.001)
        XCTAssertEqual(back.opacity, 1, accuracy: 0.001)
    }

    // MARK: - Staying readable

    func testContrastMatchesWCAG() {
        XCTAssertEqual(RGBAColor.white.contrast(with: RGBAColor(red: 0, green: 0, blue: 0)), 21, accuracy: 0.01)
        XCTAssertEqual(RGBAColor.white.contrast(with: .white), 1, accuracy: 0.001)
        // #767676 on white is the textbook just-passes-AA example, 4.54:1.
        XCTAssertEqual(RGBAColor(hex: 0x767676).contrast(with: .white), 4.54, accuracy: 0.02)
    }

    func testTextTurnsDarkOnLightBackdropsAndLightOnDarkOnes() {
        let cream = solid(0xFFF8E7)
        XCTAssertFalse(cream.usesLightText)
        XCTAssertEqual(WidgetStyle.custom.pinnedColorScheme(custom: cream), .light)

        let navy = solid(0x101828)
        XCTAssertTrue(navy.usesLightText)
        XCTAssertEqual(WidgetStyle.custom.pinnedColorScheme(custom: navy), .dark)
    }

    func testSquaresOnlyColorTheNumberWhenTheyRead() {
        var style = solid(0x0B1026)
        style.squares = RGBAColor(hex: 0xFF7A59)
        XCTAssertTrue(style.squaresStandOut)

        style.squares = RGBAColor(hex: 0x1A2040) // navy on navy
        XCTAssertFalse(style.squaresStandOut, "the number would vanish; it should fall back to the text color")
    }

    func testAGradientIsJudgedByItsWeakestEnd() {
        var style = CustomWidgetStyle.default
        style.usesGradient = true
        style.background = RGBAColor(hex: 0xFFFFFF)
        style.backgroundEnd = RGBAColor(hex: 0x000000)
        style.squares = RGBAColor(hex: 0xFFFF66) // bright on black, invisible on white
        XCTAssertFalse(style.squaresStandOut)
    }

    func testTheStartingDesignIsReadable() {
        let style = CustomWidgetStyle.default
        XCTAssertTrue(style.usesLightText)
        XCTAssertTrue(style.squaresStandOut)
    }

    func testAPickedEmptyColorIsUsedAndAnAutomaticOneIsWorkedOut() {
        var style = CustomWidgetStyle.default
        XCTAssertNil(style.emptySquares)
        XCTAssertTrue(style.emptySquaresShow)

        style.emptySquares = RGBAColor(hex: 0x445566)
        XCTAssertEqual(RGBAColor(style.theme.levels[0]), RGBAColor(hex: 0x445566))
    }

    func testAnEmptyColorMatchingTheBackdropIsFlagged() {
        var style = solid(0x0B1026)
        style.emptySquares = RGBAColor(hex: 0x0B1026)
        XCTAssertFalse(style.emptySquaresShow)
    }

    func testSpacingAndMinimalReachTheTheme() {
        var style = CustomWidgetStyle.default
        XCTAssertEqual(style.theme.spacing, 1)
        XCTAssertFalse(style.theme.hidesText)

        style.spacing = .roomy
        style.minimal = true
        XCTAssertGreaterThan(style.theme.spacing, 1)
        XCTAssertTrue(style.theme.hidesText)
        XCTAssertTrue(style.theme.monochrome.hidesText, "a tinted home screen keeps it minimal")
    }

    func testAStyleSavedBeforeTheseOptionsGetsTheirDefaults() throws {
        let json = #"{"squares":{"red":1,"green":0,"blue":0,"opacity":1},"shape":"dot"}"#
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(json.utf8))

        XCTAssertNil(decoded.emptySquares)
        XCTAssertEqual(decoded.spacing, .standard)
        XCTAssertFalse(decoded.minimal)
        XCTAssertEqual(decoded.shape, .dot)
    }

    func testTheNewOptionsSurviveSaving() throws {
        var style = CustomWidgetStyle.default
        style.emptySquares = RGBAColor(hex: 0x222222)
        style.spacing = .tight
        style.minimal = true
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded, style)
    }

    func testAMissedDayColorIsOptional() throws {
        var style = CustomWidgetStyle.default
        XCTAssertNil(style.theme.missed)

        style.missedSquares = RGBAColor(hex: 0xE5484D)
        XCTAssertEqual(style.theme.missed.map(RGBAColor.init), RGBAColor(hex: 0xE5484D))
        XCTAssertNil(style.theme.monochrome.missed, "one tint can't color it apart")

        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded.missedSquares, style.missedSquares)
    }

    func testAMissedColorMatchingTheBackdropIsFlagged() {
        var style = solid(0x0B1026)
        XCTAssertTrue(style.missedSquaresShow, "none picked is fine")
        style.missedSquares = RGBAColor(hex: 0x0B1026)
        XCTAssertFalse(style.missedSquaresShow)
        style.missedSquares = RGBAColor(hex: 0xE5484D)
        XCTAssertTrue(style.missedSquaresShow)
    }

    func testEveryChoiceHasAName() {
        for name in CellShapeChoice.allCases.map(\.name) + FontChoice.allCases.map(\.name)
            + WeightChoice.allCases.map(\.name) + SpacingChoice.allCases.map(\.name)
            + DayOffMark.allCases.map(\.name) + TestScenario.allCases.map(\.name) {
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testEveryShapeHasAnOutlineToDraw() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        for shape in CellShapeChoice.allCases {
            let path = CellShape(cornerFraction: shape.cornerFraction, form: shape.form).path(in: rect)
            XCTAssertFalse(path.isEmpty, "\(shape)")
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingRect), "\(shape) stays inside its cell")
        }
    }

    func testShapesAndTypeReachTheTheme() {
        var style = CustomWidgetStyle.default
        style.shape = .heart
        style.font = .condensed
        style.weight = .heavy
        let theme = style.theme

        XCTAssertEqual(theme.form, .heart)
        XCTAssertEqual(theme.fontWidth, .compressed)
        XCTAssertEqual(theme.numberWeight, .heavy)
        XCTAssertEqual(theme.monochrome.form, .heart, "a tinted home screen keeps the shape")
    }

    func testAFreezeStaysApartFromBlueSquares() {
        var blue = solid(0x0B1026)
        blue.squares = RGBAColor(hex: 0x7DD3FC)
        XCTAssertNotEqual(RGBAColor(blue.theme.freeze), RGBAColor(hex: 0x7DD3FC))

        var coral = solid(0x0B1026)
        coral.squares = RGBAColor(hex: 0xFF7A59)
        XCTAssertEqual(RGBAColor(coral.theme.freeze), RGBAColor(hex: 0x7DD3FC), "ice blue everywhere else")
    }

    func testAStyleSavedBeforeWeightWasAChoiceStaysBold() throws {
        let decoded = try JSONDecoder().decode(CustomWidgetStyle.self, from: Data(#"{"shape":"star"}"#.utf8))
        XCTAssertEqual(decoded.weight, .bold)
        XCTAssertEqual(decoded.shape, .star)
    }

    func testEveryStarterLookIsReadable() {
        for (index, style) in CustomWidgetStyle.starters.enumerated() {
            XCTAssertTrue(style.squaresStandOut, "starter \(index)")
        }
        XCTAssertEqual(Set(CustomWidgetStyle.starters.map(\.squares.red)).count, CustomWidgetStyle.starters.count, "no two alike")
    }

    func testNotYetIsARingSinceTheSquareColorCouldBeAnything() {
        XCTAssertTrue(CustomWidgetStyle.default.theme.ringsPending)
        XCTAssertFalse(WidgetStyle.ember.theme(for: .dark).ringsPending, "built-in styles keep their two colors")
    }

    func testChoicesMapToTheirShapeAndType() {
        XCTAssertEqual(CellShapeChoice.square.cornerFraction, 0)
        XCTAssertEqual(CellShapeChoice.dot.cornerFraction, 0.5)
        XCTAssertEqual(FontChoice.monospaced.design, .monospaced)

        var style = CustomWidgetStyle.default
        style.shape = .dot
        style.font = .serif
        let theme = WidgetStyle.custom.theme(for: .dark, custom: style)
        XCTAssertEqual(theme.cornerFraction, 0.5)
        XCTAssertEqual(theme.fontDesign, .serif)
        XCTAssertEqual(theme.levels.count, 5)
    }
}
