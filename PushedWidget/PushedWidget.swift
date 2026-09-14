import SwiftUI
import WidgetKit

struct PushedWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetContentMargins) var margins
    let entry: StreakEntry

    var body: some View {
        StreakWidgetView(
            snapshot: entry.snapshot,
            family: family,
            style: entry.style,
            layout: entry.layout,
            custom: entry.custom,
            margins: margins
        )
    }
}

struct PushedWidget: Widget {
    let kind = "PushedWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetOptionsIntent.self, provider: Provider()) { entry in
            PushedWidgetEntryView(entry: entry)
                .modifier(StyleContainerBackground(style: entry.style, custom: entry.custom))
        }
        .configurationDisplayName("Contribution Graph")
        .description("Your GitHub contribution graph and commit streak, in five styles or one you design.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // StreakWidgetView applies the standard margins itself, trimmed for
        // the graph layout so the squares can run closer to the edges.
        .contentMarginsDisabled()
    }
}

/// Classic keeps the system's own widget background, which follows light and
/// dark mode. Every other style paints its own backdrop.
private struct StyleContainerBackground: ViewModifier {
    let style: WidgetStyle
    let custom: CustomWidgetStyle

    func body(content: Content) -> some View {
        if style == .classic {
            content.containerBackground(.background, for: .widget)
        } else {
            content.containerBackground(for: .widget) { WidgetBackground(style: style, custom: custom) }
        }
    }
}

@main
struct PushedWidgetBundle: WidgetBundle {
    var body: some Widget {
        PushedWidget()
    }
}

// One preview per style, so each look can be tuned in Xcode's canvas without
// touching the home screen.
#Preview("Classic", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .classic, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .classic, layout: .streak)
}

#Preview("Aurora", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .aurora, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .aurora, layout: .streak)
}

#Preview("Ember", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .ember, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .ember, layout: .streak)
}

#Preview("Terminal", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .terminal, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .terminal, layout: .streak)
}

#Preview("Paper", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .paper, layout: .graph)
    StreakEntry(date: .now, snapshot: .sample(), style: .paper, layout: .streak)
}

#Preview("Custom", as: .systemMedium) {
    PushedWidget()
} timeline: {
    StreakEntry(date: .now, snapshot: .sample(), style: .custom, layout: .graph, custom: .default)
    StreakEntry(date: .now, snapshot: .sample(), style: .custom, layout: .streak, custom: .default)
}
