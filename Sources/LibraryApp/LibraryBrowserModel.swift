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
            created: LibraryFormat.date(item.metadata.createdAt), sizeBytes: item.sourceBytes)
    }
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
    public enum SortKey: String, Sendable, CaseIterable { case name, kind, updated, size }

    /// What the item list area shows.
    public enum Content: Equatable {
        case loading
        case rows([BrowserRow])
        case libraryEmpty
        case folderEmpty(String)
        case noMatches(String)
        case tooLarge(LibraryMessage)
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

    @ObservationIgnored private var lastLibrary: URL?

    public init(session: LibrarySession) {
        self.session = session
    }

    // MARK: Derived state

    public var listing: LibraryListing? { session.listing }

    public var isFiltering: Bool { !filterQuery.isEmpty }

    private var filterQuery: String { filterText.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var content: Content {
        Self.content(
            listing: listing, failure: session.listingFailure, folder: folder, filter: filterQuery, key: sortKey,
            ascending: ascending)
    }

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

    /// Path bar components, root first, each with the folder it opens (BRW-4).
    public var pathComponents: [(name: String, folder: String)] {
        var result = [(name: "Library", folder: "")]
        var current = ""
        for part in folder.split(separator: "/").map(String.init) {
            current = current.isEmpty ? part : current + "/" + part
            result.append((name: part, folder: current))
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

    // MARK: Navigation

    public func show(folder path: String) {
        guard path.isEmpty || listing?.folders.contains(path) == true else { return }
        filterText = ""
        folder = path
        selection = []
    }

    /// Opens the selected folder (⌘↓, double-click). Books open with A7.
    public func openSelection() {
        guard selectedRows.count == 1, let row = selectedRows.first, let path = row.folderPath else { return }
        show(folder: path)
    }

    /// Goes to the enclosing folder (⌘↑), selecting the folder just left.
    public func goUp() {
        guard !folder.isEmpty else { return }
        let left = folder
        show(folder: Self.parent(folder))
        selection = ["folder:" + left]
    }

    public func requestSearchFocus() {
        searchFocusRequested = true
    }

    /// Keeps the location and selection valid after the listing changes, and starts at the root for a new library.
    public func listingChanged() {
        if session.libraryURL != lastLibrary {
            lastLibrary = session.libraryURL
            folder = ""
            filterText = ""
            selection = []
            showingIssues = false
            return
        }
        guard let listing else { return }
        let folders = Set(listing.folders)
        while !folder.isEmpty && !folders.contains(folder) { folder = Self.parent(folder) }
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
                case .name: left.name.localizedStandardCompare(right.name)
                case .kind: left.kind.label.localizedStandardCompare(right.kind.label)
                case .updated: compare(left.updated ?? .distantPast, right.updated ?? .distantPast)
                case .size: compare(left.sizeBytes ?? 0, right.sizeBytes ?? 0)
                }
            if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
            let byName = left.name.localizedStandardCompare(right.name)
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
        "\(size(bytes)) (\(bytes.formatted()) bytes)"
    }
}
