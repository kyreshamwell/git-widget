import Foundation

/// A custom style someone designed and kept, under the name they gave it.
struct SavedStyle: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// Favorites are the ones that take turns in the daily rotation.
    var isFavorite: Bool
    var createdAt: Date
    var style: CustomWidgetStyle

    init(
        id: UUID = UUID(),
        name: String,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        style: CustomWidgetStyle = .default
    ) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.style = style
    }

    /// A name that's been cleared still needs something to show.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

/// A style ready to draw: one of the built-ins, or a custom design, with the
/// name to show beside it.
struct WidgetLook: Equatable, Sendable {
    var style: WidgetStyle
    var custom: CustomWidgetStyle = .default
    var name: String

    init(_ style: WidgetStyle) {
        self.style = style
        self.name = style.name
    }

    init(_ saved: SavedStyle) {
        style = .custom
        custom = saved.style
        name = saved.displayName
    }
}

/// Every custom style someone has saved, in the order they're shown, and how
/// the daily rotation picks from them.
///
/// Kept in the shared container, so a widget draws exactly what the app
/// previewed. There's always at least one style in it: a widget set to Custom
/// needs something to show.
struct StyleLibrary: Codable, Equatable, Sendable {
    var styles: [SavedStyle]
    /// Whether the built-in styles take a turn in the daily rotation as well.
    var rotatesBuiltIns = false

    /// Enough to play with, short enough that Edit Widget's list stays usable.
    static let maxStyles = 24

    /// The style from before there was a library always gets this id, so the
    /// app and the widget agree on it without either having to write first.
    static let firstStyleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// What everyone starts with: the one custom style there used to be,
    /// carried over as it was.
    static func starting(with style: CustomWidgetStyle = .default) -> StyleLibrary {
        StyleLibrary(styles: [
            SavedStyle(id: firstStyleID, name: "My Style", createdAt: .distantPast, style: style),
        ])
    }
}

// MARK: - Editing

extension StyleLibrary {
    subscript(id: UUID) -> SavedStyle? {
        get { styles.first { $0.id == id } }
        set {
            guard let index = styles.firstIndex(where: { $0.id == id }) else { return }
            if let newValue {
                styles[index] = newValue
            } else if canRemove {
                styles.remove(at: index)
            }
        }
    }

    var canAdd: Bool { styles.count < Self.maxStyles }
    /// The last one stays, so Custom widgets always have a style.
    var canRemove: Bool { styles.count > 1 }

    /// Adds a style and hands it back, or nil when the library is full.
    /// With no design given, it starts from the next of the starter looks.
    @discardableResult
    mutating func add(_ style: CustomWidgetStyle? = nil, named name: String? = nil) -> SavedStyle? {
        guard canAdd else { return nil }
        let starters = CustomWidgetStyle.starters
        let saved = SavedStyle(
            name: unusedName(from: name ?? "Style \(styles.count + 1)"),
            style: style ?? starters[styles.count % starters.count]
        )
        styles.append(saved)
        return saved
    }

    /// A copy placed right after the original, named after it.
    @discardableResult
    mutating func duplicate(_ id: UUID) -> SavedStyle? {
        guard canAdd, let index = styles.firstIndex(where: { $0.id == id }) else { return nil }
        let original = styles[index]
        let copy = SavedStyle(name: unusedName(from: "\(original.displayName) copy"), style: original.style)
        styles.insert(copy, at: index + 1)
        return copy
    }

    /// `name`, or `name 2`, `name 3` and so on until it's one not taken.
    private func unusedName(from name: String) -> String {
        let taken = Set(styles.map(\.displayName))
        guard taken.contains(name) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }
}

// MARK: - What a widget shows

extension StyleLibrary {
    /// The styles that take turns: favorites, or every saved style when none
    /// is marked, followed by the built-ins if those are included.
    var rotation: [WidgetLook] {
        let favorites = styles.filter(\.isFavorite)
        let mine = (favorites.isEmpty ? styles : favorites).map(WidgetLook.init)
        return mine + (rotatesBuiltIns ? WidgetStyle.builtIn.map(WidgetLook.init) : [])
    }

    /// The rotation's style for `day`. It's worked out from the date alone,
    /// so the app and every widget land on the same one without comparing
    /// notes, and it moves on by one each midnight.
    func rotationPick(on day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> WidgetLook {
        let pool = rotation
        guard !pool.isEmpty else { return WidgetLook(.classic) }
        // Counted from a fixed day in the phone's own calendar, so the count
        // ticks over at local midnight.
        let start = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? .distantPast
        let dayNumber = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: day)).day ?? 0
        return pool[((dayNumber % pool.count) + pool.count) % pool.count]
    }

    /// What a widget set to `style` draws on `day`. `saved` is the custom
    /// style picked in Edit Widget; a widget from before there was a choice,
    /// or one whose style has since been deleted, gets the first.
    func look(
        for style: WidgetStyle,
        saved: UUID? = nil,
        on day: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WidgetLook {
        switch style {
        case .rotation:
            return rotationPick(on: day, calendar: calendar)
        case .custom:
            let chosen = saved.flatMap { self[$0] } ?? styles.first
            return chosen.map(WidgetLook.init) ?? WidgetLook(.classic)
        default:
            return WidgetLook(style)
        }
    }
}

// MARK: - Saved data

extension SavedStyle {
    private enum CodingKeys: String, CodingKey {
        case id, name, isFavorite, createdAt, style
    }

    /// Anything missing takes a default, so a style saved by another version
    /// of the app is never thrown away over one field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        isFavorite = (try? container.decodeIfPresent(Bool.self, forKey: .isFavorite)) ?? false
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        style = (try? container.decodeIfPresent(CustomWidgetStyle.self, forKey: .style)) ?? .default
    }
}

extension StyleLibrary {
    private enum CodingKeys: String, CodingKey {
        case styles, rotatesBuiltIns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        styles = (try? container.decodeIfPresent([SavedStyle].self, forKey: .styles)) ?? []
        rotatesBuiltIns = (try? container.decodeIfPresent(Bool.self, forKey: .rotatesBuiltIns)) ?? false
    }
}
