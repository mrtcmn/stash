import SwiftUI
import StashCore

/// Grid card: media-first with a text fallback. Glass-like surface, no real glass on cards.
struct SnipTile: View {
    let snip: Snip
    @Environment(\.colorSchemeContrast) private var contrast

    private var aspect: CGFloat {
        guard let m = snip.primaryMedia?.aspectRatio, m > 0 else { return 4.0 / 3.0 }
        return min(max(CGFloat(m), 0.7), 1.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let media = snip.primaryMedia {
                Color.clear
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay { AsyncThumbnail(media: media) }
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: Theme.symbol(for: snip.kind))
                        .font(Theme.font(11, .medium))
                        .foregroundStyle(Theme.tint(for: snip.kind))
                        .accessibilityHidden(true)
                    Text(snip.domain ?? snip.kind.label)
                        .font(Theme.font(11)).foregroundStyle(Theme.inkTertiary).lineLimit(1)
                    Spacer(minLength: 0)
                    if snip.isFavorite {
                        Image(systemName: "star.fill").font(Theme.font(11)).foregroundStyle(Theme.favorite).accessibilityHidden(true)
                    }
                }
                Text(snip.displayTitle)
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(snip.primaryMedia == nil ? 5 : 2)
                    .multilineTextAlignment(.leading)
                if snip.primaryMedia == nil, !snip.body.isEmpty {
                    Text(snip.body).font(Theme.font(13)).foregroundStyle(Theme.inkSecondary).lineLimit(3)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(contrast == .increased ? 0.6 : 0.28), .white.opacity(contrast == .increased ? 0.3 : 0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snip.kind.label), \(snip.displayTitle)\(snip.isFavorite ? ", Favorite" : "")")
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
    }
}
