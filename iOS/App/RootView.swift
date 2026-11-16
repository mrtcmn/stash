import SwiftUI
import StashCore

struct RootView: View {
    @State private var model = LibraryModel()
    @State private var selected: Snip?
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var controlHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 18

    var body: some View {
        let items = model.filtered
        ZStack {
            AuroraBackground()
            if !model.loaded {
                ProgressView().tint(Theme.inkSecondary)
            } else if items.isEmpty {
                EmptyLibraryView(searching: !model.query.isEmpty)
            } else if model.mode == .globe {
                GlobeView(items: items, onSelect: { selected = $0 }, onSwitchToGrid: { model.mode = .grid })
                    .ignoresSafeArea()
            } else {
                LibraryGridView(snips: items, onSelect: { selected = $0 },
                                onDelete: model.delete, onFavorite: model.toggleFavorite)
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .sheet(item: $selected) { snip in
            SnipDetailSheet(snip: model.snips.first { $0.id == snip.id } ?? snip,
                            onDelete: model.delete, onFavorite: model.toggleFavorite)
                .presentationDetents([.medium, .large])
        }
        .task { await model.observe() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.mode)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkTertiary)
                    TextField("Search your stash", text: $model.query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(Theme.inkTertiary)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: controlHeight)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button {
                    searchFocused = false
                    model.mode = model.mode == .globe ? .grid : .globe
                } label: {
                    Image(systemName: model.mode == .globe ? "square.grid.2x2" : "globe")
                        .font(.system(size: iconSize, weight: .medium)).foregroundStyle(Theme.ink)
                        .frame(width: controlHeight, height: controlHeight)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(model.mode == .globe ? "Show grid" : "Show globe")
                .accessibilityHint("Changes how your stash is shown")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
