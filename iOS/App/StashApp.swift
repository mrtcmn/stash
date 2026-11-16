import SwiftUI

@main
struct StashApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Dark-only on purpose, like the Mac app: the theme has no light variant.
                .preferredColorScheme(.dark)
        }
    }
}
