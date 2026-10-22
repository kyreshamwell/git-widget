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
                            HStack(spacing: 14) {
                                Button {
                                    editing = saved.id
                                } label: {
                                    Label("Edit", systemImage: "paintbrush")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Button {
                                    toggleFavorite(saved.id)
                                } label: {
                                    Label(
                                        saved.isFavorite ? "Favorite" : "Not a favorite",
                                        systemImage: saved.isFavorite ? "star.fill" : "star"
                                    )
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(saved.isFavorite ? Color.yellow : Color.secondary)
                                }
                            }
                            .padding(.top, 2)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = saved.id }
                    }
                }

                Text("To use one, long-press a Pushed widget on your home screen, tap Edit Widget, then choose a Style and Layout. Pick Custom to wear one of your styles, or Daily Rotation for a different favorite each day. Each widget keeps its own, so you can mix them.")
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

    private func toggleFavorite(_ id: UUID) {
        var updated = AppConfig.styleLibrary
        updated[id]?.isFavorite.toggle()
        AppConfig.styleLibrary = updated
        library = updated
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var columns: [GridItem] {
        family == .systemSmall
            ? [GridItem(.flexible(), spacing: 16, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
            : [GridItem(.flexible())]
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
