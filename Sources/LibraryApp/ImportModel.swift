import Foundation
import LibraryCore
import Observation

/// One import sheet: pasted text or TXT files saved into a folder as items, or books unpacked into folders
/// (spec IMP-1 to IMP-12; screen specs, "Import").
@MainActor @Observable
public final class ImportModel {
    public enum Source: String, Sendable { case paste, files }
    public enum Mode: String, Sendable { case oneBook, unpack }

    /// What the pasted string is, shown under the source as soon as it changes.
    public enum Analysis: Equatable, Sendable {
        case empty
        case checking
        case valid(kind: ItemKind, entries: Int?, label: String?)
        case invalid(LibraryMessage)
    }

    /// The outcome of Import.
    public enum Result: Equatable {
        /// Created items (by ID) and unpacked top folders (by path), in the order imported.
        case imported(items: [String], folders: [String])
        /// Some files failed; the others stay imported (IMP-3).
        case partial(
            imported: Int, total: Int, failures: [(name: String, reason: String)], items: [String], folders: [String])

        public static func == (left: Result, right: Result) -> Bool {
            switch (left, right) {
            case (.imported(let a, let b), .imported(let c, let d)): a == c && b == d
            case (.partial(let a, let b, let c, let d, let e), .partial(let f, let g, let h, let i, let j)):
                a == f && b == g && c.map(\.name) == h.map(\.name) && c.map(\.reason) == h.map(\.reason) && d == i
                    && e == j
            default: false
            }
        }
    }

    public var source: Source
    public var text: String
    public private(set) var files: [URL]
    public var name = ""
    public var destination: String
    public var mode: Mode = .oneBook
    public private(set) var analysis: Analysis = .empty
    public private(set) var importing = false
    /// A problem shown in the sheet, with everything entered kept.
    public private(set) var failure: LibraryMessage?

    private let session: LibrarySession

    public init(session: LibrarySession, destination: String, text: String = "", files: [URL] = []) {
        self.session = session
        self.destination = destination
        self.text = text
        self.files = files
        source = files.isEmpty ? .paste : .files
    }

    /// The bytes that will be saved for pasted text: exactly the text, whitespace and line endings included.
    public var pastedBytes: Data { Data(text.utf8) }

    /// Names are optional and apply to one pasted string or one file saved as one item (IMP-5).
    public var acceptsName: Bool {
        mode == .oneBook && (source == .paste || files.count == 1)
    }

    /// Why Import is disabled, or nil when it can run.
    public var blocker: String? {
        if importing { return "Importing…" }
        switch source {
        case .paste:
            if text.isEmpty { return "Paste a blueprint string or choose TXT files." }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "The pasted text is empty."
            }
            switch analysis {
            case .invalid(let message): return message.title
            case .valid(let kind, _, _) where mode == .unpack && kind != .book: return "Only books can be unpacked."
            case .checking, .empty: return "Checking the string…"
            case .valid: return nil
            }
        case .files:
            return files.isEmpty ? "Paste a blueprint string or choose TXT files." : nil
        }
    }

    public var importTitle: String {
        source == .files && files.count > 1 ? "Import \(files.count) Files" : "Import"
    }

    public func setFiles(_ urls: [URL]) {
        files = urls
        source = urls.isEmpty ? .paste : .files
        failure = nil
    }

    /// Decodes the pasted text off the main thread; called whenever it changes.
    public func analyze() async {
        failure = nil
        let bytes = pastedBytes
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            analysis = .empty
            return
        }
        analysis = .checking
        let result = await Task.detached { Self.inspect(bytes) }.value
        guard bytes == pastedBytes else { return }
        analysis = result
    }

    /// Saves the source. Returns nil when nothing was imported; `failure` then says why.
    public func run() async -> Result? {
        guard blocker == nil else { return nil }
        importing = true
        defer { importing = false }
        failure = nil
        switch source {
        case .paste:
            switch await save(pastedBytes, name: acceptsName ? trimmedName : nil) {
            case .success(let created):
                await session.refresh()
                return .imported(items: created.item.map { [$0] } ?? [], folders: created.folder.map { [$0] } ?? [])
            case .failure(let message):
                failure = message
                return nil
            }
        case .files:
            var items: [String] = []
            var folders: [String] = []
            var failures: [(name: String, reason: String)] = []
            for url in files {
                let bytes: Data
                switch await session.perform(
                    .importing, refreshing: false, { _ in try NativeLibrary.readSourceFile(at: url) })
                {
                case .success(let read): bytes = read
                case .failure(let message):
                    failures.append((url.lastPathComponent, message.title))
                    continue
                case .ignored: return nil
                }
                switch await save(bytes, name: acceptsName ? trimmedName : nil) {
                case .success(let created):
                    if let item = created.item { items.append(item) }
                    if let folder = created.folder { folders.append(folder) }
                case .failure(let message):
                    failures.append((url.lastPathComponent, message.title))
                }
            }
            await session.refresh()
            if failures.isEmpty { return .imported(items: items, folders: folders) }
            if items.isEmpty && folders.isEmpty && files.count == 1 {
                failure = LibraryMessage(title: failures[0].reason, guidance: "Nothing was imported.")
                return nil
            }
            return .partial(
                imported: files.count - failures.count, total: files.count, failures: failures, items: items,
                folders: folders)
        }
    }

    private var trimmedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum Saved {
        case success((item: String?, folder: String?))
        case failure(LibraryMessage)
    }

    /// Checks one source and saves it as one item or unpacks it, without refreshing the listing.
    private func save(_ bytes: Data, name: String?) async -> Saved {
        let checked = await Task.detached { Self.inspect(bytes) }.value
        switch checked {
        case .invalid(let message): return .failure(message)
        case .empty:
            return .failure(
                LibraryMessage(title: "The file is empty", guidance: "Choose a file with a blueprint string."))
        case .valid(let kind, _, _) where mode == .unpack && kind != .book:
            return .failure(
                LibraryMessage(title: "Only books can be unpacked", guidance: "Save it as one item instead."))
        default: break
        }
        let folder = destination
        let unpack = mode == .unpack
        let outcome = await session.perform(.importing, refreshing: false) { library -> (String?, String?) in
            if unpack { return (nil, try library.importUnpacked(bytes, folder: folder).folder) }
            return (try library.importSource(bytes, name: name, folder: folder).id, nil)
        }
        switch outcome {
        case .success(let created): return .success((created.0, created.1))
        case .failure(let message): return .failure(message)
        case .ignored:
            return .failure(LibraryMessage(title: "The library closed", guidance: "Open it again to import."))
        }
    }

    /// Decodes bytes to tell the owner what they are (IMP-7, IMP-8).
    nonisolated static func inspect(_ bytes: Data) -> Analysis {
        guard !bytes.isEmpty else { return .empty }
        do {
            let document = try BlueprintCodec.decode(bytes)
            let kind = ItemKind(stored: document.root.kind.rawValue)
            let entries = kind == .book ? BlueprintEntryReader.children(of: document.root).count : nil
            return .valid(kind: kind, entries: entries, label: document.root.label)
        } catch {
            return .invalid(
                LibraryMessage.describing(error, activity: .importing)
                    ?? LibraryMessage(title: "This isn't a blueprint string", guidance: "Copy it again from the game."))
        }
    }
}
