import Foundation

/// Derived, disposable map from exact source hash to the root's kind and entry icons, so listing never decodes saved
/// blueprints. Keyed by content, an entry cannot become stale; an unreadable index, or one of another schema (such as
/// schema 1, which held kinds only), is rebuilt.
struct LibrarySourceIndex: Codable, Equatable {
    static let name = "source-index.json"
    static let maximumBytes = 16 * 1024 * 1024
    static let schema = 2

    var schemaVersion = schema
    var kinds: [String: String] = [:]
    /// Entry icons of roots that have any; every key is also in `kinds`.
    var icons: [String: [EntryIcon]] = [:]

    static func read(_ cache: LibraryDirectory) -> LibrarySourceIndex {
        guard (try? cache.info(name)) != nil,
            let bytes = try? cache.read(name, maximum: maximumBytes),
            let index = try? JSONDecoder().decode(LibrarySourceIndex.self, from: bytes),
            index.schemaVersion == schema, index.kinds.count <= LibraryBounds.directoryEntries,
            index.kinds.allSatisfy({
                LibraryRecords.validHash($0.key) && BlueprintEntryKind(rawValue: $0.value) != nil
            }),
            index.icons.allSatisfy({ hash, icons in
                index.kinds[hash] != nil && (1...4).contains(icons.count) && icons.allSatisfy(\.isValid)
                    && icons.map(\.index) == icons.map(\.index).sorted() && Set(icons.map(\.index)).count == icons.count
            })
        else { return LibrarySourceIndex() }
        return index
    }

    /// Replaces the index atomically. Cache files get no drive barrier; a lost write only costs a decode.
    func write(_ cache: LibraryDirectory) throws {
        let bytes = try LibraryRecords.encode(self, maximum: Self.maximumBytes)
        let temporary = ".tmp-" + LibraryRecords.uuid()
        try cache.writeNew(temporary, data: bytes)
        do {
            try cache.move(temporary, to: cache, as: Self.name, replacing: true)
        } catch {
            try? cache.remove(temporary)
            throw error
        }
    }
}
