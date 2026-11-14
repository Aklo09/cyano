import AppKit

/// Folder panels for library selection (screen specs, "Library selection").
@MainActor
enum LibraryPanels {
    static func chooseLibrary() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Library"
        panel.prompt = "Open"
        panel.message = "Choose a library folder, or an empty folder to create one."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return await run(panel)
    }

    static func chooseEmptyFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an Empty Folder for the New Library"
        panel.prompt = "Create Library"
        panel.message = "The library is created inside this folder. Use New Folder to make one."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return await run(panel)
    }

    private static func run(_ panel: NSOpenPanel) async -> URL? {
        await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
