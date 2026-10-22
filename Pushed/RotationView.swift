import SwiftUI
import WidgetKit

/// What the Daily Rotation style shows today and tomorrow, and which styles
/// take turns.
struct RotationView: View {
    let snapshot: ContributionSnapshot?
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon

    @State private var library = AppConfig.styleLibrary

    private var today: WidgetLook { library.rotationPick(on: Date()) }

    private var tomorrow: WidgetLook {
        let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return library.rotationPick(on: next)
    }

    var body: some View {
        Form {
            Section {
                FittedPreview(size: WidgetPreviewCard.size(for: .systemMedium)) {
                    WidgetPreviewCard(
                        snapshot: snapshot ?? .sample(),
                        family: .systemMedium,
                        style: today.style,
                        layout: .graph,
                        weeks: weeks,
                        icon: icon,
                        custom: today.custom
                    )
                }
                .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                LabeledContent("Today", value: today.name)
                LabeledContent("Tomorrow", value: tomorrow.name)
            } footer: {
                if library.rotation.count < 2 {
                    Text("Only one style is taking turns, so every day looks the same. Mark another favorite or include the built-in styles.")
                }
            }

            Section {
                ForEach($library.styles) { $saved in
                    Toggle(isOn: $saved.isFavorite) {
                        HStack(spacing: 10) {
                            CustomStyleSwatch(style: saved.style)
                            Text(saved.displayName)
                        }
                    }
                }
            } header: {
                Text("Favorites")
            } footer: {
                Text("Favorites take turns, one a day, changing at midnight. With none marked, all of your styles do.")
            }

            Section {
                Toggle("Include built-in styles", isOn: $library.rotatesBuiltIns)
            } footer: {
                Text("To use it, long-press a Pushed widget, tap Edit Widget and choose Daily Rotation as the style.")
            }
        }
        .navigationTitle("Daily Rotation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { library = AppConfig.styleLibrary }
        .onChange(of: library) { _, updated in
            AppConfig.styleLibrary = updated
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
