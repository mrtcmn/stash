import AVFoundation
import Foundation
import StashCore
import Vision

/// Reads what is inside a snip's media, on this Mac: text in every image (OCR), what the
/// images show (labels), and still frames from videos. Search and the embedding use all three.
@MainActor
final class MediaAnalyzer {
    /// Raise this to run a new kind of analysis over the whole library once.
    static let version = 1

    private let library: LibraryStore
    private var queue: [UUID] = []
    private var queued: Set<UUID> = []
    private var running = false

    init(library: LibraryStore) {
        self.library = library
    }

    func scan() {
        enqueue(library.snips.map(\.id))
    }

    func enqueue(_ ids: [UUID]) {
        for id in ids where !queued.contains(id) {
            guard let snip = library.snip(id), Self.needsAnalysis(snip) else { continue }
            queued.insert(id)
            queue.append(id)
        }
        pump()
    }

    static func needsAnalysis(_ snip: Snip) -> Bool {
        guard (snip.analysisVersion ?? 0) < version else { return false }
        let hasInput = snip.media.contains { $0.localFile != nil || $0.videoURL != nil }
        // Wait for the downloader: it enqueues the snip again once the files are local.
        let waiting = snip.media.contains { $0.kind == .image && $0.localFile == nil && $0.remoteURL != nil }
        return hasInput && !waiting
    }

    // ponytail: one snip at a time keeps Vision and video decoding off the user's way; a pool if it is too slow.
    private func pump() {
        guard !running, !queue.isEmpty else { return }
        running = true
        let id = queue.removeFirst()
        Task {
            await analyze(id)
            queued.remove(id)
            running = false
            pump()
        }
    }

    private func analyze(_ id: UUID) async {
        guard let snip = library.snip(id), Self.needsAnalysis(snip) else { return }
        let store = library.media
        // Screenshots and images already get OCR when they are saved.
        let wantsOCR = snip.ocrText == nil
        let media = snip.media

        let result = await Task.detached(priority: .utility) {
            await Self.run(media: media, wantsOCR: wantsOCR, store: store)
        }.value

        library.mutate(id) { s in
            if wantsOCR, !result.ocr.isEmpty { s.ocrText = result.ocr }
            s.labels = result.labels
            for (index, frames) in result.frames where index < s.media.count {
                s.media[index].frames = frames
            }
            s.analysisVersion = Self.version
        }
    }

    private struct Result: Sendable {
        var ocr = ""
        var labels: [String] = []
        var frames: [Int: [String]] = [:]
    }

    nonisolated private static func run(media: [SnipMedia], wantsOCR: Bool, store: MediaStore) async -> Result {
        var result = Result()
        var texts: [String] = []
        var labelScores: [String: Float] = [:]

        for (index, m) in media.enumerated() {
            var images: [CGImage] = []
            if let file = m.localFile, let image = ImageCoding.cgImage(at: store.url(for: file)) {
                images.append(image)
            }
            if (m.kind == .video || m.kind == .gif), m.frames == nil, let raw = m.videoURL, let url = URL(string: raw) {
                let stills = await VideoFrames.sample(url, count: m.kind == .gif ? 3 : 6)
                let names = stills.compactMap { image in
                    ImageCoding.jpeg(image, quality: 0.8).flatMap { try? store.save($0, fileExtension: "jpg") }
                }
                if !names.isEmpty { result.frames[index] = names }
                images += stills
            }
            for (i, image) in images.enumerated() {
                // Text in a video is usually the same on every frame; read the first one only.
                if wantsOCR, i == 0 {
                    let text = await TextRecognizer.recognize(image)
                    if !text.isEmpty { texts.append(text) }
                }
                for (label, score) in ImageLabeler.labels(image) {
                    labelScores[label] = max(labelScores[label] ?? 0, score)
                }
            }
        }
        result.ocr = texts.joined(separator: "\n\n")
        result.labels = labelScores.sorted { $0.value > $1.value }.prefix(8).map(\.key)
        return result
    }
}

enum ImageLabeler {
    /// Apple's on-device classifier: about 1,300 everyday labels such as "document", "food" or "dog".
    nonisolated static func labels(_ image: CGImage) -> [(String, Float)] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? [])
            // Apple's recommended filter: keep labels that are right at least 90% of the time.
            .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
            .prefix(6)
            .map { ($0.identifier.replacingOccurrences(of: "_", with: " "), $0.confidence) }
    }
}

enum VideoFrames {
    /// Evenly spaced stills from a local or remote video. AVFoundation reads only the
    /// byte ranges it needs, so a remote MP4 is not downloaded in full.
    nonisolated static func sample(_ url: URL, count: Int) async -> [CGImage] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // The embedding sees each frame at about 140 vision tokens; 512 px is plenty and halves the disk use.
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let times = (0..<count).map { i in
            CMTime(seconds: duration.seconds * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
        }
        var images: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image { images.append(image) }
        }
        return images
    }
}
