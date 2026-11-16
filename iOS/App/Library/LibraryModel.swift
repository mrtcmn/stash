import SwiftUI
import StashCore

enum LibraryMode: String, CaseIterable { case globe, grid }

@MainActor @Observable
final class LibraryModel {
    var snips: [Snip] = [] { didSet { recompute() } }
    var query = "" { didSet { scheduleFilter() } }
    var mode: LibraryMode = .globe
    var loaded = false
    /// Snips matching every word of the query, in library order. Stored, so reading it is free.
    private(set) var filtered: [Snip] = []

    @ObservationIgnored private var haystack: [UUID: (updatedAt: Date, text: String)] = [:]
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var attempted: Set<UUID> = []

    private func scheduleFilter() {
        filterTask?.cancel()
        if query.trimmingCharacters(in: .whitespaces).isEmpty { recompute(); return }
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            recompute()
        }
    }

    private func recompute() {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { filtered = snips; return }
        // Lowercase each snip once, and again only after it changes.
        var next: [UUID: (updatedAt: Date, text: String)] = [:]
        next.reserveCapacity(snips.count)
        for snip in snips {
            if let cached = haystack[snip.id], cached.updatedAt == snip.updatedAt {
                next[snip.id] = cached
            } else {
                next[snip.id] = (snip.updatedAt, (snip.searchableText + " " + (snip.url ?? "")).lowercased())
            }
        }
        haystack = next
        filtered = snips.filter { snip in
            guard let text = next[snip.id]?.text else { return false }
            return words.allSatisfy { text.contains($0) }
        }
    }

    func observe() async {
        for await list in SharedStore.shared.updates() {
            snips = list
            loaded = true
        }
    }

    /// Reloads after the app returns to the foreground, because Darwin notifications skip a suspended app.
    func refresh() async {
        SharedStore.shared.reload()
        await enrichBareLinks()
    }

    func delete(_ snip: Snip) {
        snips.removeAll { $0.id == snip.id }
        Task { try? await SharedStore.shared.delete(ids: [snip.id]) }
    }

    func toggleFavorite(_ snip: Snip) {
        guard let i = snips.firstIndex(where: { $0.id == snip.id }) else { return }
        snips[i].isFavorite.toggle()
        snips[i].updatedAt = Date()
        let favorite = snips[i].isFavorite
        Task {
            // Field-level change: it cannot bring back a snip deleted elsewhere or undo an enrichment.
            if let stored = try? await SharedStore.shared.update(id: snip.id, { $0.isFavorite = favorite; $0.updatedAt = Date() }) {
                replace(stored)
            }
        }
    }

    private func replace(_ snip: Snip) {
        if let i = snips.firstIndex(where: { $0.id == snip.id }) { snips[i] = snip }
    }

    /// Fills in links that the Share Extension could not enrich in time.
    private func enrichBareLinks() async {
        let bare = snips.filter {
            $0.kind == .link && $0.link?.imageURL == nil && $0.title.isEmpty && !attempted.contains($0.id)
        }.prefix(8)
        for snip in bare {
            attempted.insert(snip.id)
            guard let s = snip.url, let url = URL(string: s),
                  let enriched = await LightEnricher.enrich(snip, url: url) else { continue }
            if let stored = try? await SharedStore.shared.update(id: snip.id, { LightEnricher.apply(enriched, to: &$0, autoTitle: nil) }) {
                replace(stored)
            }
        }
    }
}
