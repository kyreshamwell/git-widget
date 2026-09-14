import XCTest

final class StreakIconTests: XCTestCase {
    // MARK: - What counts as an emoji

    func testEmojiOfEveryShapeTheKeyboardProducesCount() {
        // Plain, variation-selected, skin-toned, joined, flag and keycap.
        for emoji in ["🔥", "❤️", "☕️", "👍🏽", "👩‍💻", "🏳️‍🌈", "🇯🇵", "1️⃣", "#️⃣"] {
            XCTAssertEqual(emoji.count, 1, "\(emoji) should be a single character")
            XCTAssertTrue(Character(emoji).isEmoji, "\(emoji) should count as an emoji")
        }
    }

    func testCharactersThatOnlyCarryTheEmojiPropertyDoNot() {
        // Digits, # and * are keycap bases, and © has a text-style default.
        // None of them should turn up as a streak icon on their own.
        for text in ["a", "Z", "1", "#", "*", "©", "é", " ", "."] {
            XCTAssertFalse(Character(text).isEmoji, "\"\(text)\" is not an emoji")
        }
    }

    // MARK: - Picking

    func testTheNewestEmojiInTheInputWins() {
        XCTAssertEqual(StreakIcon.lastEmoji(in: "🔥⚡"), "⚡")
        XCTAssertEqual(StreakIcon.lastEmoji(in: "ship it 🚀 now"), "🚀")
        XCTAssertEqual(StreakIcon.lastEmoji(in: "👩‍💻"), "👩‍💻", "a joined emoji must not be split")
        XCTAssertNil(StreakIcon.lastEmoji(in: "streak"))
        XCTAssertNil(StreakIcon.lastEmoji(in: ""))
    }

    // MARK: - Stored values

    func testValuesFromTheOldFixedMenuStillLoad() {
        for old in ["🔥", "⚡", "🌱", "⭐", "none"] {
            XCTAssertEqual(StreakIcon.sanitized(old), old)
        }
    }

    func testAnythingThePickerCouldNotHaveWrittenFallsBack() {
        XCTAssertEqual(StreakIcon.sanitized(nil), "🔥")
        XCTAssertEqual(StreakIcon.sanitized(""), "🔥")
        XCTAssertEqual(StreakIcon.sanitized("fire"), "🔥")
        XCTAssertEqual(StreakIcon.sanitized("🐙"), "🐙")
    }

    func testEveryQuickPickIsOneValidEmoji() {
        XCTAssertEqual(Set(StreakIcon.suggestions).count, StreakIcon.suggestions.count, "no duplicates")
        for emoji in StreakIcon.suggestions {
            XCTAssertEqual(StreakIcon.sanitized(emoji), emoji)
        }
    }

    // MARK: - Footer label

    func testLabelMatchesWhatTheWidgetShowed() {
        XCTAssertEqual(StreakIcon.label(streak: 12, icon: "🔥", compact: false), "🔥 12")
        XCTAssertEqual(StreakIcon.label(streak: 12, icon: "🔥", compact: true), "🔥 12")
        XCTAssertEqual(StreakIcon.label(streak: 12, icon: "none", compact: false), "12-day streak")
        XCTAssertEqual(StreakIcon.label(streak: 1, icon: "none", compact: true), "1 day")
        XCTAssertEqual(StreakIcon.label(streak: 3, icon: "none", compact: true), "3 days")
    }
}
