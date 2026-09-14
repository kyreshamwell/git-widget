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

    /// Intensity levels 0-4, oldest first, aligned so index 0 is a Sunday.
    let levels: [Int]
    /// Date of the final entry in `levels`; required for axis labels.
    var endDate: Date? = nil
    var showsLabels: Bool = false
    var style: WidgetStyle = .classic

    private var theme: WidgetTheme {
        style.theme(for: colorScheme, renderingMode: renderingMode, custom: custom)
    }

    private var weeks: [[Int]] {
        stride(from: 0, to: levels.count, by: 7).map { start in
            Array(levels[start..<min(start + 7, levels.count)])
        }
    }

    /// (column, "Jan") pairs — one label wherever a column starts a new month.
    private var monthLabels: [(col: Int, text: String)] {
        guard showsLabels, let endDate else { return [] }
        let cal = Calendar(identifier: .gregorian)
        guard let startDate = cal.date(byAdding: .day, value: -(levels.count - 1), to: endDate) else { return [] }

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        var labels: [(Int, String)] = []
        var previousMonth = cal.component(.month, from: startDate)
        let columns = (levels.count + 6) / 7
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
        let active = levels.filter { $0 > 0 }.count
        var text = "Contribution graph. \(active) of \(levels.count) days with contributions"
        if let endDate {
            text += ", through \(endDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return text + "."
    }

    var body: some View {
        GeometryReader { geo in
            let columns = weeks.count
            let labelFont: CGFloat = 9
            let topInset: CGFloat = showsLabels ? labelFont + 4 : 0
            let leftInset: CGFloat = showsLabels ? 24 : 0

            let availW = geo.size.width - leftInset
            let availH = geo.size.height - topInset

            // Gutter scales with density so dense views (52 weeks) don't lose
            // a third of their width to fixed 2pt gaps.
            let spacing = max(0.8, min(2.5, availW / CGFloat(max(columns, 1)) * 0.18))
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
                                    let level = weeks[col][row]
                                    CellShape(cornerFraction: theme.cornerFraction)
                                        .fill(theme.color(for: level))
                                        .frame(width: cellW, height: cellH)
                                        .glow(theme.glows && level >= 3 ? theme.color(for: level) : nil, radius: cellW * 0.5)
                                        // On a tinted home screen the active days
                                        // take the accent tint and empty ones stay
                                        // neutral, so the graph still reads.
                                        .widgetAccentable(level > 0)
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

/// One day's cell. The corner radius scales with the cell, so the same style
/// reads the same at a year's worth of tiny squares or a week of big ones.
struct CellShape: InsettableShape {
    var cornerFraction: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path(roundedRect: inset, cornerRadius: min(inset.width, inset.height) * cornerFraction)
    }

    func inset(by amount: CGFloat) -> CellShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
