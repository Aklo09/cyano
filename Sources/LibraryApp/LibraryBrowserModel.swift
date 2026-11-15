import Foundation
import LibraryCore
import Observation

/// What a row in the item list stands for.
public enum ItemKind: String, Sendable, CaseIterable {
    case folder
    case blueprint
    case book = "blueprint_book"
    case upgradePlanner = "upgrade_planner"
    case deconstructionPlanner = "deconstruction_planner"

    public init(stored: String) {
        self = ItemKind(rawValue: stored) ?? .blueprint
    }

    /// One label and one symbol per kind, used everywhere (screen specs, "Conventions").
    public var label: String {
        switch self {
        case .folder: "Folder"
        case .blueprint: "Blueprint"
        case .book: "Book"
        case .upgradePlanner: "Upgrade Planner"
        case .deconstructionPlanner: "Deconstruction Planner"
        }
    }

    public var symbol: String {
        switch self {
        case .folder: "folder"
        case .blueprint: "square.grid.3x3"
        case .book: "books.vertical"
        case .upgradePlanner: "arrow.up.square"
        case .deconstructionPlanner: "xmark.square"
        }
    }
}

/// One row of the item list: a subfolder or a saved item.
public struct BrowserRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: ItemKind
    /// The folder holding the row, shown in search results.
    public let folder: String
    /// For folders, the folder's own path; for items, nil.
    public let folderPath: String?
    public let itemId: String?
    public let updated: Date?
    public let created: Date?
    public let sizeBytes: Int?
    /// For entries inside an open book: their stored indices from the root book (BOOK-2).
    public var entryPath: [Int]? = nil
    /// The entry's icons in slot order (ICN-1); folders have none.
    public var icons: [EntryIcon] = []

    /// The entry's own stored index, shown in the # column.
    public var storedIndex: Int? { entryPath?.last }

    /// The name sorts by its text form, so rich-text tags never decide the order (ICN-7).
    public var sortName: String { RichTextName(name).textForm }

    static func folder(_ path: String) -> BrowserRow {
        BrowserRow(
            id: "folder:" + path, name: LibraryBrowserModel.lastComponent(path), kind: .folder,
            folder: LibraryBrowserModel.parent(path), folderPath: path, itemId: nil, updated: nil, created: nil,
            sizeBytes: nil)
    }

    static func item(_ item: LibraryItem) -> BrowserRow {
        BrowserRow(
            id: "item:" + item.id, name: item.name, kind: ItemKind(stored: item.kind), folder: item.folder,
            folderPath: nil, itemId: item.id, updated: LibraryFormat.date(item.metadata.updatedAt),
            created: LibraryFormat.date(item.metadata.createdAt), sizeBytes: item.sourceBytes, icons: item.entryIcons)
    }
}

extension BrowserRow {
    static func entry(_ entry: BlueprintEntry, itemId: String) -> BrowserRow {
        BrowserRow(
            id: "entry:" + BlueprintEntryReader.pathText(entry.path), name: BlueprintEntryReader.name(entry),
            kind: BlueprintEntryReader.kind(entry), folder: "", folderPath: nil, itemId: itemId, updated: nil,
            created: nil, sizeBytes: nil, entryPath: entry.path, icons: entry.icons)
    }
}

/// Where a path bar component leads.
public enum PathTarget: Equatable, Sendable {
    case folder(String)
    /// A book inside the open item, by stored indices ([] is the root book).
    case book([Int])
}

public struct PathComponent: Equatable, Sendable {
    public let name: String
    public let target: PathTarget
}

/// A folder in the sidebar tree; the root has the empty path.
public struct FolderNode: Identifiable, Equatable, Sendable {
    public let path: String
    public let name: String
    public var children: [FolderNode]?
    public var id: String { path }
}

/// Browsing state for the library window, derived from the session's listing (BRW-1 to BRW-10).
@MainActor @Observable
public final class LibraryBrowserModel {
    public enum SortKey: String, Sendable, CaseIterable {
        case name, kind, updated, size

        /// The column and View ▸ Sort By title.
        public var title: String {
            switch self {
            case .name: "Name"
            case .kind: "Kind"
            case .updated: "Updated"
            case .size: "Size"
            }
        }
    }

    /// What the item list area shows.
    public enum Content: Equatable {
        case loading
        case rows([BrowserRow])
        case libraryEmpty
        case folderEmpty(String)
        case noMatches(String)
        case tooLarge(LibraryMessage)
        /// An open book with no entries (BOOK-4).
        case bookEmpty
        /// An open book that could not be read.
        case bookFailed(LibraryMessage)
    }

    public let session: LibrarySession
    /// The folder being browsed; "" is the library root.
    public private(set) var folder = ""
    public var filterText = ""
    public var sortKey: SortKey = .name
    public var ascending = true
    /// Selected row IDs (`BrowserRow.id`).
    public var selection: Set<String> = []
    public var showingIssues = false
    /// Set by the Find command; the window moves focus to the search field and clears it.
    public var searchFocusRequested = false
    /// Set to move keyboard focus to the item list (Escape in the comment field).
    public var listFocusRequested = false
    /// The book shown in the item list instead of a folder's contents, if any.
    public private(set) var book: OpenBook?
    /// Details of the selected saved item, decoded on demand (version, description, settings).
    public private(set) var itemDetail: (key: String, detail: EntryDetail)?
    /// The open Import sheet, if any.
    public var importSheet: ImportModel?
    /// The row being renamed in place (`BrowserRow.id`), if any.
    public var renamingRow: String?
    /// Why the last rename failed; the field stays open with the typed text.
    public var renameFailure: LibraryMessage?
    /// Why the last organization change failed or what it could not do, shown as an alert.
    public var organizeFailure: LibraryMessage?
    /// Items or a folder waiting for delete confirmation.
    public var pendingDeletion: PendingDeletion?
    /// Rows shown in the Move To sheet.
    public var moveSheetRows: [BrowserRow]?
    /// The open Replace Source sheet.
    public var replaceSheet: ReplaceModel?
    /// The inspector tab shown for items and entries.
    public var inspectorTab: InspectorTab = .details
    /// Unsaved comment text per item or entry (`CommentScope.key`).
    public internal(set) var commentDrafts: [String: String] = [:]
    public internal(set) var addingComment = false
    /// Why the last comment change failed; shown under the field with the text kept.
    public var commentFailure: LibraryMessage?
    /// A comment waiting for "Delete this comment?".
    public var commentPendingDeletion: LibraryComment?
    /// Set by Add Comment; the inspector moves focus to the field.
    public var commentFocusRequested = false
    /// A short confirmation shown at the bottom of the window ("Copied blueprint string").
    public var confirmation: String?
    /// A failed copy or save, shown as an alert.
    public var exportFailure: LibraryMessage?
    /// Writes text to the clipboard; tests replace it.
    @ObservationIgnored public var pasteboardWriter: @MainActor (String) -> Void = LibraryPasteboard.write
    /// Files that failed in the last multi-file import, shown in a summary (IMP-3).
    public var importSummary: (imported: Int, total: Int, failures: [(name: String, reason: String)])?

    @ObservationIgnored private var lastLibrary: URL?

    public init(session: LibrarySession) {
        self.session = session
    }

    // MARK: Derived state

    public var listing: LibraryListing? { session.listing }

    public var isFiltering: Bool { !filterQuery.isEmpty }

    private var filterQuery: String { filterText.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var content: Content {
        if let book, !isFiltering {
            if let failure = book.failure { return .bookFailed(failure) }
            guard let entry = book.entry else { return .loading }
            let rows = BlueprintEntryReader.children(of: entry).map { BrowserRow.entry($0, itemId: book.itemId) }
            return rows.isEmpty ? .bookEmpty : .rows(rows)
        }
        return Self.content(
            listing: listing, failure: session.listingFailure, folder: folder, filter: filterQuery, key: sortKey,
            ascending: ascending)
    }

    /// Identifies the folder or book entry the item list shows, ignoring the filter.
    public var locationKey: String {
        if let book { return "book:" + book.itemId + ":" + book.path.map(String.init).joined(separator: ".") }
        return "folder:" + folder
    }

    /// Whether the item list shows a book's entries (columns #, Name, Kind; stored order).
    public var showsBook: Bool { book != nil && !isFiltering }

    nonisolated static func content(
        listing: LibraryListing?, failure: LibraryMessage?, folder: String, filter: String, key: SortKey,
        ascending: Bool
    ) -> Content {
        guard let listing else { return failure.map(Content.tooLarge) ?? .loading }
        if listing.items.isEmpty && listing.folders.isEmpty && filter.isEmpty { return .libraryEmpty }
        let rows = rows(listing: listing, folder: folder, filter: filter, key: key, ascending: ascending)
        if rows.isEmpty {
            if !filter.isEmpty { return .noMatches(filter) }
            if listing.items.isEmpty && folder.isEmpty { return .libraryEmpty }
            return .folderEmpty(folder.isEmpty ? "Library" : lastComponent(folder))
        }
        return .rows(rows)
    }

    /// Path bar components, root first, each with the folder or book it opens (BRW-4, BOOK-3).
    public var pathComponents: [PathComponent] {
        var result = [PathComponent(name: "Library", target: .folder(""))]
        var current = ""
        for part in folder.split(separator: "/").map(String.init) {
            current = current.isEmpty ? part : current + "/" + part
            result.append(PathComponent(name: part, target: .folder(current)))
        }
        if let book {
            for (depth, name) in book.trail.enumerated() {
                result.append(PathComponent(name: name, target: .book(Array(book.path.prefix(depth)))))
            }
        }
        return result
    }

    public var folderTree: FolderNode {
        Self.tree(folders: listing?.folders ?? [])
    }

    /// The selected folder's description from an unpacked book (BRW-7).
    public var folderDescription: String? {
        listing?.folderComments[folder]
    }

    public var issues: [(path: String, message: String)] {
        (listing?.issues ?? []).map { ($0.path, LibraryMessage.listingIssue(code: $0.code)) }
    }

    public var selectedRows: [BrowserRow] {
        guard case .rows(let rows) = content else { return [] }
        return rows.filter { selection.contains($0.id) }
    }

    public var selectedItem: LibraryItem? {
        guard selection.count == 1, let id = selection.first, id.hasPrefix("item:") else { return nil }
        let itemId = String(id.dropFirst(5))
        return listing?.items.first { $0.id == itemId }
    }

    /// The saved item that is open as a book.
    public var openBookItem: LibraryItem? {
        guard let book else { return nil }
        return listing?.items.first { $0.id == book.itemId }
    }

    /// What the inspector shows: the selected entry, or the open book itself when nothing is selected inside it,
    /// or the selected saved item once its details are loaded.
    public var selectedDetail: EntryDetail? {
        if let book, !isFiltering, let entry = book.entry {
            let bookName = book.trail.last ?? book.itemName
            if selection.count == 1, let id = selection.first, id.hasPrefix("entry:"),
                let child = BlueprintEntryReader.children(of: entry).first(where: {
                    "entry:" + BlueprintEntryReader.pathText($0.path) == id
                })
            {
                return BlueprintEntryReader.detail(child, bookName: bookName)
            }
            if selection.isEmpty {
                let detail = BlueprintEntryReader.detail(entry, bookName: book.trail.dropLast().last ?? book.itemName)
                return entry.path.isEmpty ? Self.renamed(detail, to: book.itemName) : detail
            }
            return nil
        }
        guard let item = selectedItem, let loaded = itemDetail, loaded.key == Self.detailKey(item) else { return nil }
        return loaded.detail
    }

    // MARK: Navigation

    public func show(folder path: String) {
        guard path.isEmpty || listing?.folders.contains(path) == true else { return }
        filterText = ""
        book = nil
        folder = path
        selection = []
    }

    /// Whether the single selected row is a folder or book that Open can enter.
    public var canOpenSelection: Bool {
        guard selectedRows.count == 1, let row = selectedRows.first else { return false }
        return row.folderPath != nil || row.kind == .book
    }

    /// Opens the selected folder or book (⌘↓, double-click).
    public func openSelection() async {
        guard selectedRows.count == 1, let row = selectedRows.first else { return }
        if let path = row.folderPath {
            show(folder: path)
        } else if row.kind == .book, let itemId = row.itemId {
            if let entryPath = row.entryPath, let book {
                await openBook(itemId: itemId, path: entryPath, trail: book.trail + [row.name])
            } else if let item = listing?.items.first(where: { $0.id == itemId }) {
                filterText = ""
                folder = item.folder
                await openBook(itemId: itemId, path: [], trail: [item.name])
            }
        }
    }

    /// Goes to the enclosing book or folder (⌘↑), selecting the one just left.
    public func goUp() async {
        if let book {
            if book.path.isEmpty {
                self.book = nil
                selection = ["item:" + book.itemId]
            } else {
                let left = "entry:" + BlueprintEntryReader.pathText(book.path)
                await openBook(itemId: book.itemId, path: Array(book.path.dropLast()), trail: book.trail.dropLast())
                selection = [left]
            }
            return
        }
        guard !folder.isEmpty else { return }
        let left = folder
        show(folder: Self.parent(folder))
        selection = ["folder:" + left]
    }

    public var canGoUp: Bool { book != nil || !folder.isEmpty }

    /// Follows a path bar component.
    public func navigate(to target: PathTarget) async {
        switch target {
        case .folder(let path):
            show(folder: path)
        case .book(let path):
            guard let book, path.count < book.path.count else { return }
            await openBook(itemId: book.itemId, path: path, trail: Array(book.trail.prefix(path.count + 1)))
        }
    }

    /// Decodes the selected saved item for the inspector, once per item and source.
    public func loadSelectedDetail() async {
        guard book == nil || isFiltering, let item = selectedItem else { return }
        let key = Self.detailKey(item)
        if itemDetail?.key == key { return }
        let id = item.id
        guard case .success(let entry) = await session.perform(.listing, refreshing: false, { try $0.entry(id: id) })
        else { return }
        guard selectedItem.map(Self.detailKey) == key else { return }
        itemDetail = (key, Self.renamed(BlueprintEntryReader.detail(entry), to: item.name))
    }

    private func openBook(itemId: String, path: [Int], trail: [String]) async {
        guard let item = listing?.items.first(where: { $0.id == itemId }) else { return }
        book = OpenBook(
            itemId: itemId, itemName: item.name, sourceSha256: item.metadata.sourceSha256, path: path, trail: trail,
            entry: nil, failure: nil)
        selection = []
        let outcome = await session.perform(.listing, refreshing: false) { try $0.entry(id: itemId, entryPath: path) }
        guard book?.itemId == itemId, book?.path == path else { return }
        switch outcome {
        case .success(let entry) where entry.kind == .book: book?.entry = entry
        case .success: book?.failure = LibraryMessage(title: "This entry isn't a book", guidance: "Go back up a level.")
        case .failure(let message): book?.failure = message
        case .ignored: break
        }
    }

    private static func detailKey(_ item: LibraryItem) -> String { item.id + ":" + item.metadata.sourceSha256 }

    /// The root of a saved item is shown with the item's own (possibly renamed) name.
    private static func renamed(_ detail: EntryDetail, to name: String) -> EntryDetail {
        EntryDetail(
            name: name, kind: detail.kind, version: detail.version, description: detail.description,
            settings: detail.settings, location: detail.location, entryCount: detail.entryCount, icons: detail.icons)
    }

    // MARK: Import

    /// Where imports go by default: the current folder, or the folder holding the open book (IMP-4).
    public var importDestination: String {
        openBookItem?.folder ?? folder
    }

    /// Opens the Import sheet with pasted text, files, or a drop target folder.
    public func beginImport(text: String = "", files: [URL] = [], folder target: String? = nil) {
        guard session.libraryURL != nil else { return }
        let model = ImportModel(session: session, destination: target ?? importDestination, text: text, files: files)
        importSheet = model
        if !text.isEmpty { Task { await model.analyze() } }
    }

    /// Runs the open sheet's import, closes it on success, and shows what was created (IMP-1, IMP-9, IMP-3).
    public func runImport() async {
        guard let sheet = importSheet, let result = await sheet.run() else { return }
        importSheet = nil
        switch result {
        case .imported(let items, let folders):
            reveal(items: items, folders: folders, in: sheet.destination)
        case .partial(let imported, let total, let failures, let items, let folders):
            reveal(items: items, folders: folders, in: sheet.destination)
            importSummary = (imported, total, failures)
        }
    }

    /// Shows `folder` with the given new items and folders selected.
    public func reveal(items: [String], folders: [String], in target: String) {
        filterText = ""
        book = nil
        folder = target.isEmpty || listing?.folders.contains(target) == true ? target : ""
        selection = Set(items.map { "item:" + $0 } + folders.map { "folder:" + $0 })
    }

    public func requestSearchFocus() {
        searchFocusRequested = true
    }

    public func requestListFocus() {
        listFocusRequested = true
    }

    /// Keyboard focus moved into the item list. A table draws no focus ring, so with no shown row selected the first
    /// row is selected, as in Finder; the focused list then shows it highlighted. A selection left from another folder
    /// (hidden by a search) counts as none.
    public func itemListFocusedByKeyboard() {
        guard selectedRows.isEmpty, case .rows(let rows) = content, let first = rows.first else { return }
        selection = [first.id]
    }

    /// Keeps the location and selection valid after the listing changes, and starts at the root for a new library.
    public func listingChanged() {
        if session.libraryURL != lastLibrary {
            lastLibrary = session.libraryURL
            folder = ""
            filterText = ""
            selection = []
            showingIssues = false
            book = nil
            itemDetail = nil
            return
        }
        guard let listing else { return }
        let folders = Set(listing.folders)
        while !folder.isEmpty && !folders.contains(folder) { folder = Self.parent(folder) }
        if let open = book {
            if let item = listing.items.first(where: { $0.id == open.itemId }) {
                // A move keeps the book open in its new folder; a replaced source reloads from the root book.
                folder = item.folder
                if item.metadata.sourceSha256 != open.sourceSha256 {
                    Task { await openBook(itemId: open.itemId, path: [], trail: [item.name]) }
                }
            } else {
                book = nil
                selection = []
            }
        }
        guard book == nil else { return }
        let items = Set(listing.items.map { "item:" + $0.id })
        selection = selection.filter { items.contains($0) || folders.contains(String($0.dropFirst(7))) }
    }

    // MARK: Pure helpers

    nonisolated static func rows(listing: LibraryListing, folder: String, filter: String, key: SortKey, ascending: Bool)
        -> [BrowserRow]
    {
        if !filter.isEmpty {
            let matches = listing.items.filter { $0.name.localizedStandardContains(filter) }.map(BrowserRow.item)
            return sorted(matches, key: key, ascending: ascending)
        }
        let subfolders = listing.folders.filter { parent($0) == folder && !$0.isEmpty }.map(BrowserRow.folder)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let items = listing.items.filter { $0.folder == folder }.map(BrowserRow.item)
        return subfolders + sorted(items, key: key, ascending: ascending)
    }

    nonisolated static func sorted(_ rows: [BrowserRow], key: SortKey, ascending: Bool) -> [BrowserRow] {
        rows.sorted { left, right in
            let order: ComparisonResult =
                switch key {
                case .name: left.sortName.localizedStandardCompare(right.sortName)
                case .kind: left.kind.label.localizedStandardCompare(right.kind.label)
                case .updated: compare(left.updated ?? .distantPast, right.updated ?? .distantPast)
                case .size: compare(left.sizeBytes ?? 0, right.sizeBytes ?? 0)
                }
            if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
            let byName = left.sortName.localizedStandardCompare(right.sortName)
            return byName == .orderedSame ? left.id < right.id : byName == .orderedAscending
        }
    }

    nonisolated static func tree(folders: [String]) -> FolderNode {
        func children(of parentPath: String) -> [FolderNode]? {
            let direct = folders.filter { !$0.isEmpty && parent($0) == parentPath }
                .sorted { lastComponent($0).localizedStandardCompare(lastComponent($1)) == .orderedAscending }
            guard !direct.isEmpty else { return nil }
            return direct.map { FolderNode(path: $0, name: lastComponent($0), children: children(of: $0)) }
        }
        return FolderNode(path: "", name: "Library", children: children(of: ""))
    }

    nonisolated static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    nonisolated static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    nonisolated private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
    }
}

/// Display formats for dates and sizes (screen specs, "Conventions").
public enum LibraryFormat {
    public static func date(_ stored: String) -> Date? {
        try? Date(stored, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// Medium date with short time in the Mac's time zone and format.
    public static func display(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Decimal B/KB/MB.
    public static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// The size with its exact byte count, for the inspector.
    public static func exactSize(_ bytes: Int) -> String {
        bytes < 1000 ? size(bytes) : "\(size(bytes)) (\(bytes.formatted()) bytes)"
    }
}
