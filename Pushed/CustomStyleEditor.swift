import SwiftUI
import WidgetKit

/// Designs the Custom style. Changes show in the preview immediately and are
/// saved as they're made; widgets set to Custom repaint once the edits settle.
struct CustomStyleEditor: View {
    /// Real data when connected, sample data before setup.
    let snapshot: ContributionSnapshot?
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon

    @State private var custom = AppConfig.customStyle
    @State private var previewLayout: WidgetLayout = .graph

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
                        custom: custom
                    )
                }
                .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ColorPicker("Background", selection: $custom.background.color, supportsOpacity: false)
                Toggle("Gradient", isOn: $custom.usesGradient.animation())
                if custom.usesGradient {
                    ColorPicker("Gradient end", selection: $custom.backgroundEnd.color, supportsOpacity: false)
                }
                ColorPicker("Squares", selection: $custom.squares.color, supportsOpacity: false)
            } header: {
                Text("Colors")
            } footer: {
                if !custom.squaresStandOut {
                    Text("These squares are hard to see on this background, so the streak number and status dot use the text color instead.")
                }
            }

            Section("Shape and type") {
                Picker("Shape", selection: $custom.shape) {
                    ForEach(CellShapeChoice.allCases) { shape in
                        Text(shape.name).tag(shape)
                    }
                }
                Picker("Font", selection: $custom.font) {
                    ForEach(FontChoice.allCases) { font in
                        Text(font.name).tag(font)
                    }
                }
                Toggle("Glow on busy days", isOn: $custom.glows)
            }

            Section {
                Button("Start over") { custom = .default }
                    .disabled(custom == .default)
            } footer: {
                Text("To use it, long-press a Pushed widget, tap Edit Widget and choose Custom. Text and empty days adjust to your colors, so everything stays readable.")
            }
        }
        .navigationTitle("Custom Style")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: custom) {
            guard custom != AppConfig.customStyle else { return }
            AppConfig.customStyle = custom
            // A color picker reports every step of a drag. Repaint the
            // widgets once the choice settles, not on each step.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

/// A thumbnail of the custom style for settings rows: its backdrop with a
/// few squares stepping up through its color.
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
