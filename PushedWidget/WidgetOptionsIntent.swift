import AppIntents
import WidgetKit

/// The choices behind Edit Widget. Every placed widget keeps its own, so a
/// Terminal small can sit next to an Aurora medium.
struct WidgetOptionsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget Options"
    static var description = IntentDescription("Choose how this widget looks.")

    @Parameter(title: "Style", default: .classic)
    var style: WidgetStyle

    /// Which saved style a Custom widget wears. Left empty, it's the first
    /// one, which is also what a widget from before there was a choice gets.
    @Parameter(title: "Custom Style")
    var saved: SavedStyleEntity?

    @Parameter(title: "Layout", default: .graph)
    var layout: WidgetLayout

    /// Left at "Same as app", a widget follows the time range set in the
    /// app, which is what every widget did before this was a choice.
    @Parameter(title: "Range", default: .app)
    var range: WidgetRange

    @Parameter(title: "Show", default: .streak)
    var stat: WidgetStat

    /// The saved-style picker only shows while Style is set to Custom, and
    /// Range only for the layouts with a graph in them.
    static var parameterSummary: some ParameterSummary {
        When(\.$style, .equalTo, .custom) {
            When(\.$layout, .equalTo, .week) {
                Summary {
                    \.$style
                    \.$saved
                    \.$layout
                    \.$stat
                }
            } otherwise: {
                Summary {
                    \.$style
                    \.$saved
                    \.$layout
                    \.$range
                    \.$stat
                }
            }
        } otherwise: {
            When(\.$layout, .equalTo, .week) {
                Summary {
                    \.$style
                    \.$layout
                    \.$stat
                }
            } otherwise: {
                Summary {
                    \.$style
                    \.$layout
                    \.$range
                    \.$stat
                }
            }
        }
    }
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
        .rotation: "Daily Rotation",
    ]
}

extension WidgetLayout: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static var caseDisplayRepresentations: [WidgetLayout: DisplayRepresentation] = [
        .graph: "Graph",
        .streak: "Big streak",
        .week: "This week",
    ]
}

extension WidgetRange: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Range"
    static var caseDisplayRepresentations: [WidgetRange: DisplayRepresentation] = [
        .app: "Same as app",
        .month: "1 month",
        .threeMonths: "3 months",
        .sixMonths: "6 months",
        .year: "1 year",
    ]
}

extension WidgetStat: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static var caseDisplayRepresentations: [WidgetStat: DisplayRepresentation] = [
        .streak: "Current streak",
        .best: "Best streak",
        .week: "Days this week",
        .year: "Contributions this year",
    ]
}

/// One of the styles saved in the app, as Edit Widget lists it.
struct SavedStyleEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Custom Style"
    static var defaultQuery = SavedStyleQuery()

    /// The saved style's UUID, as text.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ saved: SavedStyle) {
        id = saved.id.uuidString
        name = saved.displayName
    }
}

/// Reads the list straight from the shared library each time, so a style
/// renamed or added in the app shows up the next time Edit Widget opens.
struct SavedStyleQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SavedStyleEntity] {
        AppConfig.styleLibrary.styles
            .filter { identifiers.contains($0.id.uuidString) }
            .map(SavedStyleEntity.init)
    }

    func suggestedEntities() async throws -> [SavedStyleEntity] {
        AppConfig.styleLibrary.styles.map(SavedStyleEntity.init)
    }

    func defaultResult() async -> SavedStyleEntity? {
        AppConfig.styleLibrary.styles.first.map(SavedStyleEntity.init)
    }
}
