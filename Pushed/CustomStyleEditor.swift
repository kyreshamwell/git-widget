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
    @State private var previewFamily: WidgetFamily = .systemMedium
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
                TextField("Name", text: $saved.name)
                Toggle("In Daily Rotation", isOn: $saved.inRotation)
            } footer: {
                Text("Checked styles take turns in the Daily Rotation style, one a day. Check just one and it stays put.")
            }

            Section {
                ColorPicker("Background", selection: $saved.style.background.color, supportsOpacity: false)
                Toggle("Gradient", isOn: $saved.style.usesGradient.animation())
                if saved.style.usesGradient {
                    ColorPicker("Gradient end", selection: $saved.style.backgroundEnd.color, supportsOpacity: false)
                }
                ColorPicker("Squares", selection: $saved.style.squares.color, supportsOpacity: false)
                Toggle("Pick empty day color", isOn: Binding(
                    get: { saved.style.emptySquares != nil },
                    set: { picking in
                        // A soft step off the backdrop to start from.
                        saved.style.emptySquares = picking
                            ? RGBAColor(hex: saved.style.usesLightText ? 0x3A3A4A : 0xE4E4E7)
                            : nil
                    }
                ).animation())
                if saved.style.emptySquares != nil {
                    ColorPicker("Empty days", selection: Binding(
                        get: { saved.style.emptySquares?.color ?? .gray },
                        set: { saved.style.emptySquares = RGBAColor($0) }
                    ), supportsOpacity: false)
                }
                Toggle("Mark missed days", isOn: Binding(
                    get: { saved.style.missedSquares != nil },
                    set: { marking in
                        // A muted red to start from, softer on dark backdrops.
                        saved.style.missedSquares = marking
                            ? RGBAColor(hex: saved.style.usesLightText ? 0xE5484D : 0xD93D42)
                            : nil
                    }
                ).animation())
                if saved.style.missedSquares != nil {
                    ColorPicker("Missed days", selection: Binding(
                        get: { saved.style.missedSquares?.color ?? .red },
                        set: { saved.style.missedSquares = RGBAColor($0) }
                    ), supportsOpacity: false)
                }
            } header: {
                Text("Colors")
            } footer: {
                Text(colorsNote)
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
                Picker("Number weight", selection: $saved.style.weight) {
                    ForEach(WeightChoice.allCases) { weight in
                        Text(weight.name).tag(weight)
                    }
                }
                Picker("Spacing", selection: $saved.style.spacing) {
                    ForEach(SpacingChoice.allCases) { spacing in
                        Text(spacing.name).tag(spacing)
                    }
                }
                Toggle("Glow on busy days", isOn: $saved.style.glows)
            }

            Section {
                Toggle("Minimal", isOn: $saved.style.minimal)
            } footer: {
                Text("Leaves just the number and the squares: no month or day labels, captions or status words.")
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
        // The preview stays put while the controls scroll under it, so every
        // change can be seen without scrolling back up.
        .pinnedToTop { preview }
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

    private var preview: some View {
        VStack(spacing: 10) {
            FittedPreview(size: WidgetPreviewCard.size(for: previewFamily)) {
                WidgetPreviewCard(
                    snapshot: snapshot ?? .sample(),
                    family: previewFamily,
                    style: .custom,
                    layout: previewLayout,
                    weeks: weeks,
                    icon: icon,
                    custom: saved.style
                )
            }
            // Fitted into a fixed height, so a small or large preview doesn't
            // push the controls off the screen.
            .frame(maxWidth: .infinity, maxHeight: 176)
            .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
            .animation(.snappy, value: previewFamily)

            HStack(spacing: 8) {
                Picker("Layout", selection: $previewLayout) {
                    ForEach(WidgetLayout.allCases) { layout in
                        Text(layout.name).tag(layout)
                    }
                }
                Picker("Size", selection: $previewFamily) {
                    Text("S").tag(WidgetFamily.systemSmall)
                    Text("M").tag(WidgetFamily.systemMedium)
                    Text("L").tag(WidgetFamily.systemLarge)
                }
                .frame(maxWidth: 120)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Warnings first, since they're the ones that need acting on.
    private var colorsNote: String {
        let style = saved.style
        var notes: [String] = []
        if !style.squaresStandOut {
            notes.append("These squares are hard to see on this background, so the streak number and status dot use the text color instead.")
        }
        if !style.emptySquaresShow {
            notes.append("Empty days are almost the same color as the background, so they'll be hard to see.")
        }
        if !style.missedSquaresShow {
            notes.append("Missed days are almost the same color as the background, so they'll be hard to see.")
        }
        if notes.isEmpty {
            if style.emptySquares == nil {
                notes.append("Empty days are worked out from your background so they always show.")
            }
            notes.append("A missed day is the day a streak of two or more ended, counted from when you connected Pushed. It gets an outline in this color. Rest days and freezes never count as missed.")
        }
        return notes.joined(separator: " ")
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
                CellShape(cornerFraction: style.shape.cornerFraction, form: style.shape.form)
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

extension View {
    /// Keeps `header` at the top while the content scrolls under it. The
    /// backdrop is frosted glass that fades out at its lower edge, so what
    /// slides underneath stays visible but blurred enough that the header
    /// stays easy to read, with no hard line where it ends.
    func pinnedToTop<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            header()
                .padding(.bottom, 6)
                .background {
                    // Full strength behind the whole header, then a fade that
                    // hangs just below it, so nothing reads through the controls.
                    let fade: CGFloat = 26
                    Rectangle()
                        .fill(.regularMaterial)
                        .mask {
                            GeometryReader { geo in
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: max(0, 1 - fade / max(geo.size.height, 1))),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            }
                        }
                        .padding(.bottom, -fade)
                        .ignoresSafeArea(edges: .top)
                }
        }
    }
}
