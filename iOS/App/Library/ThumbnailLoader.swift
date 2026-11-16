import SwiftUI
import ImageIO
import StashCore

/// Downsampled, cached thumbnails. Local files first, then remote URLs through URLCache.
final class ThumbnailLoader: @unchecked Sendable {
    /// A decoded image and the pixel limit it was decoded for.
    final class Entry { let image: UIImage; let maxPixel: CGFloat
        init(_ image: UIImage, _ maxPixel: CGFloat) { self.image = image; self.maxPixel = maxPixel } }

    static let shared = ThumbnailLoader()

    private let cache: NSCache<NSString, Entry> = {
        let c = NSCache<NSString, Entry>()
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 128 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
    private var warning: NSObjectProtocol?

    init() {
        warning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [cache] _ in cache.removeAllObjects() }
    }

    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private static let maxDownload: Int64 = 15 << 20

    func image(for media: SnipMedia, maxPixel: CGFloat) async -> UIImage? {
        guard let source = media.localFile ?? media.remoteURL else { return nil }
        let key = source as NSString
        // One decode serves every size up to its own: reuse a cached image that is large enough.
        if let hit = cache.object(forKey: key), hit.maxPixel >= maxPixel { return hit.image }

        let flightKey = "\(source)@\(Int(maxPixel))"
        let task: Task<UIImage?, Never> = lock.withLock {
            if let existing = inFlight[flightKey] { return existing }
            let created = Task.detached(priority: .utility) { [self] in
                let image = await load(media, maxPixel: maxPixel)
                if let image {
                    cache.setObject(Entry(image, maxPixel), forKey: key, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
                }
                lock.withLock { inFlight[flightKey] = nil }
                return image
            }
            inFlight[flightKey] = created
            return created
        }
        return await task.value
    }

    private func load(_ media: SnipMedia, maxPixel: CGFloat) async -> UIImage? {
        if let file = media.localFile {
            return Self.downsample(SharedStore.shared.mediaURL.appendingPathComponent(file), maxPixel: maxPixel)
        }
        guard let s = media.remoteURL, let url = URL(string: s), ["http", "https"].contains(url.scheme) else { return nil }
        // Download to a file so a large image never sits in memory as Data.
        guard let (file, response) = try? await session.download(from: url) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        guard response.expectedContentLength <= Self.maxDownload, size <= Self.maxDownload else { return nil }
        return Self.downsample(file, maxPixel: maxPixel)
    }

    private static func downsample(_ file: URL, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Loads a thumbnail when it appears and cancels when it scrolls away.
struct AsyncThumbnail: View {
    let media: SnipMedia
    var maxPixel: CGFloat = 600
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: media.localFile ?? media.remoteURL) {
            image = await ThumbnailLoader.shared.image(for: media, maxPixel: maxPixel)
        }
    }
}
