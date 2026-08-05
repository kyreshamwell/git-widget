import SwiftUI

/// Renders GitHub-style contribution squares: one column per week, Sunday at
/// the top, using the same 5-step green palette as github.com. Optionally draws
/// GitHub's axis labels — Mon/Wed/Fri down the left, month abbreviations on top.
struct ContributionGridView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Intensity levels 0-4, oldest first, aligned so index 0 is a Sunday.
    let levels: [Int]
    /// Date of the final entry in `levels`; required for axis labels.
    var endDate: Date? = nil
    var showsLabels: Bool = false

    private static let lightPalette: [Color] = [
        Color(red: 0.922, green: 0.930, blue: 0.941), // #ebedf0
        Color(red: 0.608, green: 0.914, blue: 0.659), // #9be9a8
        Color(red: 0.251, green: 0.769, blue: 0.388), // #40c463
        Color(red: 0.188, green: 0.631, blue: 0.306), // #30a14e
        Color(red: 0.129, green: 0.431, blue: 0.224), // #216e39
    ]

    // Level 0 is lifted from GitHub's #161b22: that shade is darker than the
    // iOS dark-mode widget background, so empty days vanished into the platter.
    private static let darkPalette: [Color] = [
        Color(red: 0.184, green: 0.212, blue: 0.247), // #2f3640-ish, visible on dark platters
        Color(red: 0.055, green: 0.267, blue: 0.161), // #0e4429
        Color(red: 0.000, green: 0.427, blue: 0.196), // #006d32
        Color(red: 0.149, green: 0.651, blue: 0.255), // #26a641
        Color(red: 0.224, green: 0.827, blue: 0.325), // #39d353
    ]

    private var palette: [Color] {
        colorScheme == .dark ? Self.darkPalette : Self.lightPalette
    }

    static func color(for level: Int, dark: Bool) -> Color {
        let palette = dark ? darkPalette : lightPalette
        return palette[min(max(level, 0), 4)]
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
                                .font(.system(size: labelFont))
                                .foregroundStyle(.secondary)
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
                                    .font(.system(size: labelFont))
                                    .foregroundStyle(.secondary)
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
                                    RoundedRectangle(cornerRadius: min(cellW, cellH) * 0.25)
                                        .fill(palette[min(max(weeks[col][row], 0), 4)])
                                        .frame(width: cellW, height: cellH)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // center in available space
        }
    }
}
