import SwiftUI

/// The application's scenes. The Xcode app target only hosts them, so interface code stays in this package
/// target and builds and tests with SwiftPM.
public struct LibraryAppScenes: Scene {
    public init() {}

    public var body: some Scene {
        Window(LibraryAppIdentity.name, id: LibraryAppIdentity.selectionWindow) {
            LibrarySelectionPlaceholder()
        }
        .windowResizability(.contentSize)
    }
}

/// Names shared by the scenes and the app target.
public enum LibraryAppIdentity {
    public static let name = "Factorio Blueprint Library"
    public static let selectionWindow = "library-selection"
}

/// Stands in for library selection (milestone 3, A5) so the scaffold launches to a real window.
struct LibrarySelectionPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(LibraryAppIdentity.name)
                .font(.title2.weight(.semibold))
            Text("Opening and creating libraries comes in a later build.")
        }
        .padding(32)
        .frame(minWidth: 420)
    }
}
