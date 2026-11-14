import AppKit
import SwiftUI

/// The application's scenes. The Xcode app target only hosts them, so interface code stays in this package
/// target and builds and tests with SwiftPM.
public struct LibraryAppScenes: Scene {
    @State private var model: LibrarySelectionModel

    public init() {
        // The app decides at launch which window to show (LIB-11) and never restores windows (PRV-13). AppKit's
        // saved application state would otherwise restore "no windows" after a quit with none open, and it is
        // keyed by bundle identifier, so it also overrides launches with separate preferences.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
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

        Settings {
            SettingsView(model: model)
        }

        Window(LibraryAppIdentity.name, id: LibraryAppIdentity.libraryWindow) {
            LibraryWindowView(model: model)
        }
        .defaultSize(width: 1200, height: 720)
        .defaultLaunchBehavior(model.windowGoal == .library ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        // Opening a subject that already has a window brings that window forward (PRV-4); none are restored (PRV-13).
        WindowGroup("Preview", id: LibraryAppIdentity.previewWindow, for: PreviewSubject.self) { $subject in
            PreviewWindowView(model: model, subject: subject)
        }
        .defaultSize(width: 900, height: 640)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// Names shared by the scenes and the app target.
public enum LibraryAppIdentity {
    public static let name = "Factorio Blueprint Library"
    public static let selectionWindow = "library-selection"
    public static let libraryWindow = "library"
    public static let previewWindow = "preview"
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
            Button("Import…") { model.browser.beginImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.session.libraryURL == nil || model.session.requiresRecovery)
            Button("Import from Clipboard") { model.browser.beginImport(text: LibraryPasteboard.text) }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(model.session.libraryURL == nil || model.session.requiresRecovery)
            Button("Save As TXT…") { Task { await ExportFlow.saveSelection(model.browser) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.browser.exportTarget == nil)
            Divider()
            Button("Close Library") { Task { await model.closeLibrary() } }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.session.libraryURL == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { model.browser.requestSearchFocus() }
                .keyboardShortcut("f")
                .disabled(model.session.libraryURL == nil)
        }
        CommandMenu("Library") {
            Button("Open") { Task { await model.browser.openSelection() } }
                .keyboardShortcut(.downArrow)
                .disabled(!model.browser.canOpenSelection)
            Button("Enclosing Folder") { Task { await model.browser.goUp() } }
                .keyboardShortcut(.upArrow)
                .disabled(model.session.libraryURL == nil || !model.browser.canGoUp)
            Button("Open in Preview Window") {
                if let target = model.browser.previewTarget {
                    openWindow(id: LibraryAppIdentity.previewWindow, value: target.subject)
                }
            }
            .keyboardShortcut("y")
            .disabled(model.browser.previewTarget == nil)
            Divider()
            Button("New Folder") { Task { await model.browser.newFolder() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.session.libraryURL == nil || model.session.requiresRecovery)
            Button("Rename") { model.browser.beginRename() }
                .disabled(!model.browser.canRenameSelection)
            Button("Move To…") { model.browser.moveSheetRows = model.browser.organizableSelection }
                .keyboardShortcut("m", modifiers: [.command, .control])
                .disabled(model.browser.organizableSelection.isEmpty)
            Button("Replace Source…") { model.browser.beginReplace() }
                .disabled(!model.browser.canReplaceSelection)
            Button("Move to Trash") {
                // ⌘⌫ keeps its text meaning (delete to the start of the line) while a text field has focus.
                if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
                    text.deleteToBeginningOfLine(nil)
                } else {
                    model.browser.requestDelete()
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.browser.organizableSelection.isEmpty)
            Divider()
            Button("Add Comment") { model.browser.beginComment() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(model.browser.commentScope == nil)
            Divider()
            Button("Show Listing Issues") { model.browser.showingIssues = true }
                .disabled(model.browser.issues.isEmpty)
        }
        CommandGroup(after: .sidebar) {
            ForEach(Array(InspectorTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { model.browser.inspectorTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(model.browser.commentScope == nil)
            }
        }
        SidebarCommands()
        InspectorCommands()
        PreviewCommands()
    }

    /// A choice made from the menu while no window shows selection must still surface its outcome.
    private func showSelectionIfNeeded() {
        if model.windowGoal == .selection { openWindow(id: LibraryAppIdentity.selectionWindow) }
        if model.pendingCreation != nil { openWindow(id: LibraryAppIdentity.selectionWindow) }
    }
}
