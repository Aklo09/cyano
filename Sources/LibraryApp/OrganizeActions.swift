import Foundation
import LibraryCore
import UniformTypeIdentifiers

/// A delete waiting for confirmation (ORG-8, ORG-10).
public struct PendingDeletion: Equatable, Sendable {
    public let rows: [BrowserRow]
    public var title: String {
        guard rows.count == 1, let row = rows.first else { return "Move \(rows.count) items to the Trash?" }
        return row.kind == .folder ? "Delete the folder “\(row.name)”?" : "Move “\(row.name)” to the Trash?"
    }
    public var message: String {
        if rows.count == 1, rows.first?.kind == .folder { return "The folder is empty." }
        return rows.count == 1
            ? "Its original string and metadata go to the Trash, with its comments."
            : "Their original strings and metadata go to the Trash, with their comments."
    }
    public var actionTitle: String {
        rows.count == 1 && rows.first?.kind == .folder ? "Delete Folder" : "Move to Trash"
    }
}

extension LibraryBrowserModel {
    /// Saved items and folders that organization acts on; entries inside a book never qualify (BOOK-7).
    public var organizableSelection: [BrowserRow] {
        guard !showsBook else { return [] }
        return selectedRows.filter { $0.folderPath != nil || ($0.itemId != nil && $0.entryPath == nil) }
    }

    public var canRenameSelection: Bool { organizableSelection.count == 1 && selection.count == 1 }
    public var canReplaceSelection: Bool { canRenameSelection && organizableSelection.first?.folderPath == nil }

    /// The folder new folders go into: the current folder, or the open book's folder.
    public var organizeFolder: String { importDestination }

    // MARK: New folder and rename

    /// Creates "New Folder" (or "New Folder 2", …) in the current folder, selects it, and starts renaming (ORG-1).
    public func newFolder() async {
        guard session.libraryURL != nil else { return }
        let parent = organizeFolder
        let taken = Set(
            (listing?.folders ?? []).filter { Self.parent($0) == parent }.map { Self.lastComponent($0).lowercased() })
        var name = "New Folder"
        var counter = 2
        while taken.contains(name.lowercased()) {
            name = "New Folder \(counter)"
            counter += 1
        }
        let chosen = name
        let outcome = await session.perform(.changing) { try $0.createFolder(parent: parent, name: chosen) }
        switch outcome {
        case .success(let path):
            show(folder: parent)
            selection = ["folder:" + path]
            renamingRow = "folder:" + path
        case .failure(let message): organizeFailure = message
        case .ignored: break
        }
    }

    /// Starts renaming the selected item or folder in place (Return).
    public func beginRename() {
        guard canRenameSelection, let row = organizableSelection.first else { return }
        renameFailure = nil
        renamingRow = row.id
    }

    /// Renames a row; returns nil on success, or the reason with the field kept open (ORG-2 to ORG-5).
    @discardableResult public func rename(_ row: BrowserRow, to newName: String) async -> LibraryMessage? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == row.name {
            renamingRow = nil
            return nil
        }
        if let path = row.folderPath {
            let parent = Self.parent(path)
            let outcome = await session.perform(.changing) { try $0.moveFolder(path, parent: parent, name: name) }
            switch outcome {
            case .success(let newPath):
                renamingRow = nil
                selection = ["folder:" + newPath]
                return nil
            case .failure(let message):
                renameFailure = message
                return message
            case .ignored:
                return nil
            }
        }
        guard let itemId = row.itemId else { return nil }
        let outcome = await session.perform(.changing) { try $0.renameItem(id: itemId, name: name) }
        switch outcome {
        case .success:
            renamingRow = nil
            selection = ["item:" + itemId]
            return nil
        case .failure(let message):
            renameFailure = message
            return message
        case .ignored:
            return nil
        }
    }

    public func cancelRename() {
        renamingRow = nil
        renameFailure = nil
    }

    // MARK: Move

    /// Folders the rows can move into: not where they already are, not a moved folder or its descendants (ORG-7).
    public func moveTargets(for rows: [BrowserRow]) -> [String] {
        let folders = [""] + (listing?.folders ?? [])
        let moving = rows.compactMap(\.folderPath)
        let sources = Set(rows.map { $0.folderPath.map(Self.parent) ?? $0.folder })
        return folders.filter { target in
            !(sources.count == 1 && sources.contains(target))
                && !moving.contains { target == $0 || target.hasPrefix($0 + "/") }
        }
    }

    /// Moves rows into `target`; returns the failures, each worded for the owner (ORG-6, ORG-7).
    @discardableResult public func move(_ rows: [BrowserRow], to target: String, reveal: Bool) async -> [LibraryMessage]
    {
        var failures: [LibraryMessage] = []
        var moved: [String] = []
        for row in rows where row.entryPath == nil {
            if let path = row.folderPath {
                let outcome = await session.perform(.changing, refreshing: false) {
                    try $0.moveFolder(path, parent: target)
                }
                switch outcome {
                case .success(let newPath): moved.append("folder:" + newPath)
                case .failure(let message): failures.append(Self.named(message, row.name))
                case .ignored: return failures
                }
            } else if let itemId = row.itemId {
                let outcome = await session.perform(.changing, refreshing: false) {
                    try $0.moveItem(id: itemId, folder: target)
                }
                switch outcome {
                case .success: moved.append("item:" + itemId)
                case .failure(let message): failures.append(Self.named(message, row.name))
                case .ignored: return failures
                }
            }
        }
        await session.refresh()
        if reveal && !moved.isEmpty {
            show(folder: target)
            selection = Set(moved)
        }
        if let first = failures.first { organizeFailure = first }
        return failures
    }

    /// Rows dragged as "fb-native-row:<id>" lines, resolved against the current list.
    public func rows(fromDragged text: String) -> [BrowserRow] {
        let ids = text.split(separator: "\n").compactMap { line -> String? in
            line.hasPrefix(Self.dragPrefix) ? String(line.dropFirst(Self.dragPrefix.count)) : nil
        }
        guard case .rows(let rows) = content else { return [] }
        return rows.filter { ids.contains($0.id) && $0.entryPath == nil }
    }

    public static let dragPrefix = "fb-native-row:"

    /// What dragging a row carries: the row, or the whole selection when the row is part of it.
    public func dragPayload(for row: BrowserRow) -> String {
        let rows = selection.contains(row.id) ? organizableSelection : [row]
        return rows.filter { $0.entryPath == nil }.map { Self.dragPrefix + $0.id }.joined(separator: "\n")
    }

    /// Handles a drop on a sidebar folder: TXT files open Import (IMP-2), dragged rows move there (ORG-6).
    public func drop(_ providers: [NSItemProvider], into folder: String) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if !files.isEmpty {
            Task {
                var urls: [URL] = []
                for provider in files {
                    if let url = await Self.loadURL(provider) { urls.append(url) }
                }
                if !urls.isEmpty { beginImport(files: urls, folder: folder) }
            }
            return true
        }
        let texts = providers.filter { $0.canLoadObject(ofClass: NSString.self) }
        guard !texts.isEmpty else { return false }
        Task {
            var text = ""
            for provider in texts {
                if let part = await Self.loadString(provider) { text += part + "\n" }
            }
            let rows = rows(fromDragged: text)
            guard !rows.isEmpty, moveTargets(for: rows).contains(folder) else { return }
            await move(rows, to: folder, reveal: false)
        }
        return true
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { value, _ in continuation.resume(returning: value) }
        }
    }

    private static func loadString(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { value, _ in continuation.resume(returning: value) }
        }
    }

    // MARK: Delete

    /// Asks before moving items to the Trash or deleting an empty folder; non-empty folders are explained (ORG-8, ORG-10).
    public func requestDelete() {
        let rows = organizableSelection
        guard !rows.isEmpty else { return }
        if let folder = rows.first(where: { $0.folderPath != nil }), let path = folder.folderPath {
            guard rows.count == 1 else {
                organizeFailure = LibraryMessage(
                    title: "Folders are deleted one at a time", guidance: "Select only the empty folder to delete.")
                return
            }
            let hasContent =
                (listing?.items.contains { $0.folder == path } ?? false)
                || (listing?.folders.contains { $0.hasPrefix(path + "/") } ?? false)
            if hasContent {
                organizeFailure = LibraryMessage(
                    title: "“\(folder.name)” isn't empty", guidance: "Move or delete its items first.")
                return
            }
        }
        pendingDeletion = PendingDeletion(rows: rows)
    }

    /// Deletes the confirmed rows; reports originals the Trash refused (ORG-8 to ORG-10). The alert passes its
    /// value because dismissing it clears `pendingDeletion` before the button's action runs.
    public func confirmDelete(_ confirmed: PendingDeletion? = nil) async {
        guard let pending = confirmed ?? pendingDeletion else { return }
        pendingDeletion = nil
        var quarantined = false
        for row in pending.rows {
            if let path = row.folderPath {
                let outcome = await session.perform(.changing, refreshing: false) { try $0.deleteFolder(path) }
                if case .failure(let message) = outcome { organizeFailure = Self.named(message, row.name) }
            } else if let itemId = row.itemId {
                let outcome = await session.perform(.changing, refreshing: false) { try $0.deleteItem(id: itemId) }
                switch outcome {
                case .success(let place): quarantined = quarantined || place == .quarantine
                case .failure(let message): organizeFailure = Self.named(message, row.name)
                case .ignored: break
                }
            }
        }
        await session.refresh()
        selection = []
        if quarantined { organizeFailure = Self.quarantineNotice }
    }

    static let quarantineNotice = LibraryMessage(
        title: "The Trash couldn't accept the removed files",
        guidance: "They were kept in the library's operations-quarantine folder.")

    /// Prefixes a message with the row it concerns when several rows are involved.
    static func named(_ message: LibraryMessage, _ name: String) -> LibraryMessage {
        LibraryMessage(
            title: message.title.replacingOccurrences(of: "That name", with: "“\(name)”"), guidance: message.guidance,
            code: message.code, technical: message.technical)
    }
}

/// The Replace Source sheet: a pasted string or one file replaces the selected item's source (ORG-11 to ORG-13).
@MainActor @Observable
public final class ReplaceModel {
    public let itemId: String
    public let itemName: String
    public var text = ""
    public private(set) var file: URL?
    public private(set) var analysis: ImportModel.Analysis = .empty
    public private(set) var replacing = false
    public private(set) var failure: LibraryMessage?

    private let session: LibrarySession

    public init(session: LibrarySession, itemId: String, itemName: String, text: String = "") {
        self.session = session
        self.itemId = itemId
        self.itemName = itemName
        self.text = text
    }

    public var usesFile: Bool { file != nil }

    public func setFile(_ url: URL?) {
        file = url
        failure = nil
    }

    public var blocker: String? {
        if replacing { return "Replacing…" }
        if file != nil { return nil }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Paste a blueprint string or choose a TXT file."
        }
        switch analysis {
        case .invalid(let message): return message.title
        case .checking, .empty: return "Checking the string…"
        case .valid: return nil
        }
    }

    public func analyze() async {
        failure = nil
        let bytes = Data(text.utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            analysis = .empty
            return
        }
        analysis = .checking
        let result = await Task.detached { ImportModel.inspect(bytes) }.value
        guard bytes == Data(text.utf8) else { return }
        analysis = result
    }

    /// Replaces the source; returns the result, or nil with `failure` set and the input kept.
    public func run() async -> LibraryReplacement? {
        guard blocker == nil else { return nil }
        replacing = true
        defer { replacing = false }
        let id = itemId
        let pasted = Data(text.utf8)
        let file = file
        let outcome = await session.perform(.changing) { library -> LibraryReplacement in
            let bytes = try file.map { try NativeLibrary.readSourceFile(at: $0) } ?? pasted
            return try library.replaceSource(id: id, bytes: bytes)
        }
        switch outcome {
        case .success(let replacement): return replacement
        case .failure(let message):
            failure = message
            return nil
        case .ignored: return nil
        }
    }
}

extension LibraryBrowserModel {
    public func beginReplace(text: String = "") {
        guard canReplaceSelection, let row = organizableSelection.first, let itemId = row.itemId else { return }
        replaceSheet = ReplaceModel(session: session, itemId: itemId, itemName: row.name, text: text)
    }

    /// Runs the open Replace sheet and reports moved comments or quarantined originals (ORG-11, ORG-12, ORG-9).
    public func runReplace() async {
        guard let sheet = replaceSheet, let result = await sheet.run() else { return }
        replaceSheet = nil
        selection = ["item:" + sheet.itemId]
        switch result.promotedComments {
        case 0: confirm("Replaced")
        case 1: confirm("Replaced. 1 comment moved to the item.")
        default: confirm("Replaced. \(result.promotedComments) comments moved to the item.")
        }
        if result.originals == .quarantine { organizeFailure = Self.quarantineNotice }
    }
}
