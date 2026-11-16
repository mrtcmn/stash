import SwiftUI
import StashCore

struct SnipDetailSheet: View {
    let snip: Snip
    let onDelete: (Snip) -> Void
    let onFavorite: (Snip) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let media = snip.primaryMedia {
                        Color.clear
                            .aspectRatio(min(max(CGFloat(media.aspectRatio ?? 1.5), 0.7), 1.8), contentMode: .fit)
                            .overlay { AsyncThumbnail(media: media, maxPixel: 1200) }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                            .accessibilityElement()
                            .accessibilityLabel("Image for \(snip.displayTitle)")
                            .accessibilityAddTraits(.isImage)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: Theme.symbol(for: snip.kind)).foregroundStyle(Theme.tint(for: snip.kind)).accessibilityHidden(true)
                        Text(snip.domain ?? snip.kind.label).foregroundStyle(Theme.inkTertiary)
                    }
                    .font(Theme.font(13, .medium))
                    Text(snip.displayTitle).headline(24).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    if let summary = snip.link?.summary ?? (snip.body.isEmpty ? nil : snip.body) {
                        Text(summary).font(Theme.font(16)).foregroundStyle(Theme.inkSecondary)
                    }
                    if let s = snip.url, let url = URL(string: s) {
                        Button { openURL(url) } label: {
                            Label("Open Link", systemImage: "safari").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                    Text("Saved \(snip.savedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkTertiary)
                }
                .padding(20)
            }
            .background(AuroraBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { onFavorite(snip) } label: {
                        Image(systemName: snip.isFavorite ? "star.fill" : "star")
                    }
                    .accessibilityLabel(snip.isFavorite ? "Unfavorite" : "Favorite")
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this snip?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete(snip); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
        // Dark-only on purpose: see Theme.
        .preferredColorScheme(.dark)
    }
}
