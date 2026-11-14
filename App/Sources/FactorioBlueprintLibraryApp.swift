import LibraryApp
import SwiftUI

/// Bundle entry point only; everything else lives in the package's LibraryApp target.
@main
struct FactorioBlueprintLibraryApp: App {
    var body: some Scene {
        LibraryAppScenes()
    }
}
