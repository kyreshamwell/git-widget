import SwiftUI
import WidgetKit

/// Every style, drawn with the real widget view. Styles are chosen per widget
/// from Edit Widget, so this is a catalog to browse rather than a setting.
struct WidgetStyleGallery: View {
    /// Real data when connected. Sample data otherwise, so the styles can be
    /// seen before setup.
    let snapshot: ContributionSnapshot?
    var weeks: Int = AppConfig.widgetWeeks
    var icon: String = AppConfig.streakIcon

    @State private var layout: WidgetLayout = .graph
    @State private var family: WidgetFamily = .systemMedium
    @State private var custom = AppConfig.customStyle

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

                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(WidgetStyle.allCases) { style in
                        VStack(alignment: .leading, spacing: 10) {
                            FittedPreview(size: WidgetPreviewCard.size(for: family)) {
                                WidgetPreviewCard(
                                    snapshot: snapshot ?? .sample(),
                                    family: family,
                                    style: style,
                                    layout: layout,
                                    weeks: weeks,
                                    icon: icon,
                                    custom: custom
                                )
                            }
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.name).font(.headline)
                                Text(style.tagline)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if style == .custom {
                                    NavigationLink {
                                        CustomStyleEditor(snapshot: snapshot, weeks: weeks, icon: icon)
                                    } label: {
                                        Label("Design your own", systemImage: "paintbrush")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                        // Fill the column, so a short tagline can't make its
                        // card narrower and shift it off the grid.
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)

                Text("To use one, long-press a Pushed widget on your home screen, tap Edit Widget, then choose a Style and Layout. Each widget keeps its own, so you can mix them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Widget Styles")
        .navigationBarTitleDisplayMode(.inline)
        // Coming back from the editor should show what was just designed.
        .onAppear { custom = AppConfig.customStyle }
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
