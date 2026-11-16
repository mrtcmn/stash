import SwiftUI
import UIKit
import UniformTypeIdentifiers
import StashCore

/// Saves the shared link instantly, shows a short confirmation, then closes.
/// Metadata enrichment gets a small time budget and never blocks the UI.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareConfirmationView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await run() }
    }

    private func run() async {
        let started = Date()
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        guard SharedStore.shared.isAvailable else {
            model.state = .unavailable
            await finish(after: 1.6, since: started)
            return
        }
        guard let url = await Self.findURL(in: items) else {
            model.state = .failed
            await finish(after: 0.9, since: started)
            return
        }
        let title = Self.cleanTitle(items.compactMap { $0.attributedContentText?.string ?? $0.attributedTitle?.string }.first, url: url)
        do {
            let snip = try await SharedStore.shared.save(url: url, title: title)
            model.state = .saved
            model.host = snip.domain ?? url.host
            // Enrich within the time budget. Cancelling the fetch keeps the head read so far.
            // The app finishes the job on the next launch if nothing came back.
            let fetch = Task { await LightEnricher.enrich(snip, url: url) }
            let timer = Task {
                try? await Task.sleep(for: .seconds(0.85))
                fetch.cancel()
            }
            let enriched = await fetch.value
            timer.cancel()
            if let enriched {
                // Field-level update: a delete or favorite made meanwhile in the app is kept.
                let autoTitle = title
                let stored = try? await SharedStore.shared.update(id: snip.id) { LightEnricher.apply(enriched, to: &$0, autoTitle: autoTitle) }
                if let name = stored?.displayTitle, !name.isEmpty { model.title = name }
            }
        } catch {
            model.state = .failed
        }
        await finish(after: 0.9, since: started)
    }

    /// Shared text often holds the link too. Remove the link; drop the title when nothing else remains.
    private static func cleanTitle(_ text: String?, url: URL) -> String? {
        guard var text else { return nil }
        for form in [url.absoluteString, url.absoluteString.removingTrailingSlash] {
            text = text.replacingOccurrences(of: form, with: "")
        }
        if let found = firstURL(in: text) { text = text.replacingOccurrences(of: found.absoluteString, with: "") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == url.absoluteString { return nil }
        return String(text.prefix(140))
    }

    private func finish(after seconds: Double, since start: Date) async {
        let wait = seconds - Date().timeIntervalSince(start)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private static func findURL(in items: [NSExtensionItem]) async -> URL? {
        let providers = items.flatMap { $0.attachments ?? [] }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let item = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) {
                if let url = item as? URL, url.scheme?.hasPrefix("http") == true { return url }
                if let text = item as? String, let url = firstURL(in: text) { return url }
            }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let item = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier),
               let text = item as? String, let url = firstURL(in: text) { return url }
        }
        for item in items {
            if let text = item.attributedContentText?.string, let url = firstURL(in: text) { return url }
        }
        return nil
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, range: range) ?? []
        return matches.compactMap(\.url).first { $0.scheme == "http" || $0.scheme == "https" }
    }
}

private extension String {
    var removingTrailingSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}

// MARK: - Confirmation UI

@MainActor
final class ShareModel: ObservableObject {
    enum State { case saving, saved, failed, unavailable }
    @Published var state: State = .saving
    @Published var host: String?
    @Published var title: String?
}

struct ShareConfirmationView: View {
    @ObservedObject var model: ShareModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appeared = false

    private var headline: String {
        switch model.state {
        case .failed: "Nothing to save"
        case .unavailable: "Stash is not set up"
        default: "Saved to Stash"
        }
    }
    private var isError: Bool { model.state == .failed || model.state == .unavailable }

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(.largeTitle, weight: .medium))
                    .foregroundStyle(isError ? Theme.danger : Theme.tint(for: .link))
                    .symbolEffect(.bounce, value: reduceMotion ? ShareModel.State.saving : model.state)
                    .accessibilityHidden(true)
                Text(headline)
                    .headline(20, .medium)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if model.state == .unavailable {
                    Text("Open the Stash app once, then try again.")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                } else if let line = model.title ?? model.host {
                    Text(line)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 300)
            .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(.white.opacity(contrast == .increased ? 0.4 : 0.12)))
            .scaleEffect(reduceMotion || appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        // Dark-only on purpose: see Theme.
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .onAppear {
            if reduceMotion { appeared = true } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { appeared = true } }
            announce()
        }
        .onChange(of: model.state) { announce() }
    }

    private func announce() {
        guard model.state != .saving else { return }
        UIAccessibility.post(notification: .announcement, argument: headline)
    }
}
