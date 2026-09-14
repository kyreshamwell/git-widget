import AppIntents
import WidgetKit

/// The choices behind Edit Widget. Every placed widget keeps its own, so a
/// Terminal small can sit next to an Aurora medium.
struct WidgetOptionsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget Options"
    static var description = IntentDescription("Choose how this widget looks.")

    @Parameter(title: "Style", default: .classic)
    var style: WidgetStyle

    @Parameter(title: "Layout", default: .graph)
    var layout: WidgetLayout
}

extension WidgetStyle: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [WidgetStyle: DisplayRepresentation] = [
        .classic: "Classic",
        .aurora: "Aurora",
        .ember: "Ember",
        .terminal: "Terminal",
        .paper: "Paper",
        .custom: "Custom",
    ]
}

extension WidgetLayout: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static var caseDisplayRepresentations: [WidgetLayout: DisplayRepresentation] = [
        .graph: "Graph",
        .streak: "Big streak",
    ]
}
