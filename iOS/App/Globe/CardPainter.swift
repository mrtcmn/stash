import UIKit
import SwiftUI
import StashCore

/// Draws a globe card with Core Graphics, off the main thread. The image includes the rounded
/// corners and the drop shadow, so the layer needs no shadow, corner mask or offscreen pass.
enum CardPainter {
    /// Card size in points.
    static let size = CGSize(width: 320, height: 240)
    /// Transparent margin around the card that holds the shadow.
    static let margin: CGFloat = 36
    static let canvas = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
    private static let radius: CGFloat = 34
    private static let inset: CGFloat = 22

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    private static let surface = color(0x151515)
    private static let ink = color(0xF2F2F2)
    private static let secondary = color(0xABABAB)
    private static let tertiary = color(0xA6A6A6)
    private static let favorite = color(0xFFD68A)

    private static func tint(_ kind: SnipKind) -> UIColor {
        switch kind {
        case .tweet, .text: color(0xC7C7CC)
        case .screenshot: color(0x9FF0D4)
        case .note: color(0xFFD68A)
        case .link: color(0xC5B8FF)
        case .image: color(0xFFB3C7)
        }
    }

    private static func format(_ scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = false
        return f
    }

    private static var cardRect: CGRect { CGRect(origin: CGPoint(x: margin, y: margin), size: size) }

    /// An empty card shown while the real one draws.
    static func placeholder(scale: CGFloat) -> CGImage? {
        UIGraphicsImageRenderer(size: canvas, format: format(scale)).image { ctx in
            drawBase(ctx.cgContext, tint: nil)
        }.cgImage
    }

    static func render(_ snip: Snip, media: UIImage? = nil, scale: CGFloat) -> CGImage? {
        UIGraphicsImageRenderer(size: canvas, format: format(scale)).image { ctx in
            let g = ctx.cgContext
            let tint = tint(snip.kind)
            drawBase(g, tint: tint)
            if let media { drawMedia(g, media) }

            let content = cardRect.insetBy(dx: inset, dy: inset)
            var y = content.minY

            // Header: kind symbol and label, favorite star on the right.
            let header = UIFont.systemFont(ofSize: 11, weight: .medium)
            if let symbol = UIImage(systemName: Theme.symbol(for: snip.kind),
                                    withConfiguration: UIImage.SymbolConfiguration(font: header))?
                .withTintColor(tint, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: content.minX, y: y))
                draw(snip.kind.label, font: header, color: tint, in: CGRect(x: content.minX + symbol.size.width + 6, y: y, width: 150, height: 16), lines: 1)
            }
            if snip.isFavorite,
               let star = UIImage(systemName: "star.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12))?
                .withTintColor(favorite, renderingMode: .alwaysOriginal) {
                star.draw(at: CGPoint(x: content.maxX - star.size.width, y: y))
            }
            y += 26

            // Title.
            let titleFont = UIFont.systemFont(ofSize: 17, weight: .medium)
            y += draw(snip.displayTitle, font: titleFont, color: ink, kern: -17 * 0.035,
                      in: CGRect(x: content.minX, y: y, width: content.width, height: 0), lines: 3) + 10

            // Domain pinned to the bottom.
            let footFont = UIFont.systemFont(ofSize: 11)
            let footHeight = footFont.lineHeight.rounded(.up)
            let footTop = content.maxY - footHeight
            if let domain = snip.domain {
                draw(domain, font: footFont, color: tertiary, in: CGRect(x: content.minX, y: footTop, width: content.width, height: footHeight), lines: 1)
            }

            // Summary fills what is left.
            if let summary = snip.link?.summary ?? (snip.body.isEmpty ? nil : snip.body) {
                let font = UIFont.systemFont(ofSize: 13.5)
                let room = footTop - 8 - y
                let lines = min(3, Int(room / font.lineHeight))
                if lines > 0 {
                    draw(summary, font: font, color: secondary, in: CGRect(x: content.minX, y: y, width: content.width, height: 0), lines: lines)
                }
            }
        }.cgImage
    }

    /// Fills the card with the picture (aspect fill), then darkens it so the text stays readable.
    private static func drawMedia(_ g: CGContext, _ image: UIImage) {
        let rect = cardRect
        g.saveGState()
        g.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        g.clip()
        let k = max(rect.width / image.size.width, rect.height / image.size.height)
        let w = image.size.width * k, h = image.size.height * k
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        gradient(g, [UIColor.black.withAlphaComponent(0.55), UIColor.black.withAlphaComponent(0.15), UIColor.black.withAlphaComponent(0.70)], in: rect)
        g.restoreGState()
    }

    /// Shadow, glass fill, tint wash and rim light.
    private static func drawBase(_ g: CGContext, tint: UIColor?) {
        let rect = cardRect
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath

        // Shadow from an opaque shape, then clear the inside so the glass stays translucent.
        g.saveGState()
        g.setShadow(offset: CGSize(width: 0, height: 10), blur: 14, color: UIColor.black.withAlphaComponent(0.38).cgColor)
        g.addPath(path)
        g.setFillColor(surface.cgColor)
        g.fillPath()
        g.restoreGState()
        g.saveGState()
        g.addPath(path)
        g.clip()
        g.setBlendMode(.clear)
        g.fill(rect)
        g.restoreGState()

        g.saveGState()
        g.addPath(path)
        g.clip()
        g.setFillColor(surface.withAlphaComponent(0.72).cgColor)
        g.fill(rect)
        gradient(g, [UIColor.white.withAlphaComponent(0.10), UIColor.white.withAlphaComponent(0.02), UIColor.white.withAlphaComponent(0.045)], in: rect)
        if let tint {
            g.setFillColor(tint.withAlphaComponent(0.06).cgColor)
            g.fill(rect)
        }
        g.restoreGState()

        // Rim: a 1 pt stroke filled with a gradient.
        g.saveGState()
        g.addPath(path)
        g.setLineWidth(1)
        g.replacePathWithStrokedPath()
        g.clip()
        gradient(g, [UIColor.white.withAlphaComponent(0.30), color(0xE4E4E4, 0.12), UIColor.white.withAlphaComponent(0.05)], in: rect)
        g.restoreGState()
    }

    private static func gradient(_ g: CGContext, _ colors: [UIColor], in rect: CGRect) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        g.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    }

    /// Draws text clipped to `lines` lines and returns the height used.
    @discardableResult
    private static func draw(_ text: String, font: UIFont, color: UIColor, kern: CGFloat = 0, in rect: CGRect, lines: Int) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: style])
        let maxHeight = font.lineHeight.rounded(.up) * CGFloat(lines)
        let bounds = attributed.boundingRect(with: CGSize(width: rect.width, height: maxHeight), options: [.usesLineFragmentOrigin], context: nil)
        let height = min(maxHeight, bounds.height.rounded(.up))
        attributed.draw(with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return height
    }
}
