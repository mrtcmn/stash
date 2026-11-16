import Foundation
import os
import StashCore

/// Library store in the App Group container, shared by the app and the Share Extension.
/// Keeps no connection state beyond one `SnipDatabase`; safe for the extension memory cap.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.dev.grasco.stash"
    /// Darwin notification posted after every write so the other process can reload.
    public static let changeNotification = "dev.grasco.stash.library-changed"

    public static let shared = SharedStore()

    private static let log = Logger(subsystem: "dev.grasco.stash", category: "store")

    private let database: SnipDatabase?
    /// Why the library did not open, or nil. The empty screen shows it.
    public private(set) var openError: String?
    private let lock = NSLock()
    private var observers: [UUID: @Sendable () -> Void] = [:]
    /// Identifies this process in the writer file, so a process can ignore its own notifications.
    private let token = UUID().uuidString

    /// The folder that holds the library, or nil when the App Group container is missing.
    public let rootURL: URL?
    public var mediaURL: URL { (rootURL ?? FileManager.default.temporaryDirectory).appendingPathComponent("Media", isDirectory: true) }
    /// True when the database opened. False means an entitlement problem or a disk error.
    public var isAvailable: Bool { database != nil }

    /// Pass `rootURL` only in tests. The shared singleton never falls back to a private folder,
    /// because data saved there would be invisible to the other process.
    public init(rootURL: URL? = nil) {
        let root = rootURL
            ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
                .appendingPathComponent("Stash", isDirectory: true)
        self.rootURL = root
        guard let root else {
            Self.log.error("App Group container \(Self.appGroupID, privacy: .public) is missing. Check the entitlements.")
            database = nil
            openError = "App Group container is missing"
            return
        }
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Media"), withIntermediateDirectories: true)
        do {
            database = try SnipDatabase(fileURL: root.appendingPathComponent("library.sqlite"))
            openError = nil
        } catch {
            openError = String(describing: error)
            Self.log.error("Cannot open the library: \(String(describing: error), privacy: .public)")
            database = nil
        }
        // Dev seed: a library file copied next to the database is merged once, then removed.
        let seed = root.appendingPathComponent("seed.sqlite")
        if let database, FileManager.default.fileExists(atPath: seed.path) {
            Task { [self] in
                do {
                    try await database.importSnips(fromFile: seed.path)
                    try? FileManager.default.removeItem(at: seed)
                } catch { openError = "Seed import failed: \(error)" }
                reload()
            }
        }
        startListening()
    }

    // MARK: Writes

    /// Saves a bare link snip. Re-saving the same URL merges into the existing snip.
    /// The look-up, merge and write run in one transaction, so two processes cannot insert twice.
    @discardableResult
    public func save(url: URL, title: String? = nil, source: String = "ios-share") async throws -> Snip {
        guard let database else { throw StoreError.unavailable }
        let absolute = url.absoluteString
        let key = "url:\(URLNormalizer.normalize(absolute))"
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let now = Date()
        let incoming = Snip(
            kind: .link, title: cleanTitle, url: absolute,
            createdAt: now, savedAt: now, source: source, externalID: key,
            link: LinkInfo(url: absolute, title: cleanTitle.isEmpty ? nil : cleanTitle)
        )
        let result = try await database.mergeUpsert(externalID: key) { existing in
            existing.map { SnipMerger.merge(existing: $0, incoming: incoming) } ?? incoming
        }
        postChange()
        return result
    }

    public func upsert(_ snips: [Snip]) async throws {
        guard let database else { throw StoreError.unavailable }
        try await database.upsert(snips)
        postChange()
    }

    /// Atomic field-level change. Returns nil, and writes nothing, when the snip was deleted meanwhile.
    @discardableResult
    public func update(id: UUID, _ transform: @escaping @Sendable (inout Snip) -> Void) async throws -> Snip? {
        guard let database else { throw StoreError.unavailable }
        let result = try await database.update(id: id, transform: transform)
        if result != nil { postChange() }
        return result
    }

    public func delete(ids: [UUID]) async throws {
        guard let database else { throw StoreError.unavailable }
        try await database.delete(ids: ids)
        postChange()
    }

    // MARK: Reads

    /// All snips, newest first.
    public func list() async -> [Snip] {
        guard let database else { return [] }
        return (try? await database.loadAll()) ?? []
    }

    /// A stream that yields the full list now and after changes from other processes.
    /// One consumer loads serially, so snapshots arrive in order. Bursts of changes collapse
    /// into one reload after a short quiet period.
    public func updates() -> AsyncStream<[Snip]> {
        AsyncStream { continuation in
            let id = UUID()
            let (triggers, trigger) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            trigger.yield()
            let task = Task { [weak self] in
                for await _ in triggers {
                    guard let self, !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(100))
                    continuation.yield(await self.list())
                }
            }
            lock.lock(); observers[id] = { trigger.yield() }; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                trigger.finish()
                self?.lock.lock(); self?.observers[id] = nil; self?.lock.unlock()
            }
        }
    }

    /// Asks every stream to reload, for example when the app returns to the foreground.
    public func reload() { notifyObservers() }

    public enum StoreError: Error { case unavailable }

    // MARK: Cross-process notification

    private var writerFile: URL? { rootURL?.appendingPathComponent("writer") }

    private func postChange() {
        try? token.write(to: writerFile ?? URL(fileURLWithPath: "/dev/null"), atomically: true, encoding: .utf8)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.changeNotification as CFString), nil, nil, true)
    }

    private func startListening() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center, Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<SharedStore>.fromOpaque(observer).takeUnretainedValue().handleDarwinChange()
            },
            Self.changeNotification as CFString, nil, .deliverImmediately)
    }

    private func handleDarwinChange() {
        // The last writer was this process: local state is already current.
        if let file = writerFile, (try? String(contentsOf: file, encoding: .utf8)) == token { return }
        notifyObservers()
    }

    fileprivate func notifyObservers() {
        lock.lock(); let all = Array(observers.values); lock.unlock()
        all.forEach { $0() }
    }
}
