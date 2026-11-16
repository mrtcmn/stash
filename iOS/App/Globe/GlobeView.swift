import SwiftUI
import UIKit
import QuartzCore
import StashCore

/// The library globe for iOS: cards in a brick grid bent onto a sphere, moved as Core Animation
/// layers. Each card renders once to an image. Drag to pan with inertia, pinch to zoom, tap to open.
struct GlobeView: UIViewRepresentable {
    let items: [Snip]
    var onSelect: (Snip) -> Void
    var onSwitchToGrid: () -> Void = {}

    func makeUIView(context: Context) -> GlobeUIView { GlobeUIView() }

    func updateUIView(_ view: GlobeUIView, context: Context) {
        view.onSelect = onSelect
        view.onSwitchToGrid = onSwitchToGrid
        view.update(items: items)
    }
}

@MainActor
final class GlobeUIView: UIView {
    var onSelect: ((Snip) -> Void)?
    var onSwitchToGrid: (() -> Void)?

    private static let card = CardPainter.size
    private static let pitch = CGSize(width: card.width + 22, height: card.height + 22)
    private static let zoomRange: ClosedRange<CGFloat> = 0.25...1.6
    private static let initialZoom: CGFloat = 0.5
    private static let minimumToRepeat = 12
    private static let maxInstances = 120
    private static let maxCachedImages = 100

    private struct Key: Hashable { let index: Int, copyX: Int, copyY: Int }
    private struct Hit { let snip: Snip; let frame: CGRect; let depth: CGFloat }
    private struct CardImage { let revision: Int; let image: CGImage; var lastUsed: CFTimeInterval }
    private struct Candidate { let index: Int; let copyX: Int; let copyY: Int; let distance: CGFloat }
    private struct RowCell { let x: Double; let index: Int }

    private var items: [Snip] = []
    private var itemByID: [UUID: Snip] = [:]
    private var revision: [UUID: Int] = [:]
    /// Cells grouped by row and sorted by x, so a frame visits only the cards near the screen.
    private var rowCells: [[RowCell]] = []
    private var minRow = 0
    private var candidates: [Candidate] = []
    private var scratch: [Key: CALayer] = [:]
    private var dirty = true
    private var entranceActive = false
    private var stamp = 0
    private var a11yElements: [Any]?
    private var grid = GlobeLayout(count: 0, cellAspect: 1)
    private var appearedAt: [UUID: CFTimeInterval] = [:]
    private var images: [UUID: CardImage] = [:]
    /// Cards waiting to draw: distance from the screen center and the frame that last asked.
    private var queued: [UUID: (distance: CGFloat, stamp: Int)] = [:]
    private var renderTask: Task<Void, Never>?
    private var placeholder: CGImage?

    private var camera = CGPoint.zero
    private var target = CGPoint.zero
    private var velocity = CGPoint.zero // world points per 60 Hz frame
    private var zoom: CGFloat = initialZoom
    private var targetZoom: CGFloat = initialZoom
    private var zoomAnchor: (world: CGPoint, screen: CGPoint)?
    private var shift: CGFloat = 0
    private var lastFrame: CFTimeInterval?
    private var dragging = false
    private var pinching = false
    private var pinchStartZoom: CGFloat = 1

    private let scene = CALayer()
    private var live: [Key: CALayer] = [:]
    private var spare: [CALayer] = []
    private var hits: [Hit] = []
    private var link: CADisplayLink?
    private var active = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        layer.isGeometryFlipped = false
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.addSublayer(scene)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        [pan, pinch, tap].forEach(addGestureRecognizer)

        NotificationCenter.default.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setInactive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(wakeNow), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            link?.invalidate()
            link = nil
            return
        }
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = reduceMotion ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60) : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        wake()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scene.frame = bounds
        CATransaction.commit()
        wake()
    }

    @objc private func setActive() { active = true; wake() }
    @objc private func setInactive() { active = false }
    @objc private func wakeNow() {
        link?.preferredFrameRateRange = reduceMotion ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60) : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        wake()
    }

    @objc private func memoryWarning() {
        let onScreen = Set(live.keys.compactMap { $0.index < items.count ? items[$0.index].id : nil })
        images = images.filter { onScreen.contains($0.key) }
        placeholder = nil
    }

    // MARK: Content

    func update(items newItems: [Snip]) {
        let oldIDs = items.map(\.id)
        let newIDs = newItems.map(\.id)
        let oldByID = itemByID
        items = newItems
        itemByID = Dictionary(newItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A changed snip gets a new revision, so its card draws again.
        for snip in newItems where oldByID[snip.id] != snip { revision[snip.id, default: 0] += 1 }
        if oldIDs != newIDs {
            grid = GlobeLayout(count: newItems.count, cellAspect: Self.pitch.width / Self.pitch.height)
            indexRows()
            let now = CACurrentMediaTime()
            let old = Set(oldIDs)
            var appeared: [UUID: CFTimeInterval] = [:]
            for id in newIDs { appeared[id] = old.contains(id) ? (appearedAt[id] ?? 0) : now }
            appearedAt = appeared
            revision = revision.filter { itemByID[$0.key] != nil }
        }
        wake()
    }

    private func indexRows() {
        guard !grid.cells.isEmpty else { rowCells = []; minRow = 0; return }
        let rows = grid.cells.map { Int($0.y.rounded()) }
        minRow = rows.min() ?? 0
        var buckets = [[RowCell]](repeating: [], count: (rows.max() ?? 0) - minRow + 1)
        for (index, cell) in grid.cells.enumerated() where index < items.count {
            buckets[Int(cell.y.rounded()) - minRow].append(RowCell(x: cell.x, index: index))
        }
        rowCells = buckets.map { $0.sorted { $0.x < $1.x } }
    }

    // MARK: Frame loop

    private func wake() { dirty = true; link?.isPaused = false }

    @objc private func tick(_ link: CADisplayLink) {
        guard active else { link.isPaused = true; lastFrame = nil; return }
        let now = link.timestamp
        let dt = lastFrame.map { now - $0 } ?? 1.0 / 60
        lastFrame = now
        let moving = step(dt: dt)
        // Skip the layer work when nothing moved, changed or fades in.
        if moving || dirty || entranceActive || dragging || pinching {
            dirty = false
            entranceActive = render(now: now)
        }
        if !moving, !entranceActive, !dirty, !dragging, !pinching {
            link.isPaused = true
            lastFrame = nil
        }
    }

    private func step(dt: CFTimeInterval) -> Bool {
        let r = CGFloat(min(2, max(0.2, dt * 60)))
        let previous = camera
        if !dragging, hypot(velocity.x, velocity.y) > 0.05 {
            target.x += velocity.x * r
            target.y += velocity.y * r
            velocity.x *= pow(0.88, r)
            velocity.y *= pow(0.88, r)
            zoomAnchor = nil
        }
        let ease = reduceMotion ? 1 : 1 - pow(0.84, r)
        zoom = exp(log(zoom) + (log(targetZoom) - log(zoom)) * ease)
        if let anchor = zoomAnchor {
            camera = CGPoint(x: anchor.world.x - anchor.screen.x / zoom, y: anchor.world.y - anchor.screen.y / zoom)
            if abs(zoom - targetZoom) < targetZoom * 0.0005 { zoomAnchor = nil }
        } else {
            camera.x += (target.x - camera.x) * ease
            camera.y += (target.y - camera.y) * ease
        }
        let p = perspective
        let speed = hypot(camera.x - previous.x, camera.y - previous.y) * zoom / r
        let shiftTarget = reduceMotion ? 0 : -p * 0.095 * tanh(speed / (p * 0.065))
        let follow = reduceMotion ? 1 : 1 - pow(0.89, r)
        shift += (shiftTarget - shift) * follow

        return hypot(target.x - camera.x, target.y - camera.y) * zoom > 0.05
            || abs(zoom - targetZoom) > targetZoom * 0.0005
            || hypot(velocity.x, velocity.y) > 0.05
            || abs(shift - shiftTarget) > 0.1
    }

    /// The sphere scales with the longer screen side, tuned so a phone shows a similar curve to the Mac.
    private var unit: CGFloat { max(bounds.width, bounds.height, 1) / 1728 * 1.6 }
    private var perspective: CGFloat { 1200 * unit }
    private var sphereRadius: CGFloat { 5000 * unit }

    private func render(now: CFTimeInterval) -> Bool {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let p = perspective
        let radius = sphereRadius
        var sub = CATransform3DIdentity
        sub.m34 = -1 / p
        scene.sublayerTransform = sub

        let size = bounds.size
        let card = Self.card
        let halfW = size.width / 2 / zoom + card.width
        let halfH = size.height / 2 / zoom + card.height
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        stamp += 1

        collectCandidates(size: size, halfW: halfW, halfH: halfH)

        scratch.removeAll(keepingCapacity: true)
        hits.removeAll(keepingCapacity: true)
        var animating = false

        for candidate in candidates {
            let index = candidate.index
            let item = items[index]
            let cell = grid.cells[index]
            let wx = CGFloat(cell.x) * Self.pitch.width + CGFloat(candidate.copyX) * periodX
            let wy = CGFloat(cell.y) * Self.pitch.height + CGFloat(candidate.copyY) * periodY
            let dx = (wx - camera.x) * zoom
            let dy = (wy - camera.y) * zoom

            let key = Key(index: index, copyX: candidate.copyX, copyY: candidate.copyY)
            let layer = live.removeValue(forKey: key) ?? makeLayer()
            scratch[key] = layer
            let entrance = appear(item.id, rank: index, now: now)
            if entrance < 1 { animating = true }

            let theta = dx / radius, phi = dy / radius
            let a = (x: sin(theta) * cos(phi), y: sin(phi), z: cos(theta) * cos(phi))
            let position = (x: a.x * radius, y: a.y * radius, z: (a.z - 1) * radius + shift)
            let scale = zoom * (0.92 + 0.08 * entrance)
            var transform = CATransform3DMakeScale(scale, scale, 1)
            let axis = hypot(a.y, a.x)
            if axis > 1e-9 {
                transform = CATransform3DConcat(transform, CATransform3DMakeRotation(acos(min(1, a.z)), -a.y / axis, a.x / axis, 0))
            }
            transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(position.x, position.y, position.z))
            layer.transform = transform
            layer.opacity = Float(entrance)
            show(item, in: layer, now: now, distance: candidate.distance)

            let f = p / (p - position.z)
            let w = card.width * scale * f, h = card.height * scale * f
            let screen = CGPoint(x: center.x + position.x * f, y: center.y + position.y * f)
            hits.append(Hit(snip: item, frame: CGRect(x: screen.x - w / 2, y: screen.y - h / 2, width: w, height: h), depth: position.z))
        }

        for (_, layer) in live {
            layer.isHidden = true
            spare.append(layer)
        }
        swap(&live, &scratch)
        a11yElements = nil
        pumpRenderQueue()
        return animating
    }

    private var periodX: CGFloat { CGFloat(grid.columns) * Self.pitch.width }
    private var periodY: CGFloat { CGFloat(grid.rows) * Self.pitch.height }

    /// Fills `candidates` with the cards near the screen. Only the rows and columns that overlap
    /// the visible window are visited, so the cost follows the screen, not the library size.
    private func collectCandidates(size: CGSize, halfW: CGFloat, halfH: CGFloat) {
        candidates.removeAll(keepingCapacity: true)
        guard !items.isEmpty, !rowCells.isEmpty else { return }
        let card = Self.card
        let limitX = size.width / 2 + card.width * zoom
        let limitY = size.height / 2 + card.height * zoom

        func consider(_ cell: RowCell, copyX: Int, copyY: Int) {
            let c = grid.cells[cell.index]
            let dx = (CGFloat(c.x) * Self.pitch.width + CGFloat(copyX) * periodX - camera.x) * zoom
            let dy = (CGFloat(c.y) * Self.pitch.height + CGFloat(copyY) * periodY - camera.y) * zoom
            guard abs(dx) < limitX, abs(dy) < limitY else { return }
            candidates.append(Candidate(index: cell.index, copyX: copyX, copyY: copyY, distance: dx * dx + dy * dy))
        }

        if items.count < Self.minimumToRepeat {
            for row in rowCells { for cell in row { consider(cell, copyX: 0, copyY: 0) } }
        } else {
            let pw = Double(Self.pitch.width), ph = Double(Self.pitch.height)
            let cols = Double(grid.columns), rows = Double(grid.rows)
            let xLo = (Double(camera.x) - Double(halfW)) / pw, xHi = (Double(camera.x) + Double(halfW)) / pw
            let yLo = (Double(camera.y) - Double(halfH)) / ph, yHi = (Double(camera.y) + Double(halfH)) / ph
            let maxRow = minRow + rowCells.count - 1
            let copyYLo = Int(((yLo - Double(maxRow)) / rows).rounded(.up))
            let copyYHi = Int(((yHi - Double(minRow)) / rows).rounded(.down))
            if copyYLo <= copyYHi {
                for copyY in copyYLo...copyYHi {
                    let rLo = max(minRow, Int((yLo - Double(copyY) * rows).rounded(.up)))
                    let rHi = min(maxRow, Int((yHi - Double(copyY) * rows).rounded(.down)))
                    guard rLo <= rHi else { continue }
                    for r in rLo...rHi {
                        let cells = rowCells[r - minRow]
                        guard let first = cells.first, let last = cells.last else { continue }
                        let copyXLo = Int(((xLo - last.x) / cols).rounded(.up))
                        let copyXHi = Int(((xHi - first.x) / cols).rounded(.down))
                        guard copyXLo <= copyXHi else { continue }
                        for copyX in copyXLo...copyXHi {
                            let from = xLo - Double(copyX) * cols, to = xHi - Double(copyX) * cols
                            var i = lowerBound(cells, x: from)
                            while i < cells.count, cells[i].x <= to {
                                consider(cells[i], copyX: copyX, copyY: copyY)
                                i += 1
                            }
                        }
                    }
                }
            }
        }
        if candidates.count > Self.maxInstances {
            candidates.sort { $0.distance < $1.distance }
            candidates.removeLast(candidates.count - Self.maxInstances)
        }
    }

    private func lowerBound(_ cells: [RowCell], x: Double) -> Int {
        var lo = 0, hi = cells.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cells[mid].x < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func makeLayer() -> CALayer {
        if let layer = spare.popLast() {
            layer.isHidden = false
            return layer
        }
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: CardPainter.canvas)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer.contentsGravity = .resize
        layer.contentsScale = traitCollection.displayScale
        // Shadow and corners are part of the image. Fading layers need no group pass.
        layer.allowsGroupOpacity = false
        layer.isOpaque = false
        scene.addSublayer(layer)
        return layer
    }

    private func appear(_ id: UUID, rank: Int, now: CFTimeInterval) -> CGFloat {
        guard !reduceMotion, let start = appearedAt[id], start > 0 else { return 1 }
        let delay = min(0.3, Double(rank).squareRoot() * 0.03)
        let t = max(0, min(1, (now - start - delay) / 0.35))
        if t >= 1 { appearedAt[id] = 0 }
        return CGFloat(t * t * (3 - 2 * t))
    }

    // MARK: Card images

    private func show(_ snip: Snip, in layer: CALayer, now: CFTimeInterval, distance: CGFloat) {
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let current = revision[snip.id, default: 0]
        if var cached = images[snip.id] {
            cached.lastUsed = now
            images[snip.id] = cached
            if (layer.contents as AnyObject?) !== cached.image { layer.contents = cached.image }
            if cached.revision == current { return }
        } else {
            if placeholder == nil { placeholder = CardPainter.placeholder(scale: min(2, traitCollection.displayScale)) }
            if (layer.contents as AnyObject?) !== placeholder { layer.contents = placeholder }
        }
        if let old = queued[snip.id], old.stamp == stamp {
            queued[snip.id] = (min(old.distance, distance), stamp)
        } else {
            queued[snip.id] = (distance, stamp)
        }
    }

    /// Starts one background draw for the nearest waiting card. Cards that left the screen are dropped.
    private func pumpRenderQueue() {
        guard renderTask == nil else { return }
        queued = queued.filter { $0.value.stamp == stamp }
        guard let next = queued.min(by: { $0.value.distance < $1.value.distance })?.key,
              let snip = itemByID[next] else { queued.removeAll(); return }
        queued[next] = nil
        let scale = min(2, traitCollection.displayScale)
        let rev = revision[next, default: 0]
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            var media: UIImage?
            if let m = snip.primaryMedia { media = await ThumbnailLoader.shared.image(for: m, maxPixel: 640) }
            let image = CardPainter.render(snip, media: media, scale: scale)
            await self?.finishRender(id: next, revision: rev, image: image)
        }
    }

    private func finishRender(id: UUID, revision rev: Int, image: CGImage?) {
        renderTask = nil
        if let image, itemByID[id] != nil {
            images[id] = CardImage(revision: rev, image: image, lastUsed: CACurrentMediaTime())
            evictImages()
            wake()
        }
        // Keep drawing until the queue is empty, one card per pass.
        if !queued.isEmpty { pumpRenderQueue() }
    }

    private func evictImages() {
        guard images.count > Self.maxCachedImages else { return }
        let onScreen = Set(live.keys.compactMap { $0.index < items.count ? items[$0.index].id : nil })
        let old = images.filter { !onScreen.contains($0.key) }.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (id, _) in old.prefix(images.count - Self.maxCachedImages) { images[id] = nil }
    }

    // MARK: Input

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            dragging = true
            velocity = .zero
            zoomAnchor = nil
        case .changed:
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            target.x -= t.x / targetZoom
            target.y -= t.y / targetZoom
        case .ended, .cancelled, .failed:
            dragging = false
            let v = g.velocity(in: self) // points per second
            velocity = reduceMotion ? .zero : CGPoint(x: -v.x / 60 / targetZoom, y: -v.y / 60 / targetZoom)
        default: break
        }
        wake()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinching = true
            pinchStartZoom = targetZoom
            velocity = .zero
        case .changed:
            let point = g.location(in: self)
            let screen = CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
            let world = CGPoint(x: target.x + screen.x / targetZoom, y: target.y + screen.y / targetZoom)
            targetZoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, pinchStartZoom * g.scale))
            target = CGPoint(x: world.x - screen.x / targetZoom, y: world.y - screen.y / targetZoom)
            zoomAnchor = (world, screen)
        default:
            pinching = false
        }
        wake()
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let point = g.location(in: self)
        if let hit = frontHits.first(where: { $0.frame.contains(point) }) { onSelect?(hit.snip) }
    }

    // MARK: Accessibility

    /// Hits ordered front to back. Sorted on demand, not every frame.
    private var frontHits: [Hit] { hits.sorted { $0.depth > $1.depth } }

    override var accessibilityElements: [Any]? {
        get {
            if let a11yElements { return a11yElements }
            var seen = Set<UUID>()
            let elements = frontHits.prefix(30).compactMap { hit -> UIAccessibilityElement? in
                guard seen.insert(hit.snip.id).inserted else { return nil }
                let element = UIAccessibilityElement(accessibilityContainer: self)
                element.accessibilityLabel = "\(hit.snip.kind.label), \(hit.snip.displayTitle)"
                element.accessibilityValue = hit.snip.isFavorite ? "Favorite" : nil
                element.accessibilityHint = "Opens details"
                element.accessibilityTraits = .button
                element.accessibilityFrameInContainerSpace = hit.frame
                return element
            }
            a11yElements = elements
            return elements
        }
        set {}
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            [UIAccessibilityCustomAction(name: "Switch to grid") { [weak self] _ in
                self?.onSwitchToGrid?()
                return true
            }]
        }
        set {}
    }

    /// Three-finger swipes move the globe, so VoiceOver users reach cards beyond the first 30.
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let step = CGSize(width: bounds.width * 0.7 / zoom, height: bounds.height * 0.7 / zoom)
        switch direction {
        case .left: target.x += step.width
        case .right: target.x -= step.width
        case .up: target.y += step.height
        case .down: target.y -= step.height
        default: return false
        }
        wake()
        return true
    }
}
