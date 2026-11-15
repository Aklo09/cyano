import AppKit
import Foundation
import LibraryCore

/// What Copy String and Save As TXT act on: a saved item's root, or an entry inside an open book.
public struct ExportTarget: Equatable, Sendable {
    public let itemId: String
    public let entryPath: [Int]
    public let name: String

    /// The proposed file name: the text form of the item or entry name (ICN-7) with path separators replaced, plus
    /// `.txt`.
    public var fileName: String {
        let clean = RichTextName(name).textForm.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return (clean.isEmpty ? "Blueprint" : clean) + ".txt"
    }
}

/// The result of Save As TXT.
public enum ExportSaveOutcome: Equatable, Sendable {
    case saved(bytes: Int)
    /// The destination is inside the open library (EXP-5); nothing was written.
    case insideLibrary
    /// Nothing was saved and any replaced file is back in place (EXP-6).
    case failed(LibraryMessage)
}

/// Moves a replaced export to the Trash, honoring the test redirect the library uses.
enum ExportTrash {
    static func move(_ url: URL) throws -> URL {
        if let override = ProcessInfo.processInfo.environment["FB_NATIVE_TRASH_DIRECTORY"], override.hasPrefix("/") {
            let directory = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(UUID().uuidString) \(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return (trashed as URL?) ?? url
    }
}

extension LibraryBrowserModel {
    /// The selected item, or the selected entry inside an open book; nil for none or several (EXP-1, EXP-2).
    public var exportTarget: ExportTarget? {
        guard selectedRows.count == 1, let row = selectedRows.first, let itemId = row.itemId else { return nil }
        return ExportTarget(itemId: itemId, entryPath: row.entryPath ?? [], name: row.name)
    }

    /// Copies the exact root string, or an entry's standalone string, to the clipboard (EXP-1, EXP-2).
    public func copySelectedString() async {
        guard let target = exportTarget else { return }
        let outcome = await session.perform(.exporting, refreshing: false) {
            try $0.export(id: target.itemId, entryPath: target.entryPath)
        }
        switch outcome {
        case .success(let bytes):
            guard let text = String(data: bytes, encoding: .utf8) else {
                exportFailure = LibraryMessage(
                    title: "The string can't be copied", guidance: "It isn't valid text. Save it as a TXT file instead."
                )
                return
            }
            pasteboardWriter(text)
            confirm("Copied blueprint string")
        case .failure(let message): exportFailure = message
        case .ignored: break
        }
    }

    /// Writes the target's bytes to `url`, which the save panel already confirmed (EXP-3 to EXP-6).
    public func save(_ target: ExportTarget, to url: URL) async -> ExportSaveOutcome {
        if let library = session.libraryURL, Self.isInside(url, library) { return .insideLibrary }
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
        let outcome = await session.perform(.exporting, refreshing: false) {
            try $0.export(id: target.itemId, entryPath: target.entryPath, to: url)
        }
        switch outcome {
        case .success(let count):
            confirm("Saved “\(url.lastPathComponent)”")
            return .saved(bytes: count)
        case .failure(let message):
            if let trashed { try? FileManager.default.moveItem(at: trashed, to: url) }
            if message.code == NativeLibraryError.unsafePath.code { return .insideLibrary }
            return .failed(
                LibraryMessage(
                    title: "The file wasn't saved", guidance: message.guidance, code: message.code,
                    technical: message.technical))
        case .ignored:
            if let trashed { try? FileManager.default.moveItem(at: trashed, to: url) }
            return .failed(LibraryMessage(title: "The file wasn't saved", guidance: "The library closed."))
        }
    }

    /// Shows a short confirmation at the bottom of the window, also announced to VoiceOver.
    public func confirm(_ text: String) {
        confirmation = text
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.confirmation == text { self?.confirmation = nil }
        }
    }

    static func isInside(_ url: URL, _ library: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let root = library.standardizedFileURL.resolvingSymlinksInPath().path
        return parent == root || parent.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}

/// The Save As TXT panel.
@MainActor
enum ExportPanel {
    static func choose(_ target: ExportTarget) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save As TXT"
        panel.nameFieldStringValue = target.fileName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }
}

/// Save As TXT from a menu or button: the panel, then the save; a destination inside the library is explained and
/// the panel reopens (EXP-5).
@MainActor
enum ExportFlow {
    static func saveSelection(_ browser: LibraryBrowserModel) async {
        guard let target = browser.exportTarget else { return }
        while let url = await ExportPanel.choose(target) {
            switch await browser.save(target, to: url) {
            case .saved: return
            case .failed(let message):
                browser.exportFailure = message
                return
            case .insideLibrary:
                let alert = NSAlert()
                alert.messageText = "Exports can't be saved inside the library folder"
                alert.informativeText = "Choose another location."
                alert.addButton(withTitle: "Choose Another Location")
                alert.runModal()
            }
        }
    }
}
