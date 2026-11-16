import AppKit
import StashCore
import SwiftUI

/// Where a capture came from, for naming the snip.
struct CaptureContext {
    var appName: String?
    var windowTitle: String?

    var title: String {
        if let windowTitle, !windowTitle.isEmpty, let appName { return "\(appName) — \(windowTitle)" }
        return appName ?? String(localized: "Screenshot", comment: "Default title of a screenshot when the app is not known")
    }
}

/// Runs screenshot, window, full-screen and text (OCR) captures.
@MainActor
final class CaptureCoordinator {
    private weak var model: AppModel?
    private var session: SelectionSession?
    private var isStarting = false

    init(model: AppModel) {
        self.model = model
    }

    func begin(_ mode: CaptureMode) {
        guard session == nil, !isStarting, let model else { return }
        guard ensurePermission() else { return }
        isStarting = true

        let front = NSWorkspace.shared.frontmostApplication
        let isSelf = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let appName = isSelf ? nil : front?.localizedName
        model.capturePreview.close()

        Task {
            defer { isStarting = false }
            do {
                let frozen = try await ScreenCapturer.freezeScreens(excluding: model.transientWindowNumbers)
                if mode == .screen {
                    let mouse = NSEvent.mouseLocation
                    let index = frozen.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
                    await deliver(frozen[index].image, action: .standard, context: CaptureContext(appName: appName))
                    return
                }
                let windows = ScreenCapturer.visibleWindows()
                let session = SelectionSession(frozen: frozen, windows: windows, mode: mode) { [weak self] outcome in
                    guard let self else { return }
                    self.session = nil
                    guard let outcome else {
                        if !isSelf { _ = front?.activate() }
                        return
                    }
                    let (result, action) = outcome
                    Task { await self.complete(result, action: action, frozen: frozen, appName: appName, previousApp: isSelf ? nil : front) }
                }
                self.session = session
                session.begin()
            } catch {
                HUD.shared.error(String(localized: "Capture failed: \(error.localizedDescription)", comment: "HUD error; the argument is the reason"))
            }
        }
    }

    private func ensurePermission() -> Bool {
        if ScreenCapturePermission.isGranted { return true }
        if ScreenCapturePermission.request() { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Allow Stash to record the screen", comment: "Alert title when Screen Recording access is missing")
        alert.informativeText = String(localized: "Stash needs Screen Recording access to take screenshots. Turn it on in System Settings › Privacy & Security › Screen & System Audio Recording, then try again.", comment: "Alert text when Screen Recording access is missing")
        alert.addButton(withTitle: String(localized: "Open System Settings", comment: "Alert button: opens the Screen Recording privacy settings"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Alert button"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCapturePermission.openSystemSettings()
        }
        return false
    }

    private func complete(_ result: SelectionResult, action: CaptureAction, frozen: [FrozenScreen], appName: String?, previousApp: NSRunningApplication?) async {
        var context = CaptureContext(appName: appName)
        let image: CGImage?
        switch result {
        case .region(let index, let rect):
            image = ScreenCapturer.crop(frozen[index], to: rect)
        case .window(let info, let index):
            context = CaptureContext(appName: info.appName, windowTitle: info.title)
            if let clean = try? await ScreenCapturer.capture(windowID: info.id) {
                image = clean
            } else {
                image = ScreenCapturer.crop(frozen[index], to: ScreenCoordinates.local(info.cgFrame, in: frozen[index].frame))
            }
        case .screen(let index):
            image = frozen[index].image
        }
        guard let image else {
            HUD.shared.error(String(localized: "Nothing was captured.", comment: "HUD error after a capture"))
            return
        }
        // Give focus back to where the user was, unless we open a window of our own.
        if action != .annotate, previousApp != nil, model?.libraryIsKey != true {
            _ = previousApp?.activate()
        }
        await deliver(image, action: action, context: context)
    }

    /// Hands a captured image to the chosen destination.
    func deliver(_ image: CGImage, action: CaptureAction, context: CaptureContext) async {
        guard let model else { return }
        let settings = model.settings
        var resolved = action
        if action == .standard {
            switch settings.afterCapture {
            case .saveAndCopy, .save, .copy: resolved = .standard
            case .annotate: resolved = .annotate
            }
        }
        if settings.playCaptureSound && resolved != .ocr { CaptureSound.play() }

        switch resolved {
        case .ocr:
            let text = await TextRecognizer.recognize(image)
            guard !text.isEmpty else {
                HUD.shared.error(String(localized: "No text found in the selection.", comment: "HUD error after a text (OCR) capture"))
                return
            }
            Pasteboard.copy(text: text)
            let lines = text.split(whereSeparator: \.isNewline).count
            HUD.shared.show(
                lines == 1
                    ? String(localized: "Copied 1 line of text", comment: "HUD after a text (OCR) capture")
                    : String(localized: "Copied \(lines) lines of text", comment: "HUD after a text (OCR) capture; the argument is the line count"),
                symbol: "text.viewfinder"
            )
            if settings.saveTextCaptures {
                await model.saveTextCapture(text, image: image, context: context)
            }
        case .copy:
            Pasteboard.copy(image: image)
            HUD.shared.show(String(localized: "Copied to clipboard", comment: "HUD after an image is copied to the clipboard"), symbol: "doc.on.doc.fill")
        case .save:
            if let snip = await model.saveScreenshot(image, context: context) {
                showPreview(image, snip: snip)
            }
        case .annotate:
            model.openEditor(image: image, context: context, snipID: nil)
        case .pin:
            PinnedImageController.shared.pin(image)
        case .standard:
            let copy = settings.afterCapture != .save
            let save = settings.afterCapture != .copy
            if copy { Pasteboard.copy(image: image) }
            if save, let snip = await model.saveScreenshot(image, context: context) {
                showPreview(image, snip: snip)
            } else if copy {
                HUD.shared.show(String(localized: "Copied to clipboard", comment: "HUD after an image is copied to the clipboard"), symbol: "doc.on.doc.fill")
            }
        }
    }

    private func showPreview(_ image: CGImage, snip: Snip) {
        guard let model else { return }
        if model.settings.showCapturePreview {
            model.capturePreview.show(image: image, snipID: snip.id)
        } else {
            HUD.shared.show(String(localized: "Saved to Stash", comment: "HUD after a screenshot is saved"), symbol: "checkmark.circle.fill")
        }
    }
}

/// Copies the color under the pointer as hex.
@MainActor
enum ScreenColorPicker {
    private static var sampler: NSColorSampler?

    static func pick() {
        let sampler = NSColorSampler()
        Self.sampler = sampler
        sampler.show { color in
            MainActor.assumeIsolated {
                Self.sampler = nil
                guard let color = color?.usingColorSpace(.sRGB) else { return }
                let hex = String(
                    format: "#%02X%02X%02X",
                    Int((color.redComponent * 255).rounded()),
                    Int((color.greenComponent * 255).rounded()),
                    Int((color.blueComponent * 255).rounded())
                )
                Pasteboard.copy(text: hex)
                HUD.shared.show(String(localized: "Copied \(hex)", comment: "HUD after the color picker copies a color; the argument is a hex code such as #FF0000"), swatch: Color(nsColor: color))
            }
        }
    }
}
