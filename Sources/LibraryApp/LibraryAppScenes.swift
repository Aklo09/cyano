import SwiftUI

/// The application's scenes. The Xcode app target only hosts them, so interface code stays in this package
/// target and builds and tests with SwiftPM.
public struct LibraryAppScenes: Scene {
    @State private var model: LibrarySelectionModel

    public init() {
        _model = State(initialValue: LibrarySelectionModel(defaults: LibraryPreferences.defaults()))
    }

    public var body: some Scene {
        // At launch exactly one window is presented: the library window when the last library can be reopened
        // (LIB-11), otherwise selection. Windows are never restored from a previous run.
        Window(LibraryAppIdentity.name, id: LibraryAppIdentity.selectionWindow) {
            LibrarySelectionView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.windowGoal == .selection ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .commands { LibraryCommands(model: model) }

        Window(LibraryAppIdentity.name, id: LibraryAppIdentity.libraryWindow) {
            LibraryWindowView(model: model)
        }
        .defaultLaunchBehavior(model.windowGoal == .library ? .presented : .suppressed)
        .restorationBehavior(.disabled)
    }
}

/// Names shared by the scenes and the app target.
public enum LibraryAppIdentity {
    public static let name = "Factorio Blueprint Library"
    public static let selectionWindow = "library-selection"
    public static let libraryWindow = "library"
}

/// File menu commands for libraries (screen specs, "Menus and shortcuts"); the full set comes with A15.
struct LibraryCommands: Commands {
    let model: LibrarySelectionModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Library…") {
                Task {
                    guard let url = await LibraryPanels.chooseEmptyFolder() else { return }
                    await model.chooseFolderToCreate(url)
                    showSelectionIfNeeded()
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Open Library…") {
                Task {
                    guard let url = await LibraryPanels.chooseLibrary() else { return }
                    await model.chooseFolderToOpen(url)
                    showSelectionIfNeeded()
                }
            }
            .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recents) { row in
                    Button(row.library.name) {
                        Task {
                            await model.openRecent(row)
                            showSelectionIfNeeded()
                        }
                    }
                    .disabled(!row.available)
                }
                Divider()
                Button("Clear Menu") { model.clearRecents() }
                    .disabled(model.recents.isEmpty)
            }
            Divider()
            Button("Close Library") { Task { await model.closeLibrary() } }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.session.libraryURL == nil)
        }
    }

    /// A choice made from the menu while no window shows selection must still surface its outcome.
    private func showSelectionIfNeeded() {
        if model.windowGoal == .selection { openWindow(id: LibraryAppIdentity.selectionWindow) }
        if model.pendingCreation != nil { openWindow(id: LibraryAppIdentity.selectionWindow) }
    }
}
