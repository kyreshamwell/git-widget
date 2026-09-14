import Foundation

/// The streak icon is any single emoji, or `none` for the bare number.
///
/// It's stored as the emoji itself under the key the old four-item menu used,
/// so an icon picked before the change carries straight over.
enum StreakIcon {
    static let none = "none"
    static let fallback = "🔥"

    /// One-tap picks above the keyboard field. Everything else is on the
    /// emoji keyboard, which already has search, skin tones and recents.
    static let suggestions = [
        "🔥", "⚡", "🌱", "⭐", "🚀", "💪",
        "🏆", "🎯", "💎", "✅", "🟩", "🧠",
        "☕", "💻", "🐙", "👾", "🌈", "🍀",
    ]

    /// The newest emoji in `text`. Pasted or typed input can carry more than
    /// one, and the last is the one the person was reaching for.
    static func lastEmoji(in text: String) -> String? {
        text.last(where: \.isEmoji).map(String.init)
    }

    /// The widget reads the stored value straight out of shared defaults, so
    /// anything the picker couldn't have written falls back to the default
    /// instead of rendering as stray text.
    static func sanitized(_ stored: String?) -> String {
        guard let stored else { return fallback }
        return stored == none ? none : lastEmoji(in: stored) ?? fallback
    }

    /// The streak text as the graph layout's footer shows it.
    static func label(streak: Int, icon: String, compact: Bool) -> String {
        if icon == none {
            return compact ? "\(streak) day\(streak == 1 ? "" : "s")" : "\(streak)-day streak"
        }
        return "\(icon) \(streak)"
    }
}

extension Character {
    /// True for anything the emoji keyboard inserts: pictographs, flags,
    /// keycaps, skin tones and joined sequences like 👩‍💻.
    ///
    /// Unicode gives plain digits, "#" and "*" the Emoji property as well
    /// (each can start a keycap), so a character only counts if it shows as
    /// emoji by default or explicitly asks to with the U+FE0F selector.
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.contains("\u{FE0F}"))
    }
}
