import SwiftUI

struct EmptyShelf: View {
    let searching: Bool
    let board: Bool
    let paused: Bool

    var body: some View {
        ContentUnavailableView {
            Label(searching ? "No matching clips" : board ? "Empty pinboard" : paused ? "Capture paused" : "Your clipboard history", systemImage: searching ? "magnifyingglass" : board ? "pin" : "clipboard")
        } description: {
            Text(searching ? "Try a different search." : board ? "Add clips from their Pinboards menu." : paused ? "Resume capture in Fold options." : "Copy text, images, or files to see them here.")
        }
    }
}
