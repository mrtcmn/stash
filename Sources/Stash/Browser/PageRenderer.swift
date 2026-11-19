import Foundation
import WebKit

/// Loads a page in an offscreen WebKit view so its scripts run, then returns the
/// rendered HTML. Used for pages that send an empty shell without JavaScript.
/// WebKit ships with macOS, so this needs no bundled Chromium.
@MainActor
final class PageRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?

    private override init() {
        let config = WKWebViewConfiguration()
        // A private, throwaway store: the page sees no cookies from earlier renders.
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    /// The page's HTML after scripts ran, or nil on failure or timeout.
    static func render(_ url: URL, timeout: Double = 15, settle: Double = 1.5) async -> String? {
        let renderer = PageRenderer()
        defer { renderer.webView.stopLoading() }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in try await renderer.load(url) }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw URLError(.timedOut)
                }
                try await group.next()
                group.cancelAll()
            }
            // Let client-side rendering finish after the load event.
            try await Task.sleep(for: .seconds(settle))
            return try await renderer.webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
        } catch {
            renderer.finish(error)
            return nil
        }
    }

    private func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}
