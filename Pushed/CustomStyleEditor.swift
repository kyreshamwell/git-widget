import SwiftUI
import WidgetKit

/// Designs one saved style. Changes show in the preview immediately and are
/// saved as they're made; widgets wearing it repaint once the edits settle.
struct CustomStyleEditor: View {
    /// Real data when connected, sample data before setup.
    let snapshot: ContributionSnapshot?
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon

    @Environment(\.dismiss) private var dismiss
    @State private var saved: SavedStyle
    @State private var previewLayout: WidgetLayout = .graph
    /// Set once the style is deleted, so the pending save can't put it back.
    @State private var isDeleted = false
    @State private var confirmingDelete = false

    init(styleID: UUID, snapshot: ContributionSnapshot?, weeks: Int = AppConfig.widgetWeeks, icon: String = AppConfig.streakIcon) {
        self.snapshot = snapshot
        self.weeks = weeks
        self.icon = icon
        let library = AppConfig.styleLibrary
        _saved = State(initialValue: library[styleID] ?? library.styles[0])
    }

    var body: some View {
        Form {
            Section {
                Picker("Preview layout", selection: $previewLayout) {
                    ForEach(WidgetLayout.allCases) { layout in
                        Text(layout.name).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))

                FittedPreview(size: WidgetPreviewCard.size(for: .systemMedium)) {
                    WidgetPreviewCard(
                        snapshot: snapshot ?? .sample(),
                        family: .systemMedium,
                        style: .custom,
                        layout: previewLayout,
                        weeks: weeks,
                        icon: icon,
                        custom: saved.style
                    )
                }
                .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                TextField("Name", text: $saved.name)
                Toggle("Favorite", isOn: $saved.isFavorite)
            } footer: {
                Text("Favorites take turns in the Daily Rotation style, one a day.")
            }

            Section {
                ColorPicker("Background", selection: $saved.style.background.color, supportsOpacity: false)
                Toggle("Gradient", isOn: $saved.style.usesGradient.animation())
                if saved.style.usesGradient {
                    ColorPicker("Gradient end", selection: $saved.style.backgroundEnd.color, supportsOpacity: false)
                }
                ColorPicker("Squares", selection: $saved.style.squares.color, supportsOpacity: false)
            } header: {
                Text("Colors")
            } footer: {
                if !saved.style.squaresStandOut {
                    Text("These squares are hard to see on this background, so the streak number and status dot use the text color instead.")
                }
            }

            Section("Shape and type") {
                Picker("Shape", selection: $saved.style.shape) {
                    ForEach(CellShapeChoice.allCases) { shape in
                        Text(shape.name).tag(shape)
                    }
                }
                Picker("Font", selection: $saved.style.font) {
                    ForEach(FontChoice.allCases) { font in
                        Text(font.name).tag(font)
                    }
                }
                Toggle("Glow on busy days", isOn: $saved.style.glows)
            }

            Section {
                Button("Start over") { saved.style = .default }
                    .disabled(saved.style == .default)
                Button("Duplicate") { duplicate() }
                    .disabled(!AppConfig.styleLibrary.canAdd)
                Button("Delete Style", role: .destructive) { confirmingDelete = true }
                    .disabled(!AppConfig.styleLibrary.canRemove)
            } footer: {
                Text("To use it, long-press a Pushed widget, tap Edit Widget, choose Custom, then pick this style. Text and empty days adjust to your colors, so everything stays readable.")
            }
        }
        .navigationTitle(saved.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(saved.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Style", role: .destructive) { delete() }
        } message: {
            Text("Widgets wearing it switch to your first saved style.")
        }
        .task(id: saved) {
            guard !isDeleted else { return }
            var library = AppConfig.styleLibrary
            guard library[saved.id] != saved else { return }
            library[saved.id] = saved
            AppConfig.styleLibrary = library
            // A color picker reports every step of a drag. Repaint the
            // widgets once the choice settles, not on each step.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The copy is saved right away and becomes what's being edited.
    private func duplicate() {
        var library = AppConfig.styleLibrary
        guard let copy = library.duplicate(saved.id) else { return }
        AppConfig.styleLibrary = library
        saved = copy
    }

    private func delete() {
        var library = AppConfig.styleLibrary
        guard library.canRemove else { return }
        isDeleted = true
        library[saved.id] = nil
        AppConfig.styleLibrary = library
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

/// A thumbnail of a custom style for settings rows: its backdrop with a few
/// squares stepping up through its color.
struct CustomStyleSwatch: View {
    let style: CustomWidgetStyle

    var body: some View {
        HStack(spacing: 2) {
            ForEach([0.35, 0.7, 1], id: \.self) { opacity in
                CellShape(cornerFraction: style.shape.cornerFraction)
                    .fill(style.squares.color.opacity(opacity))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(5)
        .background {
            WidgetBackground(style: .custom, custom: style)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}
