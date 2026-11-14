import Foundation
import Testing

@_spi(Testing) @testable import LibraryCore

private struct FinderLibrary {
    let parent: URL
    let url: URL
    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("fb-native-finder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
    }
    func cleanup() { try? FileManager.default.removeItem(at: parent) }
    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }
}

private func finderSource(_ label: String) throws -> Data {
    let json = "{\"blueprint\":{\"version\":1,\"label\":\"\(label)\"}}"
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private func finderBook() throws -> Data {
    let json = """
        {"blueprint_book":{"version":1,"label":"Book","description":"Described","blueprints":[
          {"index":0,"blueprint":{"version":1,"label":"Leaf"}},
          {"index":2,"blueprint_book":{"version":1,"label":"Inner","blueprints":[
            {"index":1,"blueprint":{"version":1,"label":"Deep"}}]}}]}}
        """
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

/// Writes (or rewrites with a new size) a `.DS_Store` in `directory` and every directory beneath it, as Finder may.
private func sprinkleFinderMetadata(in directory: URL, generation: Int) {
    let bytes = Data(repeating: UInt8(truncatingIfNeeded: generation), count: 16 + generation % 64)
    var directories = [directory]
    if let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
        for case let url as URL in walker
        where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            directories.append(url)
        }
    }
    for folder in directories { try? bytes.write(to: folder.appendingPathComponent(".DS_Store")) }
}

@Suite("Finder metadata files in libraries")
struct LibraryFinderMetadataTests {
    @Test("A .DS_Store in operations/ or an operation directory never blocks opening or staging cleanup")
    func operationsDirectory() throws {
        let target = try FinderLibrary()
        defer { target.cleanup() }
        try NativeLibrary.initialize(at: target.url).close()
        let stageId = LibraryRecords.uuid()
        try FileManager.default.createDirectory(
            at: target.path("operations/\(stageId)"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: target.path("operations-quarantine"), withIntermediateDirectories: false)
        try Data("finder".utf8).write(to: target.path("operations/.DS_Store"))
        try Data("finder".utf8).write(to: target.path("operations/\(stageId)/.DS_Store"))
        try Data("finder".utf8).write(to: target.path("operations-quarantine/.DS_Store"))

        let operations = try NativeLibrary.inspectOperations(at: target.url)
        #expect(operations == [LibraryOperationRecord(id: stageId, state: "unpublished", kind: nil)])
        let library = try NativeLibrary(at: target.url)
        defer { library.close() }
        #expect(try library.list().issues.isEmpty)
        #expect(try library.cleanupStaging(apply: true).selection.map(\.id) == [stageId])
        #expect(!FileManager.default.fileExists(atPath: target.path("operations/\(stageId)").path))
        _ = try library.importSource(finderSource("After cleanup"))
    }

    @Test("Finder metadata written at every write phase never fails an operation or the listing")
    func everyPhase() throws {
        let target = try FinderLibrary()
        defer { target.cleanup() }
        try NativeLibrary.initialize(at: target.url).close()
        nonisolated(unsafe) var generation = 0
        let library = try NativeLibrary.testingOpen(at: target.url) { _ in
            generation += 1
            sprinkleFinderMetadata(in: target.url, generation: generation)
        }
        defer { library.close() }
        _ = try library.createFolder(name: "Source")
        _ = try library.createFolder(name: "Empty")
        let item = try library.importSource(finderSource("Item"), folder: "Source")
        let other = try library.importSource(finderSource("Other"))
        _ = try library.addComment(id: item.id, text: "Note")
        _ = try library.renameItem(id: item.id, name: "Renamed item")
        #expect(try library.moveFolder("Source", parent: "", name: "Moved") == "Moved")
        _ = try library.moveItem(id: other.id, folder: "Moved")
        _ = try library.updateSource(id: other.id, bytes: finderSource("Replacement"))
        try FileManager.default.createDirectory(
            at: target.path("cache/\(other.id)"), withIntermediateDirectories: false)
        try Data("finder".utf8).write(to: target.path("cache/\(other.id)/.DS_Store"))
        try library.deleteItem(id: other.id)
        #expect(!FileManager.default.fileExists(atPath: target.path("cache/\(other.id)").path))
        try library.deleteFolder("Empty")
        let unpacked = try library.importUnpacked(finderBook())
        let orphan = LibraryRecords.uuid()
        try FileManager.default.createDirectory(at: target.path("cache/\(orphan)"), withIntermediateDirectories: false)
        try Data("finder".utf8).write(to: target.path("cache/\(orphan)/.DS_Store"))
        #expect(try library.cleanupCache(scope: .all, apply: true).selectedDirectories.contains(orphan))
        #expect(!FileManager.default.fileExists(atPath: target.path("cache/\(orphan)").path))

        let listing = try library.list()
        #expect(listing.issues.isEmpty)
        #expect(Set(listing.folders).isSuperset(of: ["Moved", unpacked.folder]))
        #expect(listing.items.count == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path("operations").path) == [".DS_Store"])
    }

    @Test("Interrupted folder moves and deletions replay after Finder metadata appears, changes, or disappears")
    func interruptedTrees() throws {
        struct Interrupted: Error {}
        let target = try FinderLibrary()
        defer { target.cleanup() }
        let setup = try NativeLibrary.initialize(at: target.url)
        _ = try setup.createFolder(name: "Source")
        _ = try setup.createFolder(name: "Empty")
        _ = try setup.importSource(finderSource("Item"), folder: "Source")
        setup.close()
        try Data("old".utf8).write(to: target.path("library/Source/.DS_Store"))
        try Data("old".utf8).write(to: target.path("library/Empty/.DS_Store"))

        let moving = try NativeLibrary.testingOpen(at: target.url) { phase in
            if phase == .intentPublished { throw Interrupted() }
        }
        #expect(throws: Interrupted.self) { try moving.moveFolder("Source", parent: "", name: "Moved") }
        moving.close()
        try Data("rewritten by Finder".utf8).write(to: target.path("library/Source/.DS_Store"))
        sprinkleFinderMetadata(in: target.path("operations"), generation: 7)

        // Opening replays the interrupted move, which passes through the same phases; arm the hook afterwards.
        nonisolated(unsafe) var armed = false
        let deleting = try NativeLibrary.testingOpen(at: target.url) { phase in
            if armed && phase == .treeWithdrawn { throw Interrupted() }
        }
        #expect(try deleting.list().folders.contains("Moved"))
        armed = true
        #expect(throws: Interrupted.self) { try deleting.deleteFolder("Empty") }
        deleting.close()
        sprinkleFinderMetadata(in: target.path("operations"), generation: 9)

        let reopened = try NativeLibrary(at: target.url)
        defer { reopened.close() }
        let listing = try reopened.list()
        #expect(listing.issues.isEmpty)
        #expect(listing.folders == ["Moved"])
        #expect(listing.items.map(\.folder) == ["Moved"])
    }

    @Test("An intent recorded with a .DS_Store member still replays after Finder removes the file")
    func legacyInventory() throws {
        struct Interrupted: Error {}
        let target = try FinderLibrary()
        defer { target.cleanup() }
        let setup = try NativeLibrary.initialize(at: target.url)
        _ = try setup.createFolder(name: "Source")
        _ = try setup.importSource(finderSource("Item"), folder: "Source")
        setup.close()
        let moving = try NativeLibrary.testingOpen(at: target.url) { phase in
            if phase == .intentPublished { throw Interrupted() }
        }
        #expect(throws: Interrupted.self) { try moving.moveFolder("Source", parent: "", name: "Moved") }
        moving.close()

        // Builds before this change recorded `.DS_Store` members in tree inventories.
        let stage = try #require(
            FileManager.default.contentsOfDirectory(at: target.path("operations"), includingPropertiesForKeys: nil)
                .first { LibraryRecords.validUUID($0.lastPathComponent) })
        let intentURL = stage.appendingPathComponent("intent.json")
        var intent = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: intentURL)) as? [String: Any])
        var tree = try #require(intent["tree"] as? [String: Any])
        let files = try #require(tree["files"] as? [[String: Any]])
        tree["files"] = [["path": ".DS_Store", "bytes": 6]] + files
        intent["tree"] = tree
        try JSONSerialization.data(withJSONObject: intent, options: [.sortedKeys]).write(to: intentURL)

        let reopened = try NativeLibrary(at: target.url)
        defer { reopened.close() }
        #expect(try reopened.list().folders == ["Moved"])
    }

    @Test("Only regular .DS_Store files are ignored")
    func onlyRegularFiles() throws {
        let target = try FinderLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        _ = try library.createFolder(name: "Folder")
        library.close()
        try FileManager.default.createSymbolicLink(
            atPath: target.path("library/Folder/.DS_Store").path, withDestinationPath: "/etc/hosts")
        let reopened = try NativeLibrary(at: target.url)
        let listing = try reopened.list()
        #expect(listing.issues.map(\.path) == ["Folder/.DS_Store"])
        #expect(listing.issues.map(\.code) == [NativeLibraryError.unsafePath.code])
        reopened.close()
        try FileManager.default.removeItem(at: target.path("library/Folder/.DS_Store"))
        try FileManager.default.createDirectory(
            at: target.path("operations/.DS_Store"), withIntermediateDirectories: false)
        #expect(throws: NativeLibraryError.recoveryRequired) { try NativeLibrary(at: target.url) }
    }

    @Test("A folder holding only Finder metadata can become a new library")
    func initializeBrowsedFolder() throws {
        let target = try FinderLibrary()
        defer { target.cleanup() }
        try FileManager.default.createDirectory(at: target.url, withIntermediateDirectories: false)
        try Data("finder".utf8).write(to: target.path(".DS_Store"))
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        #expect(try library.list().issues.isEmpty)
    }
}
