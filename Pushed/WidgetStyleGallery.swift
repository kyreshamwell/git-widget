import SwiftUI
import WidgetKit

/// Every style, drawn with the real widget view: the built-ins, then the ones
/// saved in the app. Styles are chosen per widget from Edit Widget, so this is
/// a catalog to browse, and the way in to designing your own.
struct WidgetStyleGallery: View {
    /// Real data when connected. Sample data otherwise, so the styles can be
    /// seen before setup.
    let snapshot: ContributionSnapshot?
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon

    @State private var layout: WidgetLayout = .graph
    @State private var family: WidgetFamily = .systemMedium
    @State private var library = AppConfig.styleLibrary
    @State private var editing: UUID?
    @State private var deleting: SavedStyle?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Layout", selection: $layout) {
                    ForEach(WidgetLayout.allCases) { layout in
                        Text(layout.name).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Size", selection: $family) {
                    Text("Small").tag(WidgetFamily.systemSmall)
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
                }
                .pickerStyle(.segmented)

                heading("Built in")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(WidgetStyle.builtIn) { style in
                        card(WidgetLook(style)) {
                            Text(style.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            RotationCheck(isOn: library.isInRotation(style)) {
                                update { $0.toggleRotation(style) }
                            }
                            .padding(.top, 4)
                        }
                        .contextMenu {
                            rotationButton(isOn: library.isInRotation(style)) {
                                update { $0.toggleRotation(style) }
                            }
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    heading("Your styles")
                    Spacer()
                    Button {
                        addStyle()
                    } label: {
                        Label("New Style", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(!library.canAdd)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(library.styles) { saved in
                        card(WidgetLook(saved)) {
                            HStack {
                                RotationCheck(isOn: saved.inRotation) {
                                    update { $0.toggleRotation(saved.id) }
                                }
                                Spacer()
                                Button {
                                    editing = saved.id
                                } label: {
                                    Label("Edit", systemImage: "paintbrush")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.top, 4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = saved.id }
                        // Hold a style for everything at once, delete included,
                        // without opening the editor first.
                        .contextMenu {
                            Button("Edit", systemImage: "paintbrush") { editing = saved.id }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                update { $0.duplicate(saved.id) }
                            }
                            .disabled(!library.canAdd)
                            rotationButton(isOn: saved.inRotation) {
                                update { $0.toggleRotation(saved.id) }
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = saved }
                                .disabled(!library.canRemove)
                        }
                    }
                }

                Text("Check the styles you want in the Daily Rotation and they take turns, one a day. Check just one and it stays put. Hold any of your styles to edit, copy or delete it.\n\nTo use one, long-press a Pushed widget on your home screen, tap Edit Widget, then choose a Style and Layout. Pick Custom to wear one of your styles, or Daily Rotation for your checked ones. Each widget keeps its own, so you can mix them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Widget Styles")
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
        // Coming back from the editor should show what was just designed.
        .onAppear { library = AppConfig.styleLibrary }
        .onChange(of: editing) { _, id in
            if id == nil { library = AppConfig.styleLibrary }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .padding(.top, 8)
    }

    private func card(_ look: WidgetLook, @ViewBuilder details: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FittedPreview(size: WidgetPreviewCard.size(for: family)) {
                WidgetPreviewCard(
                    snapshot: snapshot ?? .sample(),
                    family: family,
                    style: look.style,
                    layout: layout,
                    weeks: weeks,
                    icon: icon,
                    custom: look.custom
                )
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(look.name).font(.headline)
                details()
            }
        }
        // Fill the column, so a short tagline can't make its card narrower
        // and shift it off the grid.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addStyle() {
        var updated = AppConfig.styleLibrary
        guard let added = updated.add() else { return }
        AppConfig.styleLibrary = updated
        library = updated
        editing = added.id
    }

    /// Every change here goes through one place: saved, shown, and the
    /// widgets repainted.
    private func update(_ change: (inout StyleLibrary) -> Void) {
        var updated = AppConfig.styleLibrary
        change(&updated)
        AppConfig.styleLibrary = updated
        library = updated
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func rotationButton(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(
            isOn ? "Remove from Rotation" : "Add to Rotation",
            systemImage: isOn ? "minus.circle" : "checkmark.circle",
            action: action
        )
    }

    private var columns: [GridItem] {
        family == .systemSmall
            ? [GridItem(.flexible(), spacing: 16, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
            : [GridItem(.flexible())]
    }
}

/// The check bubble under a style: checked styles take turns in the Daily
/// Rotation.
struct RotationCheck: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("In rotation", systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Daily Rotation")
        .accessibilityValue(isOn ? "Checked" : "Not checked")
    }
}

/// Lays content out at a real widget size, then scales it to the width it's
/// given. The widget's own proportions, text wrapping included, stay exactly
/// as on the home screen whether the column is wider or narrower than that.
struct FittedPreview<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: size.width, height: size.height)
                .scaleEffect(geo.size.width / size.width, anchor: .topLeading)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
    }
}
