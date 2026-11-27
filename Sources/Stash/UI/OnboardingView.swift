import AppKit
import Combine
import SwiftUI

/// First-run guide: screen capture, the browser extension, the search engine and coding agents.
/// Nothing is required: "Get Started" works at any point.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var screenAllowed = ScreenCapturePermission.isGranted
    @State private var engine: SearchEngineChoice = .gemma
    @State private var copiedMCP = false

    private var engineDetail: LocalizedStringKey {
        switch engine {
        case .gemma: "Understands text and images in 100+ languages, fully on this Mac. One-time download of about 300 MB."
        case .apple: "Apple's built-in model. Text only, no download."
        case .off: "Matches the words you type. No model, no download."
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        Text("Welcome to ").headline(30, weight: .regular).foregroundStyle(Color(hex: 0xBDBDBD))
                        Wordmark(height: 26).foregroundStyle(Theme.ink)
                    }
                    Text("Save posts, screenshots, notes and links — then find them by meaning, privately on your Mac.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                }

                step(
                    number: 1,
                    title: "Let Stash capture the screen",
                    detail: "Needed for area, window and text (OCR) captures. Press ⌃⇧4 any time.",
                    done: screenAllowed
                ) {
                    Button(screenAllowed ? "Allowed" : "Allow Screen Recording") {
                        if !ScreenCapturePermission.request() { ScreenCapturePermission.openSystemSettings() }
                        screenAllowed = ScreenCapturePermission.isGranted
                    }
                    .disabled(screenAllowed)
                }

                step(
                    number: 2,
                    title: "Add the browser extension",
                    detail: "Works in Chrome, Arc, Brave and Edge. Save posts from X, Reddit and Pinterest with one click, and bring in your browser bookmarks.",
                    done: model.lastExtensionContact != nil
                ) {
                    Link("Add to Chrome", destination: AppResources.chromeWebStore)
                }

                step(
                    number: 3,
                    title: "Choose how search works",
                    detail: engineDetail,
                    done: false
                ) {
                    Picker("", selection: $engine) {
                        Text("EmbeddingGemma 2").tag(SearchEngineChoice.gemma)
                        Text("Apple built-in").tag(SearchEngineChoice.apple)
                        Text("Keywords only").tag(SearchEngineChoice.off)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                step(
                    number: 4,
                    title: "Ask from your terminal (optional)",
                    detail: "Claude Code, Codex and Cursor can search what you saved. Copy the command and run it in Terminal.",
                    done: copiedMCP
                ) {
                    Button(copiedMCP ? "Copied" : "Copy Command") {
                        Pasteboard.copy(text: model.mcpInstallCommand)
                        copiedMCP = true
                    }
                }

                Divider().opacity(0.4)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        @Bindable var settings = model.settings
                        Toggle("Share anonymous usage data", isOn: $settings.shareUsageData)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Text("Only counts, such as “screenshot saved”. Never your snips, URLs or searches.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    Spacer()
                    Button("Get Started") { finish(with: engine) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accentStrong)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(.glass)
            .padding(30)
            .frame(width: 620)
            .glassEffect(.regular.tint(Theme.panel.opacity(0.65)), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .onAppear { if model.settings.didOnboard { engine = model.settings.searchEngine } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenAllowed = ScreenCapturePermission.isGranted
        }
    }

    private func finish(with engine: SearchEngineChoice) {
        model.settings.searchEngine = engine
        withAnimation(.easeOut(duration: 0.25)) { model.finishOnboarding() }
    }

    private func step<Actions: View>(number: Int, title: LocalizedStringKey, detail: LocalizedStringKey, done: Bool, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color(hex: 0x7EE0B5) : Theme.accent.opacity(0.18))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                actions().padding(.top, 4)
            }
        }
    }
}
