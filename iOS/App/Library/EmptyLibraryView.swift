import SwiftUI

struct EmptyLibraryView: View {
    var searching = false

    var body: some View {
        if searching {
            ContentUnavailableView.search
        } else if let error = SharedStore.shared.openError {
            ContentUnavailableView("Cannot open the library", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView(
                "Nothing saved yet",
                systemImage: "square.and.arrow.up",
                description: Text("Tap Share in Safari, X or any app, then choose Stash.")
            )
        }
    }
}
