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

    /// The saved-style picker only shows while Style is set to Custom.
    static var parameterSummary: some ParameterSummary {
        When(\.$style, .equalTo, .custom) {
            Summary {
                \.$style
                \.$saved
                \.$layout
            }
        } otherwise: {
            Summary {
                \.$style
                \.$layout
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
