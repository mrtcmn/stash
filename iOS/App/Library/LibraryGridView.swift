import SwiftUI
import StashCore

/// Two-column masonry. Columns are lazy, so only visible cards load images.
struct LibraryGridView: View {
    let snips: [Snip]
    let onSelect: (Snip) -> Void
    let onDelete: (Snip) -> Void
    let onFavorite: (Snip) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private func columns(count: Int) -> [[Snip]] {
        var cols: [[Snip]] = Array(repeating: [], count: count)
        var heights: [CGFloat] = Array(repeating: 0, count: count)
        for s in snips {
            let i = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            cols[i].append(s)
            heights[i] += estimatedHeight(s)
        }
        return cols
    }

    private func estimatedHeight(_ s: Snip) -> CGFloat {
        let text: CGFloat = 70
        guard let r = s.primaryMedia?.aspectRatio, r > 0 else { return text + 40 }
        return text + 170 / min(max(CGFloat(r), 0.7), 1.8)
    }

    var body: some View {
        // One column at accessibility text sizes, where two would squeeze the text.
        let cols = columns(count: typeSize.isAccessibilitySize ? 1 : 2)
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                ForEach(cols.indices, id: \.self) { c in
                    LazyVStack(spacing: 12) {
                        ForEach(cols[c]) { snip in
                            Button { onSelect(snip) } label: { SnipTile(snip: snip) }
                                .buttonStyle(PressStyle())
                                .contextMenu { SnipActions(snip: snip, onDelete: onDelete, onFavorite: onFavorite) }
                                .accessibilityAction(named: snip.isFavorite ? "Unfavorite" : "Favorite") { onFavorite(snip) }
                                .accessibilityAction(named: "Delete") { onDelete(snip) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct SnipActions: View {
    let snip: Snip
    let onDelete: (Snip) -> Void
    let onFavorite: (Snip) -> Void

    var body: some View {
        if let s = snip.url, let url = URL(string: s) {
            Link(destination: url) { Label("Open Link", systemImage: "safari") }
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Button { onFavorite(snip) } label: {
            Label(snip.isFavorite ? "Unfavorite" : "Favorite", systemImage: snip.isFavorite ? "star.slash" : "star")
        }
        Button(role: .destructive) { onDelete(snip) } label: { Label("Delete", systemImage: "trash") }
    }
}
