import SwiftUI
import UIKit

/// The style people design themselves: backdrop, square color, cell shape,
/// type and glow. Saved in the shared container so the widget draws exactly
/// what the editor previewed, and applied per widget by choosing "Custom" in
/// Edit Widget.
///
/// Only the choices are stored. Everything that has to stay legible (text
/// color, the empty-day squares, the status dot) is worked out from them, so
/// no combination of picks can make the widget unreadable.
struct CustomWidgetStyle: Codable, Equatable, Sendable {
    var background: RGBAColor
    var backgroundEnd: RGBAColor
    var usesGradient: Bool
    var squares: RGBAColor
    var shape: CellShapeChoice
    var font: FontChoice
    var glows: Bool
    /// The color of a day with nothing on it. Nil works one out from the
    /// backdrop, which is what keeps it readable on any background.
    var emptySquares: RGBAColor? = nil
    /// The outline color for the day a streak ended. Nil leaves it like any
    /// other empty day.
    var missedSquares: RGBAColor? = nil
    var spacing: SpacingChoice = .standard
    /// Just the number and the squares: no labels, captions or status words.
    var minimal = false
    /// How heavy the big number is.
    var weight: WeightChoice = .bold

    /// Where a new custom style starts: coral squares on a midnight gradient,
    /// a look none of the built-in styles cover.
    static let `default` = CustomWidgetStyle(
        background: RGBAColor(hex: 0x2A1B4D),
        backgroundEnd: RGBAColor(hex: 0x0B1026),
        usesGradient: true,
        squares: RGBAColor(hex: 0xFF7A59),
        shape: .rounded,
        font: .rounded,
        glows: true
    )

    /// Where each new saved style starts, taken in turn, so a second style
    /// doesn't open as a copy of the first. The first is the default above.
    static let starters: [CustomWidgetStyle] = [
        .default,
        CustomWidgetStyle(
            background: RGBAColor(hex: 0x0F2E2B), backgroundEnd: RGBAColor(hex: 0x061716), usesGradient: true,
            squares: RGBAColor(hex: 0x5EEAD4), shape: .square, font: .monospaced, glows: true
        ),
        CustomWidgetStyle(
            background: RGBAColor(hex: 0x14213D), backgroundEnd: RGBAColor(hex: 0x0A1020), usesGradient: true,
            squares: RGBAColor(hex: 0x7DD3FC), shape: .rounded, font: .standard, glows: false
        ),
        CustomWidgetStyle(
            background: RGBAColor(hex: 0xFFF8E7), backgroundEnd: RGBAColor(hex: 0xFFF8E7), usesGradient: false,
            squares: RGBAColor(hex: 0xD9480F), shape: .dot, font: .serif, glows: false
        ),
        CustomWidgetStyle(
            background: RGBAColor(hex: 0x3B0A45), backgroundEnd: RGBAColor(hex: 0x1A0420), usesGradient: true,
            squares: RGBAColor(hex: 0xF9A8D4), shape: .rounded, font: .rounded, glows: true
        ),
    ]
}

// MARK: - Choices

enum CellShapeChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case square, rounded, dot, diamond, hexagon, heart, star

    var id: String { rawValue }

    var name: String {
        switch self {
        case .square: "Square"
        case .rounded: "Rounded"
        case .dot: "Dot"
        case .diamond: "Diamond"
        case .hexagon: "Hexagon"
        case .heart: "Heart"
        case .star: "Star"
        }
    }

    /// Only boxes use it; the other forms have no corners to round.
    var cornerFraction: CGFloat {
        switch self {
        case .square: 0
        case .dot: 0.5
        default: 0.28
        }
    }

    var form: CellForm {
        switch self {
        case .square, .rounded, .dot: .box
        case .diamond: .diamond
        case .hexagon: .hexagon
        case .heart: .heart
        case .star: .star
        }
    }
}

enum WeightChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case light, regular, bold, heavy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .light: "Light"
        case .regular: "Regular"
        case .bold: "Bold"
        case .heavy: "Heavy"
        }
    }

    var weight: Font.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

enum SpacingChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case tight, standard, roomy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tight: "Tight"
        case .standard: "Standard"
        case .roomy: "Roomy"
        }
    }

    var scale: CGFloat {
        switch self {
        case .tight: 0.4
        case .standard: 1
        case .roomy: 1.8
        }
    }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, rounded, monospaced, serif, condensed, wide

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: "Standard"
        case .rounded: "Rounded"
        case .monospaced: "Mono"
        case .serif: "Serif"
        case .condensed: "Condensed"
        case .wide: "Wide"
        }
    }

    var width: Font.Width {
        switch self {
        case .condensed: .compressed
        case .wide: .expanded
        default: .standard
        }
    }

    var design: Font.Design {
        switch self {
        case .standard, .condensed, .wide: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }
}

// MARK: - Derived theme

extension CustomWidgetStyle {
    /// Every color the text has to sit on: both ends of a gradient, or the
    /// one solid color.
    private var backdrop: [RGBAColor] {
        usesGradient ? [background, backgroundEnd] : [background]
    }

    /// White or near-black, whichever holds up better against the weakest
    /// part of the backdrop.
    var usesLightText: Bool {
        let onWhite = backdrop.map { $0.contrast(with: .white) }.min() ?? 21
        let onInk = backdrop.map { $0.contrast(with: .ink) }.min() ?? 21
        return onWhite >= onInk
    }

    /// Whether the square color can carry the streak number and the status
    /// dot: WCAG's 3:1 for large text and graphics, against every part of the
    /// backdrop. When it can't, those fall back to the text color.
    var squaresStandOut: Bool {
        backdrop.allSatisfy { $0.contrast(with: squares) >= 3 }
    }

    var colorScheme: ColorScheme { usesLightText ? .dark : .light }

    /// Ice blue, unless the squares are already close to it, in which case a
    /// freeze would pass for a busy day. Then it takes the text color.
    private var freezeColor: Color {
        let ice = RGBAColor(hex: usesLightText ? 0x7DD3FC : 0x0284C7)
        let distance = sqrt(
            pow(ice.red - squares.red, 2) + pow(ice.green - squares.green, 2) + pow(ice.blue - squares.blue, 2)
        )
        return distance < 0.35 ? (usesLightText ? Color.white : RGBAColor.ink.color) : ice.color
    }

    /// Whether a picked empty-day color can still be told from the
    /// backdrop. The automatic one always can.
    var emptySquaresShow: Bool {
        guard let emptySquares else { return true }
        return backdrop.allSatisfy { $0.contrast(with: emptySquares) >= 1.15 }
    }

    /// Whether a picked missed-day color can be told from the backdrop.
    var missedSquaresShow: Bool {
        guard let missedSquares else { return true }
        return backdrop.allSatisfy { $0.contrast(with: missedSquares) >= 1.15 }
    }

    var theme: WidgetTheme {
        let ink = usesLightText ? Color.white : RGBAColor.ink.color
        let fill = squares.color
        let accent = squaresStandOut ? fill : ink
        return WidgetTheme(
            // Empty days are a veil of the text color unless one was picked,
            // so they read on any backdrop; active days step up through the
            // square color.
            levels: [emptySquares?.color ?? ink.opacity(usesLightText ? 0.14 : 0.09)]
                + [0.35, 0.55, 0.78, 1].map { fill.opacity($0) },
            primaryText: ink,
            secondaryText: ink.opacity(0.7),
            numberFill: AnyShapeStyle(accent),
            pushed: accent,
            pending: ink.opacity(0.7),
            cornerFraction: shape.cornerFraction,
            glows: glows,
            fontDesign: font.design,
            // The square color could be anything, orange included, so "not
            // yet" is a ring instead of a color that might match it.
            ringsPending: true,
            spacing: spacing.scale,
            hidesText: minimal,
            form: shape.form,
            fontWidth: font.width,
            numberWeight: weight.weight,
            freeze: freezeColor,
            missed: missedSquares?.color
        )
    }
}

// MARK: - Saved data

extension CustomWidgetStyle {
    private enum CodingKeys: String, CodingKey {
        case background, backgroundEnd, usesGradient, squares, shape, font, glows
        case emptySquares, missedSquares, spacing, minimal, weight
    }

    /// A field that's missing or unreadable (one added in a later version, or
    /// a shape this build doesn't know) takes the default, rather than
    /// failing the whole decode and quietly discarding someone's design.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? defaultValue
        }
        background = value(.background, fallback.background)
        backgroundEnd = value(.backgroundEnd, fallback.backgroundEnd)
        usesGradient = value(.usesGradient, fallback.usesGradient)
        squares = value(.squares, fallback.squares)
        shape = value(.shape, fallback.shape)
        font = value(.font, fallback.font)
        glows = value(.glows, fallback.glows)
        emptySquares = try? container.decodeIfPresent(RGBAColor.self, forKey: .emptySquares)
        missedSquares = try? container.decodeIfPresent(RGBAColor.self, forKey: .missedSquares)
        spacing = value(.spacing, fallback.spacing)
        minimal = value(.minimal, fallback.minimal)
        weight = value(.weight, fallback.weight)
    }
}

/// A color that survives JSON. Components are sRGB and can run past 0...1 for
/// wide-gamut picks, which UIColor's extended range carries through intact.
struct RGBAColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    /// Read and written by the editor's color pickers.
    var color: Color {
        get { Color(uiColor: UIColor(red: red, green: green, blue: blue, alpha: opacity)) }
        set { self = RGBAColor(newValue) }
    }

    /// WCAG relative luminance: 0 for black through 1 for white.
    var luminance: Double {
        func linear(_ component: Double) -> Double {
            let c = min(max(component, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, from 1 (identical) to 21 (black on white).
    func contrast(with other: RGBAColor) -> Double {
        let lighter = max(luminance, other.luminance)
        let darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let ink = RGBAColor(hex: 0x141414)
}

// MARK: - Environment

private struct CustomWidgetStyleKey: EnvironmentKey {
    static let defaultValue = CustomWidgetStyle.default
}

extension EnvironmentValues {
    /// Lets views deep inside the widget, like the grid, draw the custom
    /// style being shown without threading it through every initializer.
    var customWidgetStyle: CustomWidgetStyle {
        get { self[CustomWidgetStyleKey.self] }
        set { self[CustomWidgetStyleKey.self] = newValue }
    }
}
