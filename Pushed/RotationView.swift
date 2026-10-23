import SwiftUI
import WidgetKit

/// What the Daily Rotation style shows today and tomorrow, and which styles
/// take turns. Doubles as the list for tidying up saved styles: swipe left
/// to delete one, right to copy it.
struct RotationView: View {
    let snapshot: ContributionSnapshot?
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon

    @State private var library = AppConfig.styleLibrary
    @State private var editing: UUID?
    @State private var deleting: SavedStyle?

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
                Text(statusNote)
            }

            Section {
                ForEach(library.styles) { saved in
                    checkRow(saved.displayName, isOn: saved.inRotation) {
                        CustomStyleSwatch(style: saved.style)
                    } toggle: {
                        update { $0.toggleRotation(saved.id) }
                    }
                    .swipeActions(edge: .trailing) {
                        if library.canRemove {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = saved }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if library.canAdd {
                            Button("Copy", systemImage: "plus.square.on.square") {
                                update { $0.duplicate(saved.id) }
                            }
                            .tint(.indigo)
                        }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "paintbrush") { editing = saved.id }
                    }
                }

                Button {
                    var added: SavedStyle?
                    update { added = $0.add() }
                    editing = added?.id
                } label: {
                    Label("New Style", systemImage: "plus")
                }
                .disabled(!library.canAdd)
            } header: {
                Text("Your styles")
            } footer: {
                Text("Swipe left to delete a style, right to copy it. Hold one to edit it.")
            }

            Section {
                ForEach(WidgetStyle.builtIn) { style in
                    checkRow(style.name, isOn: library.isInRotation(style)) {
                        EmptyView()
                    } toggle: {
                        update { $0.toggleRotation(style) }
                    }
                }
            } header: {
                Text("Built in")
            } footer: {
                Text("To use it, long-press a Pushed widget, tap Edit Widget and choose Daily Rotation as the style.")
            }
        }
        .navigationTitle("Daily Rotation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { id in
            CustomStyleEditor(styleID: id, snapshot: snapshot, weeks: weeks, icon: icon)
        }
        .confirmationDialog(
            "Delete \(deleting?.displayName ?? "this style")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { saved in
            Button("Delete Style", role: .destructive) {
                update { $0[saved.id] = nil }
            }
        } message: { _ in
            Text("Widgets wearing it switch to your first saved style.")
        }
        // Back from the editor, or from the gallery, the list may have changed.
        .onAppear { library = AppConfig.styleLibrary }
        .onChange(of: editing) { _, id in
            if id == nil { library = AppConfig.styleLibrary }
        }
    }

    private var statusNote: String {
        if !library.hasCheckedStyles {
            return "Nothing is checked, so all of your styles take turns. Check the ones you want, one a day, changing at midnight."
        }
        if library.rotation.count == 1 {
            return "Only \(library.rotation[0].name) is checked, so it stays put. Check more to have them take turns."
        }
        return "\(library.rotation.count) styles take turns, one a day, changing at midnight."
    }

    /// A row with a check bubble: tapping anywhere on it checks or unchecks.
    private func checkRow(
        _ name: String,
        isOn: Bool,
        @ViewBuilder swatch: () -> some View,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                swatch()
                Text(name)
                    // Inside a button, .primary means the tint.
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? "In rotation" : "Not in rotation")
    }

    private func update(_ change: (inout StyleLibrary) -> Void) {
        var updated = AppConfig.styleLibrary
        change(&updated)
        AppConfig.styleLibrary = updated
        library = updated
        WidgetCenter.shared.reloadAllTimelines()
    }
}
