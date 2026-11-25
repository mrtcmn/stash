import StashCore
import SwiftUI

/// The library's left column: fixed scopes, kinds, the user's smart categories and tags.
/// It collapses with ⌃⌘S or the button in the top bar.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var newCategory = ""
    @State private var addingCategory = false
    @FocusState private var categoryFieldFocused: Bool

    static let width: CGFloat = 220

    var body: some View {
        // Each count walks the whole library: compute them once per render.
        let kindCounts = Dictionary(grouping: model.library.snips, by: \.kind).mapValues(\.count)
        let tagCounts = model.library.tagCounts
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(nil) {
                    row(.all, count: model.library.snips.count)
                    row(.favorites)
                    row(.bookmarks)
                }
                section(String(localized: "Types", comment: "Sidebar section: snip kinds")) {
                    ForEach([SnipKind.tweet, .link, .screenshot, .image, .note, .text], id: \.self) { kind in
                        row(.kind(kind), count: kindCounts[kind] ?? 0)
                    }
                }
                categories
                if !tagCounts.isEmpty {
                    section(String(localized: "Tags", comment: "Sidebar section")) {
                        ForEach(tagCounts.prefix(60)) { entry in
                            row(.tag(entry.tag), count: entry.count)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 48) // window buttons sit above the first row
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .frame(width: Self.width)
        .glassEffect(.regular.tint(Theme.panel.opacity(0.35)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Categories

    private var categories: some View {
        section(String(localized: "Categories", comment: "Sidebar section: smart categories the user names")) {
            ForEach(model.settings.categories, id: \.self) { name in
                row(.category(name))
                    .contextMenu {
                        Button("Delete Category", systemImage: "trash", role: .destructive) { remove(name) }
                    }
            }
            if addingCategory {
                TextField(String(localized: "Name, e.g. AI or Design", comment: "Sidebar placeholder for a new smart category"), text: $newCategory)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
                    .focused($categoryFieldFocused)
                    .onSubmit(add)
                    .onExitCommand { addingCategory = false }
                    .onAppear { categoryFieldFocused = true }
            } else {
                Button {
                    newCategory = ""
                    addingCategory = true
                } label: {
                    Label("New Category", systemImage: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Name a topic. Stash finds the snips that are about it, also by what their images show.")
            }
        }
    }

    private func add() {
        let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        addingCategory = false
        guard !name.isEmpty else { return }
        if !model.settings.categories.contains(name) { model.settings.categories.append(name) }
        model.search.filter = .category(name)
    }

    private func remove(_ name: String) {
        model.settings.categories.removeAll { $0 == name }
        if model.search.filter == .category(name) { model.search.filter = .all }
    }

    // MARK: Rows

    @ViewBuilder
    private func section(_ title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
            content()
        }
    }

    private func row(_ filter: LibraryFilter, count: Int? = nil) -> some View {
        let selected = model.search.filter == filter
        return Button {
            withAnimation(.snappy(duration: 0.2)) { model.search.filter = filter }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                // The "number" icon already marks a tag; the title's own "#" would repeat it.
                Text(filter.title.hasPrefix("#") ? String(filter.title.dropFirst()) : filter.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.ink.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
