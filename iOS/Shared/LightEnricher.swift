import Foundation
import StashCore

/// Small-footprint metadata fetch: reads at most 200 KB of HTML, stops at `</head>`,
/// never downloads images. Used by the Share Extension and by the app for bare links.
enum LightEnricher {
    private static let configuration: URLSessionConfiguration = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        return config
    }()
    private static let session = URLSession(configuration: configuration)

    /// Returns a copy of `base` with fetched metadata. On cancellation it parses what it already read.
    static func enrich(_ base: Snip, url: URL) async -> Snip? {
        if let ref = TweetURL.parse(url.absoluteString) { return await tweetText(base, ref) }
        return await page(base, url)
    }

    /// Copies enrichment onto a stored snip, field by field. The title changes only when it is
    /// empty or still the automatic one, so a title the user edited stays.
    static func apply(_ enriched: Snip, to snip: inout Snip, autoTitle: String?) {
        let current = snip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enriched.title.isEmpty, current.isEmpty || current == autoTitle { snip.title = enriched.title }
        if let link = enriched.link { snip.link = link }
        if snip.media.isEmpty { snip.media = enriched.media }
        snip.updatedAt = Date()
    }

    /// Posts: use the small oEmbed JSON for a readable title.
    private static func tweetText(_ base: Snip, _ ref: TweetReference) async -> Snip? {
        var c = URLComponents(string: "https://publish.twitter.com/oembed")!
        c.queryItems = [
            URLQueryItem(name: "url", value: "https://twitter.com/\(ref.handle ?? "i")/status/\(ref.id)"),
            URLQueryItem(name: "omit_script", value: "true"),
            URLQueryItem(name: "dnt", value: "true"),
        ]
        guard let (data, _) = try? await session.data(from: c.url!),
              let post = try? OEmbedParser.snip(from: data, reference: ref) else { return nil }
        var snip = base
        let text = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = post.author?.name ?? ""
        let title = text.isEmpty ? "" : String(text.prefix(140))
        snip.title = title
        var info = snip.link ?? LinkInfo(url: base.url)
        info.title = title.isEmpty ? nil : title
        info.summary = name.isEmpty ? nil : name
        snip.link = info
        return snip
    }

    private static func page(_ base: Snip, _ url: URL) async -> Snip? {
        guard let data = await HeadCollector().fetch(url, configuration: configuration), !data.isEmpty else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let parsed = LinkMetadataParser.parse(html: html, pageURL: url)
        var snip = base
        var info = parsed.info
        info.url = info.url ?? url.absoluteString
        snip.link = info
        snip.title = parsed.title ?? ""
        if snip.media.isEmpty, let image = info.imageURL {
            snip.media = [SnipMedia(kind: .image, remoteURL: image)]
        }
        return snip
    }
}

/// Streams a page and stops once the head is complete or 200 KB arrived.
/// Cancelling the calling task returns the bytes read so far instead of nothing.
private final class HeadCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private static let limit = 200_000
    private static let closers = ["</head>", "</HEAD>"].map { Data($0.utf8) }

    private let lock = NSLock()
    private var data = Data()
    private var usable = true
    private var finished = false
    private var continuation: CheckedContinuation<Data?, Never>?
    private var task: URLSessionDataTask?
    private var session: URLSession?

    func fetch(_ url: URL, configuration: URLSessionConfiguration) async -> Data? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                lock.lock()
                if finished { lock.unlock(); cont.resume(returning: nil); return }
                continuation = cont
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            finish()
        }
    }

    private func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let cont = continuation
        continuation = nil
        let result: Data? = usable ? data : nil
        let task = task, session = session
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        cont?.resume(returning: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           (http.mimeType ?? "").contains("html") {
            completionHandler(.allow)
        } else {
            lock.lock(); usable = false; lock.unlock()
            completionHandler(.cancel)
            finish()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        let from = max(0, data.count - 7)
        data.append(chunk)
        let done = data.count >= Self.limit
            || Self.closers.contains { data.range(of: $0, in: from..<data.count) != nil }
        lock.unlock()
        if done { finish() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish()
    }
}
