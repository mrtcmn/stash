import SwiftUI
import StashCore

/// Visual language ported from the macOS Theme: graphite field, neutral surfaces.
/// The app is dark-only on purpose, like the Mac app. The graphite field and the glass surfaces
/// have no light variant, so every scene forces the dark scheme. Increased contrast is honored
/// through `\.colorSchemeContrast` where strokes are drawn.
enum Theme {
    static let ink = Color(hex: 0xF2F2F2)
    static let inkSecondary = Color(hex: 0xABABAB)
    static let inkTertiary = Color(hex: 0xA6A6A6)
    static let accent = Color(hex: 0xE4E4E4)
    static let accentStrong = Color(hex: 0xCFCFCF)
    static let danger = Color(hex: 0xFF9BA7)

    static let fieldTop = Color(hex: 0x1C1C1E)
    static let fieldBottom = Color(hex: 0x000000)
    static let surface = Color(hex: 0x151515)
    static let panel = Color(hex: 0x121212)

    static var fieldGradient: LinearGradient {
        LinearGradient(
            stops: [.init(color: fieldTop, location: 0), .init(color: fieldBottom, location: 0.74)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let cardRadius: CGFloat = 26
    static let tileRadius: CGFloat = 34
    static let controlRadius: CGFloat = 22

    static func tint(for kind: SnipKind) -> Color {
        switch kind {
        case .tweet, .text: Color(hex: 0xC7C7CC)
        case .screenshot: Color(hex: 0x9FF0D4)
        case .note: Color(hex: 0xFFD68A)
        case .link: Color(hex: 0xC5B8FF)
        case .image: Color(hex: 0xFFB3C7)
        }
    }

    static func symbol(for kind: SnipKind) -> String {
        switch kind {
        case .tweet: "bubble.left.and.text.bubble.right"
        case .screenshot: "camera.viewfinder"
        case .note: "note.text"
        case .link: "link"
        case .image: "photo"
        case .text: "text.quote"
        }
    }

    static let favorite = Color(hex: 0xFFD68A)
    static let verified = Color(hex: 0x8ECBFF)

    /// Text style for a design size, so text follows Dynamic Type.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<13.5: .footnote
        case ..<14.5: .subheadline
        case ..<16.5: .callout
        case ..<18: .body
        case ..<21: .title3
        case ..<23: .title2
        default: .title
        }
    }

    /// System font that scales with Dynamic Type. The size picks the text style.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size), weight: weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// Display heading with the tight tracking used on macOS.
    func headline(_ size: CGFloat, _ weight: Font.Weight = .medium) -> some View {
        font(Theme.font(size, weight)).tracking(-size * 0.035)
    }
}

/// Graphite field plus three blurred circles and a bottom darkening gradient.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Theme.fieldGradient
            Circle().fill(Color(hex: 0x3A3A3C, opacity: 0.35)).frame(width: 720, height: 720)
                .blur(radius: 140).offset(x: -190, y: -180)
            Circle().fill(Color(hex: 0x5A5A5C, opacity: 0.14)).frame(width: 560, height: 560)
                .blur(radius: 150).offset(x: 280, y: 290)
            Circle().fill(Color(hex: 0x2C2C2E, opacity: 0.10)).frame(width: 480, height: 480)
                .blur(radius: 160).offset(x: 190, y: -250)
            LinearGradient(stops: [.init(color: .clear, location: 0.7), .init(color: .black.opacity(0.35), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
