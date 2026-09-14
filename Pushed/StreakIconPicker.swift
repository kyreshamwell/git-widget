import SwiftUI
import UIKit

/// Any emoji as the streak icon. The emoji keyboard does the browsing, since it
/// already has search, skin tones and recents, and a grid of quick picks
/// covers the usual choices in one tap.
struct StreakIconPicker: View {
    @Binding var icon: String
    let streak: Int

    @State private var isTyping = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    EmojiField(icon: $icon, isEditing: $isTyping)
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: isTyping ? 2 : 0)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(StreakIcon.label(streak: streak, icon: icon, compact: false))
                            .font(.headline)
                        Text(isTyping
                             ? "Pick any emoji. Use the keyboard's search to find one fast."
                             : "Tap the square to choose from every emoji on your keyboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Shown next to your streak on the widget.")
            }

            Section("Quick picks") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(StreakIcon.suggestions, id: \.self) { emoji in
                        Button {
                            icon = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(icon == emoji ? Color.accentColor.opacity(0.2) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(icon == emoji ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    icon = StreakIcon.none
                } label: {
                    HStack {
                        Text("Just the number")
                            .foregroundStyle(.primary)
                        Spacer()
                        if icon == StreakIcon.none {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Streak Icon")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isTyping {
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
                }
            }
        }
    }
}

/// SwiftUI can't ask for a particular keyboard, and an emoji picker that opens
/// the letter keyboard isn't much of one. UIKit lets a text field name its
/// preferred input mode, and the emoji keyboard is one of the active modes.
private struct EmojiField: UIViewRepresentable {
    @Binding var icon: String
    @Binding var isEditing: Bool

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 40)
        field.textAlignment = .center
        // The emoji is the whole field, so a blinking caret beside it is noise.
        field.tintColor = .clear
        field.attributedPlaceholder = NSAttributedString(
            string: "+",
            attributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .light),
                .foregroundColor: UIColor.tertiaryLabel,
            ]
        )
        field.accessibilityLabel = "Streak icon"
        field.accessibilityHint = "Opens the emoji keyboard."
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        let shown = icon == StreakIcon.none ? "" : icon
        if field.text != shown { field.text = shown }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiField

        init(_ parent: EmojiField) { self.parent = parent }

        /// Every edit is judged by what was inserted, not by where the caret
        /// sat, so the field only ever holds the one emoji just chosen.
        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                // Backspace removes the icon, the same as "Just the number".
                parent.icon = StreakIcon.none
            } else if let emoji = StreakIcon.lastEmoji(in: string) {
                parent.icon = emoji
            }
            // Letters typed from another keyboard change nothing.
            textField.text = parent.icon == StreakIcon.none ? "" : parent.icon
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isEditing = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isEditing = false
        }
    }
}

private final class EmojiTextField: UITextField {
    /// iOS reopens whichever keyboard was last used in a given context, which
    /// would otherwise win over the emoji keyboard requested below.
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
            ?? super.textInputMode
    }
}
