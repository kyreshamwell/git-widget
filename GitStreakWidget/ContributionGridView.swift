import SwiftUI

struct ContributionGridView: View {
    let counts: [Int]
    let columns: Int

    private var maxCount: Int { max(counts.max() ?? 1, 1) }

    private var rows: [[Int]] {
        let padded = Array(repeating: 0, count: max(0, columns * 7 - counts.count)) + counts
        var result: [[Int]] = []
        for col in 0..<columns {
            let start = col * 7
            let end = min(start + 7, padded.count)
            result.append(start < end ? Array(padded[start..<end]) : [])
        }
        return result
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<rows.count, id: \.self) { col in
                VStack(spacing: 2) {
                    ForEach(0..<rows[col].count, id: \.self) { row in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(color(for: rows[col][row]))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
    }

    private func color(for count: Int) -> Color {
        if count == 0 { return Color.gray.opacity(0.15) }
        let intensity = min(Double(count) / Double(maxCount), 1.0)
        return Color.green.opacity(0.35 + intensity * 0.65)
    }
}
