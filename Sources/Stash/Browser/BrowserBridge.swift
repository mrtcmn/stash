import AppKit
import Foundation

/// Reads the frontmost browser tab with AppleScript, for "Snip current tab" without the extension.
/// Works with Chrome, Arc, Brave, Edge, Vivaldi, Opera, Chromium and other Chromium browsers, plus Safari.
@MainActor
enum BrowserBridge {
    struct Tab {
        let browser: String
        let bundleID: String
        let url: String
        let title: String
    }

    enum Failure: LocalizedError {
        case noBrowser
        case notAuthorized(String)
        case noWindow(String)
        case script(String, String)

        var errorDescription: String? {
            switch self {
            case .noBrowser:
                String(localized: "Bring a browser window to the front first.", comment: "HUD error when the user snips a browser tab")
            case .notAuthorized(let browser):
                String(localized: "Stash isn't allowed to read \(browser)'s tabs. Enable it in System Settings › Privacy & Security › Automation.", comment: "HUD error when the user snips a browser tab; the argument is the browser name")
            case .noWindow(let browser):
                String(localized: "\(browser) has no open window.", comment: "HUD error when the user snips a browser tab; the argument is the browser name")
            case .script(let browser, let message):
                String(localized: "Couldn't read the current tab in \(browser): \(message)", comment: "HUD error when the user snips a browser tab; the arguments are the browser name and the reason")
            }
        }
    }

    /// Bundle IDs of browsers that speak Chrome's AppleScript dictionary (`active tab of front window`).
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "org.chromium.Thorium",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "ai.perplexity.comet", "net.imput.helium",
    ]

    /// Browsers that speak Safari's dictionary (`current tab of front window`).
    static let safariBrowsers: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.kagi.kagimacOS"]

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return chromiumBrowsers.contains(bundleID) || safariBrowsers.contains(bundleID)
    }

    /// The tab of the frontmost browser, or of the most recently used running browser.
    static func currentTab(preferring app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) throws -> Tab {
        let candidate: NSRunningApplication? = {
            if let app, isBrowser(app.bundleIdentifier) { return app }
            return NSWorkspace.shared.runningApplications.first { isBrowser($0.bundleIdentifier) && !$0.isHidden }
        }()
        guard let browser = candidate, let bundleID = browser.bundleIdentifier else { throw Failure.noBrowser }
        let name = browser.localizedName ?? String(localized: "the browser", comment: "Browser name in tab errors when the app has no name")

        let dialects = safariBrowsers.contains(bundleID)
            ? ["current tab of front window", "active tab of front window"]
            : ["active tab of front window", "current tab of front window"]
        var lastError: Failure = .script(name, String(localized: "unsupported browser", comment: "Reason in a tab error"))
        for tabExpression in dialects {
            let titleProperty = tabExpression.hasPrefix("current") ? "name" : "title"
            let source = """
            tell application id "\(bundleID)"
                if (count of windows) is 0 then error number -1728
                set theTab to \(tabExpression)
                return {URL of theTab, \(titleProperty) of theTab}
            end tell
            """
            do {
                let (url, title) = try run(source, browser: name)
                guard !url.isEmpty else { throw Failure.noWindow(name) }
                return Tab(browser: name, bundleID: bundleID, url: url, title: title)
            } catch let failure as Failure {
                if case .notAuthorized = failure { throw failure }
                if case .noWindow = failure { throw failure }
                lastError = failure
            }
        }
        throw lastError
    }

    private static func run(_ source: String, browser: String) throws -> (String, String) {
        guard let script = NSAppleScript(source: source) else { throw Failure.script(browser, String(localized: "invalid script", comment: "Reason in a tab error")) }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? String(localized: "error \(code)", comment: "Reason in a tab error; the argument is an AppleScript error number")
            switch code {
            case -1743: throw Failure.notAuthorized(browser)
            case -1728, -1719: throw Failure.noWindow(browser)
            default: throw Failure.script(browser, message)
            }
        }
        let url = result.atIndex(1)?.stringValue ?? result.stringValue ?? ""
        let title = result.atIndex(2)?.stringValue ?? ""
        return (url, title)
    }
}
