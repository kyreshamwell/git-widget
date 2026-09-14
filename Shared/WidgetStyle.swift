import SwiftUI
import UIKit
import WidgetKit

/// A complete look for the widget: palette, backdrop, cell shape and type.
/// Picked per widget from Edit Widget, so two widgets can wear different
/// styles side by side.
enum WidgetStyle: String, CaseIterable, Identifiable, Sendable {
    case classic, aurora, ember, terminal, paper
    /// Designed in the app. See `CustomWidgetStyle`.
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .terminal: "Terminal"
        case .paper: "Paper"
        case .custom: "Custom"
        }
    }

    var tagline: String {
        switch self {
        case .classic: "GitHub's own greens. Follows light and dark mode."
        case .aurora: "Frosted squares over a teal and violet glow."
        case .ember: "Busy days burn hotter. Keep the fire going."
        case .terminal: "Phosphor green on black, set in monospace."
        case .paper: "Ink dots on warm paper. Calm and bright."
        case .custom: "Your colors, shape and type."
        }
    }

    /// Styles with their own backdrop pin a scheme, so anything inside that
    /// still uses a system color resolves against that backdrop rather than
    /// the phone's light or dark setting.
    func pinnedColorScheme(custom: CustomWidgetStyle = .default) -> ColorScheme? {
        switch self {
        case .classic: nil
        case .paper: .light
        case .aurora, .ember, .terminal: .dark
        case .custom: custom.colorScheme
        }
    }
}

/// What the widget leads with.
enum WidgetLayout: String, CaseIterable, Identifiable, Sendable {
    /// The contribution graph, with the streak in a footer.
    case graph
    /// The streak number, big, with a smaller graph alongside.
    case streak

    var id: String { rawValue }

    var name: String {
        switch self {
        case .graph: "Graph"
        case .streak: "Big streak"
        }
    }
}

/// The resolved colors and shapes a style draws with.
struct WidgetTheme {
    /// Level 0 (no contributions) through 4.
    let levels: [Color]
    let primaryText: Color
    let secondaryText: Color
    let numberFill: AnyShapeStyle
    /// Status dot once you've pushed today, and while you haven't yet.
    let pushed: Color
    let pending: Color
    /// Corner radius as a fraction of the cell: 0 is a square, 0.5 a dot.
    let cornerFraction: CGFloat
    /// A soft halo around the busiest cells and the streak number.
    let glows: Bool
    let fontDesign: Font.Design
    var isMonochrome = false
    /// Draw "not pushed yet" as a hollow ring rather than a second color, for
    /// themes where no second color is guaranteed to stand apart.
    var ringsPending = false

    func color(for level: Int) -> Color {
        levels[min(max(level, 0), levels.count - 1)]
    }

    /// Tinted and clear home screens drop the backdrop and repaint every pixel
    /// in a single tint, keeping only its alpha, so hue can't tell the levels
    /// apart there. White at stepped opacity still can. Shape and type stay.
    var monochrome: WidgetTheme {
        WidgetTheme(
            levels: [0.18, 0.4, 0.62, 0.82, 1].map { Color.white.opacity($0) },
            primaryText: .primary,
            secondaryText: .secondary,
            numberFill: AnyShapeStyle(Color.primary),
            pushed: .primary,
            pending: .primary,
            cornerFraction: cornerFraction,
            glows: false,
            fontDesign: fontDesign,
            isMonochrome: true,
            ringsPending: true
        )
    }
}

extension WidgetStyle {
    func theme(
        for colorScheme: ColorScheme,
        renderingMode: WidgetRenderingMode = .fullColor,
        custom: CustomWidgetStyle = .default
    ) -> WidgetTheme {
        let full = fullColorTheme(for: colorScheme, custom: custom)
        return renderingMode == .fullColor ? full : full.monochrome
    }

    private func fullColorTheme(for colorScheme: ColorScheme, custom: CustomWidgetStyle) -> WidgetTheme {
        switch self {
        case .classic:
            WidgetTheme(
                levels: colorScheme == .dark ? Self.classicDark : Self.classicLight,
                primaryText: .primary,
                secondaryText: .secondary,
                numberFill: AnyShapeStyle(Color.primary),
                pushed: .green,
                pending: .orange,
                cornerFraction: 0.25,
                glows: false,
                fontDesign: .default
            )
        case .aurora:
            WidgetTheme(
                levels: [0.16, 0.38, 0.6, 0.82, 1].map { Color.white.opacity($0) },
                primaryText: .white,
                secondaryText: .white.opacity(0.75),
                numberFill: AnyShapeStyle(Color.white),
                pushed: Color(hex: 0x6EE7B7),
                pending: Color(hex: 0xFDBA74),
                cornerFraction: 0.3,
                glows: false,
                fontDesign: .rounded
            )
        case .ember:
            WidgetTheme(
                levels: [0x3A2A24, 0x7C2D12, 0xC2410C, 0xF97316, 0xFACC15].map { Color(hex: $0) },
                primaryText: Color(hex: 0xFFF7ED),
                secondaryText: Color(hex: 0xFDBA74, opacity: 0.8),
                numberFill: AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0xFDE68A), Color(hex: 0xF97316)],
                    startPoint: .top, endPoint: .bottom
                )),
                // Hot once you've pushed, cooled to ash while you haven't.
                pushed: Color(hex: 0xFACC15),
                pending: Color(hex: 0xA8A29E),
                cornerFraction: 0.25,
                glows: true,
                fontDesign: .default
            )
        case .terminal:
            WidgetTheme(
                levels: [0x14261A, 0x0F5C2A, 0x1A9A45, 0x39D765, 0x9CFFB0].map { Color(hex: $0) },
                primaryText: Color(hex: 0x8CFCA6),
                secondaryText: Color(hex: 0x4FA968),
                numberFill: AnyShapeStyle(Color(hex: 0x8CFCA6)),
                pushed: Color(hex: 0x8CFCA6),
                pending: Color(hex: 0xF5C542),
                cornerFraction: 0,
                glows: true,
                fontDesign: .monospaced
            )
        case .paper:
            WidgetTheme(
                levels: [0.08, 0.3, 0.52, 0.76, 1].map { Color(hex: 0x292524, opacity: $0) },
                primaryText: Color(hex: 0x1C1917),
                secondaryText: Color(hex: 0x78716C),
                numberFill: AnyShapeStyle(Color(hex: 0x1C1917)),
                pushed: Color(hex: 0x3F7D58),
                pending: Color(hex: 0xC2552D),
                cornerFraction: 0.5,
                glows: false,
                fontDesign: .serif
            )
        case .custom:
            custom.theme
        }
    }

    private static let classicLight: [Color] = [
        Color(red: 0.922, green: 0.930, blue: 0.941), // #ebedf0
        Color(red: 0.608, green: 0.914, blue: 0.659), // #9be9a8
        Color(red: 0.251, green: 0.769, blue: 0.388), // #40c463
        Color(red: 0.188, green: 0.631, blue: 0.306), // #30a14e
        Color(red: 0.129, green: 0.431, blue: 0.224), // #216e39
    ]

    // Level 0 is lifted from GitHub's #161b22: that shade is darker than the
    // iOS dark-mode widget background, so empty days vanished into the platter.
    private static let classicDark: [Color] = [
        Color(red: 0.184, green: 0.212, blue: 0.247), // #2f3640-ish, visible on dark platters
        Color(red: 0.055, green: 0.267, blue: 0.161), // #0e4429
        Color(red: 0.000, green: 0.427, blue: 0.196), // #006d32
        Color(red: 0.149, green: 0.651, blue: 0.255), // #26a641
        Color(red: 0.224, green: 0.827, blue: 0.325), // #39d353
    ]
}

/// A style's backdrop. In the widget itself Classic is left to the system's
/// own background; this view stands in for it inside the app.
struct WidgetBackground: View {
    let style: WidgetStyle
    var custom: CustomWidgetStyle = .default

    var body: some View {
        switch style {
        case .classic:
            Color(uiColor: .secondarySystemGroupedBackground)
        case .aurora:
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x1E1B4B), Color(hex: 0x4C1D95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                EllipticalGradient(
                    colors: [Color(hex: 0x14B8A6, opacity: 0.8), .clear],
                    center: .topLeading, endRadiusFraction: 0.9
                )
                EllipticalGradient(
                    colors: [Color(hex: 0xEC4899, opacity: 0.6), .clear],
                    center: .bottomTrailing, endRadiusFraction: 0.8
                )
            }
        case .ember:
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x1A0F0B), Color(hex: 0x2B120A)],
                    startPoint: .top, endPoint: .bottom
                )
                EllipticalGradient(
                    colors: [Color(hex: 0xC2410C, opacity: 0.4), .clear],
                    center: .bottom, endRadiusFraction: 0.75
                )
            }
        case .terminal:
            ZStack {
                EllipticalGradient(
                    colors: [Color(hex: 0x0C1A10), Color(hex: 0x030604)],
                    center: .center, endRadiusFraction: 0.75
                )
                Scanlines()
            }
        case .paper:
            LinearGradient(
                colors: [Color(hex: 0xF8F4EC), Color(hex: 0xEEE6D6)],
                startPoint: .top, endPoint: .bottom
            )
        case .custom:
            if custom.usesGradient {
                LinearGradient(
                    colors: [custom.background.color, custom.backgroundEnd.color],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                custom.background.color
            }
        }
    }
}

/// Faint horizontal lines, like an old CRT.
private struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 0, to: size.height, by: 3) {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.white.opacity(0.025))
                )
            }
        }
    }
}

extension View {
    /// A soft halo in `color`, or nothing at all when it's nil. Skipping the
    /// modifier outright keeps the hundreds of quiet cells cheap to draw.
    @ViewBuilder
    func glow(_ color: Color?, radius: CGFloat) -> some View {
        if let color {
            shadow(color: color.opacity(0.75), radius: radius)
        } else {
            self
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
