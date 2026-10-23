import SwiftUI
import WidgetKit

/// Renders GitHub-style contribution squares: one column per week, Sunday at
/// the top, in the colors and cell shape of the given style (Classic is
/// github.com's own 5-step green). Optionally draws GitHub's axis labels:
/// Mon/Wed/Fri down the left, month abbreviations on top.
struct ContributionGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.customWidgetStyle) private var custom

    /// One per day, oldest first, aligned so index 0 is a Sunday.
    let days: [StreakDay]
    /// Date of the final entry in `days`; required for axis labels.
    var endDate: Date? = nil
    var showsLabels: Bool = false
    var style: WidgetStyle = .classic

    private var theme: WidgetTheme {
        style.theme(for: colorScheme, renderingMode: renderingMode, custom: custom)
    }

    private var weeks: [[StreakDay]] {
        stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
    }

    /// (column, "Jan") pairs — one label wherever a column starts a new month.
    private var monthLabels: [(col: Int, text: String)] {
        guard showsLabels, let endDate else { return [] }
        let cal = Calendar(identifier: .gregorian)
        guard let startDate = cal.date(byAdding: .day, value: -(days.count - 1), to: endDate) else { return [] }

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        var labels: [(Int, String)] = []
        var previousMonth = cal.component(.month, from: startDate)
        let columns = (days.count + 6) / 7
        for col in 1..<columns {
            guard let colDate = cal.date(byAdding: .day, value: col * 7, to: startDate) else { continue }
            let month = cal.component(.month, from: colDate)
            if month != previousMonth {
                labels.append((col, monthFormatter.string(from: colDate)))
                previousMonth = month
            }
        }
        return labels
    }

    /// Drops labels that would collide: each kept label needs ~28pt of
    /// breathing room, and none may hang past the grid's right edge. On dense
    /// views (a full year) this thins Jan…Dec down to every other month or so
    /// instead of letting them smush together.
    private static func spacedOut(
        _ labels: [(col: Int, text: String)],
        stepX: CGFloat,
        gridWidth: CGFloat
    ) -> [(col: Int, text: String)] {
        var kept: [(col: Int, text: String)] = []
        var lastX: CGFloat = -.infinity
        for label in labels {
            let x = CGFloat(label.col) * stepX
            guard x - lastX >= 28, x <= gridWidth - 20 else { continue }
            kept.append(label)
            lastX = x
        }
        return kept
    }

    /// Several hundred coloured rectangles are individually meaningless and
    /// unnavigable, so the grid is collapsed into one element that states what
    /// a sighted reader takes from the shape of it.
    private var accessibilityDescription: String {
        let active = days.filter(\.isActive).count
        let off = days.filter { $0.off != nil }.count
        var text = "Contribution graph. \(active) of \(days.count) days with contributions"
        if off > 0 {
            text += ", \(off) day\(off == 1 ? "" : "s") off"
        }
        if let endDate {
            text += ", through \(endDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return text + "."
    }

    var body: some View {
        // Minimal styles drop the labels along with every other word.
        let showsLabels = self.showsLabels && !theme.hidesText
        GeometryReader { geo in
            let columns = weeks.count
            let labelFont: CGFloat = 9
            let topInset: CGFloat = showsLabels ? labelFont + 4 : 0
            let leftInset: CGFloat = showsLabels ? 24 : 0

            let availW = geo.size.width - leftInset
            let availH = geo.size.height - topInset

            // Gutter scales with density so dense views (52 weeks) don't lose
            // a third of their width to fixed 2pt gaps.
            let spacing = max(0.8, min(2.5, availW / CGFloat(max(columns, 1)) * 0.18)) * theme.spacing
            let rawW = (availW - spacing * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1))
            let rawH = (availH - spacing * 6) / 7
            // True squares, like GitHub — sized by whichever dimension is tighter.
            let cellW = max(1, min(rawW, rawH))
            let cellH = cellW
            let stepX = cellW + spacing
            let gridWidth = CGFloat(columns) * cellW + CGFloat(max(columns - 1, 0)) * spacing
            let gridHeight = cellH * 7 + spacing * 6

            HStack(alignment: .bottom, spacing: 4) {
                if showsLabels {
                    // Mon / Wed / Fri, aligned to grid rows 1, 3, 5
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            Text([1: "Mon", 3: "Wed", 5: "Fri"][row] ?? "")
                                .font(.system(size: labelFont, design: theme.fontDesign))
                                .foregroundStyle(theme.secondaryText)
                                .frame(width: 20, height: cellH, alignment: .trailing)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .frame(height: gridHeight)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if showsLabels {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                            ForEach(Self.spacedOut(monthLabels, stepX: stepX, gridWidth: gridWidth), id: \.col) { label in
                                Text(label.text)
                                    .font(.system(size: labelFont, design: theme.fontDesign))
                                    .foregroundStyle(theme.secondaryText)
                                    .fixedSize()
                                    .offset(x: CGFloat(label.col) * stepX)
                            }
                        }
                        .frame(width: gridWidth, height: labelFont, alignment: .topLeading)
                    }

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            VStack(spacing: spacing) {
                                ForEach(0..<weeks[col].count, id: \.self) { row in
                                    let day = weeks[col][row]
                                    DayCell(day: day, theme: theme, glowRadius: cellW * 0.5)
                                        .frame(width: cellW, height: cellH)
                                        // On a tinted home screen the active days
                                        // take the accent tint and empty ones stay
                                        // neutral, so the graph still reads.
                                        .widgetAccentable(day.isActive)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // center in available space
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}

/// One day's square, drawn the way its theme draws that kind of day: filled
/// by how busy it was, hollow where the theme outlines empty days, and marked
/// for a rest day or a freeze in whichever way days off are set to look.
struct DayCell: View {
    @Environment(\.dayOffMark) private var mark
    let day: StreakDay
    let theme: WidgetTheme
    /// Halo size for the busiest days, in themes that glow. Zero for none.
    var glowRadius: CGFloat = 0

    var body: some View {
        if let off = day.off {
            dayOff(off == .freeze ? theme.freeze : theme.dayOff)
        } else if day.endedStreak, let missed = theme.missed {
            // Outlined rather than filled, so a red miss can't be mistaken for
            // a busy day in a warm palette.
            emptyCell.overlay {
                CellOutline(theme, thickness: 0.17).fill(missed, style: FillStyle(eoFill: true))
            }
        } else if day.level == 0 && theme.outlinesEmpty {
            emptyCell
        } else {
            CellShape(theme)
                .fill(theme.color(for: day.level))
                .glow(
                    theme.glows && day.level >= 3 && glowRadius > 0 ? theme.color(for: day.level) : nil,
                    radius: glowRadius
                )
        }
    }

    @ViewBuilder
    private var emptyCell: some View {
        if theme.outlinesEmpty {
            CellOutline(theme)
                .fill(theme.color(for: 0), style: FillStyle(eoFill: true))
        } else {
            CellShape(theme).fill(theme.color(for: 0))
        }
    }

    @ViewBuilder
    private func dayOff(_ color: Color) -> some View {
        switch mark {
        case .ring:
            CellOutline(theme, dotted: true)
                .fill(color, style: FillStyle(eoFill: true))
        case .dot:
            // An ordinary empty day with a dot in it: the quietest of the three.
            emptyCell.overlay {
                CenterDot(fraction: 0.44).fill(color)
            }
        case .stripes:
            CellShape(theme)
                .fill(color.opacity(0.22))
                .overlay {
                    Stripes().fill(color).clipShape(CellShape(theme))
                }
        }
    }
}

/// How a rest day or a freeze is marked on the graph. Set once in the app and
/// used by every widget.
enum DayOffMark: String, CaseIterable, Codable, Identifiable, Sendable {
    /// The cell's outline with a dot in the middle.
    case ring
    /// An empty day with a dot in it.
    case dot
    /// Diagonal stripes, like a paused bar.
    case stripes

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ring: "Ring"
        case .dot: "Dot"
        case .stripes: "Stripes"
        }
    }
}

private struct DayOffMarkKey: EnvironmentKey {
    static let defaultValue = DayOffMark.stripes
}

extension EnvironmentValues {
    var dayOffMark: DayOffMark {
        get { self[DayOffMarkKey.self] }
        set { self[DayOffMarkKey.self] = newValue }
    }
}

/// The outline a day is drawn in. Most styles are a square with its corners
/// rounded by some amount; custom styles can pick one of the others.
enum CellForm: String, Sendable {
    case box, diamond, hexagon, heart, star
}

/// A cell's outline, optionally with a dot in the middle. Everything is sized
/// from the cell itself, so the mark holds its proportions from a year of
/// tiny squares to a week of big ones. Fill it with the even-odd rule: the
/// inner edge cuts the hole, and the dot fills back in.
struct CellOutline: Shape {
    var cornerFraction: CGFloat
    var form: CellForm = .box
    var dotted = false
    /// Line width as a share of the cell.
    var thickness: CGFloat = 0.11

    init(cornerFraction: CGFloat, form: CellForm = .box, dotted: Bool = false, thickness: CGFloat = 0.11) {
        self.cornerFraction = cornerFraction
        self.form = form
        self.dotted = dotted
        self.thickness = thickness
    }

    init(_ theme: WidgetTheme, dotted: Bool = false, thickness: CGFloat = 0.11) {
        self.init(cornerFraction: theme.cornerFraction, form: theme.form, dotted: dotted, thickness: thickness)
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let line = max(side * thickness, 0.6)

        var path = CellShape.path(form, cornerFraction: cornerFraction, in: rect)
        path.addPath(CellShape.path(form, cornerFraction: cornerFraction, in: rect.insetBy(dx: line, dy: line)))
        if dotted {
            path.addPath(CenterDot(fraction: 0.28).path(in: rect))
        }
        return path
    }
}

/// A round dot in the middle of the cell, sized as a share of it.
struct CenterDot: Shape {
    var fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let dot = min(rect.width, rect.height) * fraction
        return Path(ellipseIn: CGRect(x: rect.midX - dot / 2, y: rect.midY - dot / 2, width: dot, height: dot))
    }
}

/// Diagonal bands across the cell, spaced in proportion to it.
struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let band = side * 0.15
        let step = side * 0.36
        var path = Path()
        var offset = -rect.height
        while offset < rect.width {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset + band, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset + band + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
            path.closeSubpath()
            offset += step
        }
        return path
    }
}

/// One day's cell. The corner radius scales with the cell, so the same style
/// reads the same at a year's worth of tiny squares or a week of big ones.
struct CellShape: InsettableShape {
    var cornerFraction: CGFloat
    var form: CellForm = .box
    var insetAmount: CGFloat = 0

    init(cornerFraction: CGFloat, form: CellForm = .box) {
        self.cornerFraction = cornerFraction
        self.form = form
    }

    init(_ theme: WidgetTheme) {
        self.init(cornerFraction: theme.cornerFraction, form: theme.form)
    }

    func path(in rect: CGRect) -> Path {
        Self.path(form, cornerFraction: cornerFraction, in: rect.insetBy(dx: insetAmount, dy: insetAmount))
    }

    func inset(by amount: CGFloat) -> CellShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    static func path(_ form: CellForm, cornerFraction: CGFloat, in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
        }
        func polygon(_ points: [CGPoint]) -> Path {
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            return path
        }

        switch form {
        case .box:
            return Path(roundedRect: rect, cornerRadius: side * cornerFraction)
        case .diamond:
            return polygon([point(0.5, 0), point(1, 0.5), point(0.5, 1), point(0, 0.5)])
        case .hexagon:
            return polygon([
                point(0.5, 0), point(0.95, 0.25), point(0.95, 0.75),
                point(0.5, 1), point(0.05, 0.75), point(0.05, 0.25),
            ])
        case .heart:
            var path = Path()
            path.move(to: point(0.5, 0.95))
            path.addCurve(to: point(0, 0.36), control1: point(0.14, 0.74), control2: point(0, 0.56))
            path.addCurve(to: point(0.5, 0.2), control1: point(0, 0.06), control2: point(0.4, 0.0))
            path.addCurve(to: point(1, 0.36), control1: point(0.6, 0.0), control2: point(1, 0.06))
            path.addCurve(to: point(0.5, 0.95), control1: point(1, 0.56), control2: point(0.86, 0.74))
            path.closeSubpath()
            return path
        case .star:
            // Chunky points, so it still reads as a star at a few points across.
            let points = (0..<10).map { index -> CGPoint in
                let angle = (Double(index) * 36 - 90) * .pi / 180
                let radius = index.isMultiple(of: 2) ? 0.5 : 0.24
                return point(0.5 + radius * cos(angle), 0.54 + radius * sin(angle))
            }
            return polygon(points)
        }
    }
}
