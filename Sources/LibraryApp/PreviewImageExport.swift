import AppKit
import Foundation
import UniformTypeIdentifiers

/// Copy Image and Save Image As (spec IMG-1 to IMG-6): the cached PNG exactly as rendered, never the view's
/// background or zoom. Saving follows Save As TXT's rules (EXP-4 to EXP-6).
public enum PreviewImageExport {
    /// The suggested file name: the name's text form (ICN-7) with path separators replaced, plus `.png`.
    public static func fileName(_ name: String) -> String {
        let clean = RichTextName(name).textForm.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return (clean.isEmpty ? "Preview" : clean) + ".png"
    }

    /// Writes `png` to `url`: refused inside the library (IMG-4); an existing file goes to the Trash first and comes
    /// back if writing fails (IMG-3, IMG-5); the write is atomic, so no partial file is left at `url`.
    public static func save(_ png: Data, to url: URL, library: URL?) -> ExportSaveOutcome {
        if let library, LibraryBrowserModel.isInside(url, library) { return .insideLibrary }
        var trashed: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                trashed = try ExportTrash.move(url)
            } catch {
                return .failed(
                    LibraryMessage(
                        title: "The existing file couldn't be replaced",
                        guidance: "It couldn't be moved to the Trash. Choose another name or location.",
                        technical: String(describing: error)))
            }
        }
        do {
            try png.write(to: url, options: .atomic)
            return .saved(bytes: png.count)
        } catch {
            if let trashed { try? FileManager.default.moveItem(at: trashed, to: url) }
            return .failed(
                LibraryMessage(
                    title: "The image wasn't saved",
                    guidance: "Check that you can write to that folder and that the drive has free space.",
                    technical: String(describing: error)))
        }
    }

    /// Puts the PNG on the clipboard as an image (IMG-1).
    @MainActor
    public static func copy(_ png: Data, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }
}

/// Copy Image and Save Image As for the focused preview: the inspector's or a preview window's.
@MainActor
enum PreviewImageFlow {
    static func copy(_ display: PreviewDisplay) {
        guard let png = display.png else { return }
        PreviewImageExport.copy(png)
        display.confirm("Copied preview image")
    }

    /// The save panel, then the save; a destination inside the library is explained and the panel reopens (IMG-4).
    static func save(_ display: PreviewDisplay, library: URL?) async {
        guard let png = display.png else { return }
        while let url = await choose(PreviewImageExport.fileName(display.exportName)) {
            switch PreviewImageExport.save(png, to: url, library: library) {
            case .saved:
                display.confirm("Saved “\(url.lastPathComponent)”")
                return
            case .failed(let message):
                let alert = NSAlert()
                alert.messageText = message.title
                alert.informativeText = message.guidance
                alert.runModal()
                return
            case .insideLibrary:
                let alert = NSAlert()
                alert.messageText = "Images can't be saved inside the library folder"
                alert.informativeText = "Choose another location."
                alert.addButton(withTitle: "Choose Another Location")
                alert.runModal()
            }
        }
    }

    private static func choose(_ name: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Image As"
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }
}
