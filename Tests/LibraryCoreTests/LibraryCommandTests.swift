import Darwin
import Foundation
import Testing

@_spi(Testing) @testable import LibraryCore

private struct CommandLibrary {
    let parent: URL
    let url: URL
    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-commands-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
    }
    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

private func commandSource(
    _ json: String = "{\"blueprint\":{\"version\":1,\"label\":\"Original\",\"unknown\":12345678901234567890}}"
) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}
private func commandBook() throws -> Data {
    try commandSource(
        """
        {"blueprint_book":{"version":1,"label":"Sparse Book","description":"Root description","active_index":5,"blueprints":[
          {"index":5,"blueprint_book":{"version":1,"label":"Nested","description":"Nested description","blueprints":[
            {"index":0,"extension":"keep","blueprint":{"version":1,"label":"Leaf","unknown":12345678901234567890}}
          ]}},
          {"index":9,"upgrade_planner":{"version":1,"label":"Planner","settings":{"description":"Planner description"}}}
        ]}}
        """)
}
private func commandChild(_ name: String, _ args: [String]) throws -> (Int32, Data, Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/\(name)")
    process.arguments = args
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, stdout, stderr)
}

/// Folders in the test Trash (set by tools/swift.sh) whose metadata preimage belongs to `id`.
private func trashedCopies(of id: String) throws -> [URL] {
    let trash = try #require(
        ProcessInfo.processInfo.environment["FB_NATIVE_TRASH_DIRECTORY"], "Run tests through tools/swift.sh")
    let folders =
        (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: trash), includingPropertiesForKeys: nil)) ?? []
    return folders.filter { folder in
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.contains { file in
            file.pathExtension == "json"
                && ((try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self).contains(id) } ?? false)
        }
    }
}

@Suite("Complete native library commands", .serialized)
struct LibraryCommandTests {
    @Test("Folder organization, case-only names, collisions, cycles, and empty-only deletion")
    func folders() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        #expect(try library.createFolder(name: "First") == "First")
        _ = try library.createFolder(name: "Destination")
        _ = try library.createFolder(parent: "First", name: "Child")
        #expect(throws: NativeLibraryError.nameCollision) { try library.createFolder(name: "first") }
        #expect(throws: NativeLibraryError.folderNotEmpty) { try library.deleteFolder("First") }
        #expect(throws: NativeLibraryError.invalidInput) { try library.moveFolder("First", parent: "First/Child") }
        #expect(throws: NativeLibraryError.invalidInput) { try library.deleteFolder("") }
        #expect(try library.moveFolder("First", parent: "", name: "FIRST") == "FIRST")
        #expect(try library.moveFolder("FIRST", parent: "Destination", name: "Moved") == "Destination/Moved")
        #expect(try library.list().folders == ["Destination", "Destination/Moved", "Destination/Moved/Child"])
        try library.deleteFolder("Destination/Moved/Child")
        try library.deleteFolder("Destination/Moved")
        try library.deleteFolder("Destination")
        #expect(try library.list().folders.isEmpty)
    }

    @Test("Recovery cannot interpret a nonempty folder as an empty-folder deletion")
    func nonemptyDeleteIntent() throws {
        let operationId = LibraryRecords.uuid()
        let file = LibraryTreeFile(path: "Original.txt", bytes: 1, sha256: String(repeating: "a", count: 64))
        let intent = LibraryTransaction(
            schemaVersion: 2, operationId: operationId, kind: "tree-delete", changes: [], cacheIds: [],
            sourceFolder: "Folder", destinationFolder: nil,
            tree: LibraryTreeInventory(directories: [], files: [file], rootInode: nil))
        let bytes = try LibraryRecords.encode(intent, maximum: LibraryBounds.transaction)
        #expect(throws: NativeLibraryError.folderNotEmpty) {
            try LibraryRecords.transaction(bytes, operationId: operationId)
        }
    }

    @Test("Folder moves record identity without content hashes and refuse a look-alike folder on replay")
    func identityMoves() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        _ = try library.createFolder(name: "Source")
        _ = try library.importSource(commandBook(), name: "Item", folder: "Source")
        library.close()
        let killed = try commandChild(
            "StorageTestDriver", ["folder-move-crash", target.url.path, "Source", "intentPublished"])
        #expect(killed.0 == SIGKILL, "\(String(decoding: killed.2, as: UTF8.self))")
        let operations = target.url.appendingPathComponent("operations")
        let stage = try #require(
            FileManager.default.contentsOfDirectory(at: operations, includingPropertiesForKeys: nil).first)
        let intent = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: stage.appendingPathComponent("intent.json")))
                as? [String: Any])
        let tree = try #require(intent["tree"] as? [String: Any])
        let files = try #require(tree["files"] as? [[String: Any]])
        #expect(tree["rootInode"] != nil && !files.isEmpty && files.allSatisfy { $0["sha256"] == nil })

        // Swap in a different folder with identical member names and sizes: replay must not adopt it.
        let source = target.url.appendingPathComponent("library/Source")
        let lookalike = target.parent.appendingPathComponent("Lookalike")
        try FileManager.default.copyItem(at: source, to: lookalike)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: lookalike, to: source)
        #expect(throws: NativeLibraryError.integrity) { try NativeLibrary(at: target.url) }
    }

    @Test("Moving and renaming preserve exact originals, identity, comments, and creation dates")
    func items() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let bytes = try commandSource()
        let item = try library.importSource(bytes)
        let commented = try library.addComment(id: item.id, text: "Retain")
        let renamed = try library.renameItem(id: item.id, name: "Renamed")
        #expect(renamed.name == "Renamed")
        _ = try library.renameItem(id: item.id, name: "RENAMED")
        _ = try library.createFolder(name: "Destination")
        let moved = try library.moveItem(id: item.id, folder: "Destination")
        #expect(moved.metadata.comments == commented.metadata.comments)
        #expect(moved.metadata.createdAt == item.metadata.createdAt)
        #expect(try library.export(id: item.id) == bytes)
        _ = try library.importSource(bytes, name: "Taken", folder: "Destination")
        #expect(throws: NativeLibraryError.nameCollision) { try library.renameItem(id: item.id, name: "Taken") }
        #expect(try library.export(id: item.id) == bytes)
        let without = try library.deleteComment(id: item.id, commentId: commented.metadata.comments[0].id)
        #expect(without.metadata.comments.isEmpty)
        #expect(throws: NativeLibraryError.notFound) {
            try library.deleteComment(id: item.id, commentId: commented.metadata.comments[0].id)
        }
        try library.deleteItem(id: item.id)
        #expect(try library.list().items.count == 1)
        #expect(throws: NativeLibraryError.notFound) { try library.export(id: item.id) }
    }

    @Test("Replacement keeps identity and dates and promotes removed-entry comments")
    func replacement() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let item = try library.importSource(commandBook(), name: "Personal")
        _ = try library.addComment(id: item.id, entryPath: [5, 0], text: "Leaf note")
        let old = try library.addComment(id: item.id, text: "Root note")
        let bytes = try commandSource()
        let new = try library.updateSource(id: item.id, bytes: bytes)
        #expect(new.id == item.id && new.name == "Personal" && new.basename == item.basename)
        #expect(new.metadata.createdAt == item.metadata.createdAt)
        #expect(new.metadata.comments.map(\.id) == old.metadata.comments.map(\.id))
        #expect(new.metadata.comments[0].text == "[Former book entry 5.0]\n\nLeaf note")
        #expect(new.metadata.comments.allSatisfy { $0.entryPath.isEmpty })
        #expect(new.metadata.comments[1] == old.metadata.comments[1])
        #expect(try library.export(id: item.id) == bytes)
        #expect(throws: BlueprintCodecError.self) { try library.updateSource(id: item.id, bytes: Data("bad".utf8)) }
        #expect(try library.export(id: item.id) == bytes)
    }

    @Test("Unpacked imports preserve sparse indices, descriptions, unknown fields and independent leaf identities")
    func unpack() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let result = try library.importUnpacked(commandBook())
        #expect(result.folder == "Sparse Book" && result.folderCount == 2 && result.itemCount == 2)
        let listing = try library.list()
        #expect(listing.issues.isEmpty)
        #expect(
            listing.folderComments == [
                "Sparse Book": "Root description", "Sparse Book/5 - Nested": "Nested description",
            ])
        let leaf = try #require(listing.items.first { $0.basename == "0 - Leaf" })
        let document = try BlueprintCodec.decode(library.export(id: leaf.id))
        #expect(document.root.value["index"] == nil)
        #expect(document.root.value["extension"]?.string == "keep")
        let originalLeaf = try BlueprintCodec.decode(commandBook()).entry(at: [5, 0])
        #expect(document.root.body["unknown"] == originalLeaf.body["unknown"])
        #expect(try library.importUnpacked(commandBook()).folder == "Sparse Book (2)")
        #expect(Set(try library.list().items.map(\.id)).count == 4)
        try library.deleteItem(id: leaf.id)
        try library.deleteFolder("Sparse Book/5 - Nested")
        #expect(try library.list().folderComments["Sparse Book/5 - Nested"] == nil)
        #expect(throws: NativeLibraryError.invalidInput) { try library.importUnpacked(commandSource()) }
    }

    @Test("Export exclusively creates new files and cannot alter managed storage")
    func exportFile() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let bytes = try commandSource()
        let item = try library.importSource(bytes)
        let output = target.parent.appendingPathComponent("output.txt")
        #expect(try library.export(id: item.id, to: output) == bytes.count)
        #expect(try Data(contentsOf: output) == bytes)
        #expect(throws: NativeLibraryError.io(EEXIST)) { try library.export(id: item.id, to: output) }
        #expect(throws: NativeLibraryError.unsafePath) {
            try library.export(id: item.id, to: target.url.appendingPathComponent("library/other.txt"))
        }
        let alias = target.parent.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(
            at: alias, withDestinationURL: target.url.appendingPathComponent("cache"))
        #expect(throws: NativeLibraryError.unsafePath) {
            try library.export(id: item.id, to: alias.appendingPathComponent("new.txt"))
        }
    }

    @Test("All file mutation publication boundaries recover after actual process termination")
    func fileCrashes() throws {
        for operation in ["rename", "move", "update", "delete", "comment-delete"] {
            var phases = ["changesStaged", "intentPublished", "filePublished", "intentRemoved"]
            if ["rename", "move", "delete"].contains(operation) { phases.append("fileRemoved") }
            if operation == "delete" {
                phases.removeAll { $0 == "filePublished" }
                phases.append("cacheRemoved")
            }
            if operation == "update" { phases.append("cacheRemoved") }
            if ["update", "delete"].contains(operation) { phases.append("removedRetained") }
            for phase in phases {
                let target = try CommandLibrary()
                defer { target.cleanup() }
                let library = try NativeLibrary.initialize(at: target.url)
                let original = try commandBook()
                let replacement = try commandSource()
                let item = try library.importSource(original, name: "Original")
                _ = try library.createFolder(name: "Destination")
                let commented = try library.addComment(id: item.id, text: "Keep or remove")
                let input = target.parent.appendingPathComponent("replacement.txt")
                try replacement.write(to: input)
                library.close()
                var args = [operation + "-crash", target.url.path, item.id]
                if operation == "update" { args.append(input.path) }
                if operation == "comment-delete" { args.append(commented.metadata.comments[0].id) }
                args.append(phase)
                let result = try commandChild("StorageTestDriver", args)
                #expect(result.0 == SIGKILL, "\(operation) \(phase): \(String(decoding: result.2, as: UTF8.self))")
                let reopened = try NativeLibrary(at: target.url)
                try reopened.recover()
                try reopened.recover()
                let listing = try reopened.list()
                #expect(listing.issues.isEmpty)
                if ["update", "delete"].contains(operation) {
                    // Exactly one preserved copy once committed, never a duplicate after replay.
                    let copies = try trashedCopies(of: item.id)
                    #expect(copies.count == (phase == "changesStaged" ? 0 : 1), "\(operation) \(phase)")
                    if let copy = copies.first {
                        #expect(try Data(contentsOf: copy.appendingPathComponent("Original.txt")) == original)
                    }
                }
                if operation == "delete" && phase != "changesStaged" {
                    #expect(listing.items.isEmpty)
                } else {
                    let restored = try #require(listing.items.first)
                    #expect(restored.id == item.id && restored.metadata.createdAt == item.metadata.createdAt)
                    let committed = phase != "changesStaged"
                    #expect(
                        try reopened.export(id: item.id)
                            == (operation == "update" && committed ? replacement : original))
                    if operation == "rename" { #expect(restored.name == (committed ? "Renamed" : "Original")) }
                    if operation == "move" { #expect(restored.folder == (committed ? "Destination" : "")) }
                    if operation == "comment-delete" {
                        #expect(restored.metadata.comments.count == (committed ? 0 : 1))
                    }
                }
                reopened.close()
            }
        }
    }

    @Test("Deleted and replaced originals move to the Trash byte-identical, with a library fallback")
    func removedOriginals() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        let original = try commandBook()
        let replacement = try commandSource()
        let replaced = try library.importSource(original, name: "Replaced")
        let deleted = try library.importSource(original, name: "Deleted")
        let metadata = try Data(contentsOf: target.url.appendingPathComponent("library/Deleted.json"))
        _ = try library.updateSource(id: replaced.id, bytes: replacement)
        try library.deleteItem(id: deleted.id)
        let replacedCopy = try #require(try trashedCopies(of: replaced.id).first)
        #expect(replacedCopy.lastPathComponent.hasPrefix("Replaced (replaced "))
        #expect(try Data(contentsOf: replacedCopy.appendingPathComponent("Replaced.txt")) == original)
        let deletedCopy = try #require(try trashedCopies(of: deleted.id).first)
        #expect(deletedCopy.lastPathComponent.hasPrefix("Deleted (deleted "))
        #expect(try Data(contentsOf: deletedCopy.appendingPathComponent("Deleted.txt")) == original)
        #expect(try Data(contentsOf: deletedCopy.appendingPathComponent("Deleted.json")) == metadata)
        #expect(try library.export(id: replaced.id) == replacement)
        library.close()

        // When the Trash cannot take the folder, it stays inside the library instead of blocking it.
        let blocked = target.parent.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/debug/fb-native")
        process.arguments = ["delete", target.url.path, replaced.id]
        process.environment = ["FB_NATIVE_TRASH_DIRECTORY": blocked.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let quarantine = target.url.appendingPathComponent("operations-quarantine")
        let kept = try #require(FileManager.default.contentsOfDirectory(atPath: quarantine.path).first)
        #expect(kept.contains("Replaced (deleted "))
        #expect(
            try Data(contentsOf: quarantine.appendingPathComponent(kept).appendingPathComponent("Replaced.txt"))
                == replacement)
        let reopened = try NativeLibrary(at: target.url)
        defer { reopened.close() }
        #expect(try reopened.list().items.isEmpty)
    }

    @Test("Folder move, empty deletion, and unpack publication recover after process termination")
    func treeCrashes() throws {
        for operation in ["folder-move", "folder-delete", "unpack"] {
            var phases = ["intentPublished", "intentRemoved"]
            if operation == "unpack" {
                phases += ["treeStaged", "treePublished"]
            } else {
                phases.append("treeWithdrawn")
                if operation == "folder-move" { phases.append("treePublished") }
            }
            for phase in phases {
                let target = try CommandLibrary()
                defer { target.cleanup() }
                let library = try NativeLibrary.initialize(at: target.url)
                _ = try library.createFolder(name: "Original")
                var originalId: String?
                if operation == "folder-move" {
                    originalId = try library.importSource(commandSource(), folder: "Original").id
                }
                library.close()
                let input = target.parent.appendingPathComponent("book.txt")
                try commandBook().write(to: input)
                let argument = operation == "unpack" ? input.path : "Original"
                let result = try commandChild(
                    "StorageTestDriver", [operation + "-crash", target.url.path, argument, phase])
                #expect(result.0 == SIGKILL, "\(operation) \(phase): \(String(decoding: result.2, as: UTF8.self))")
                let reopened = try NativeLibrary(at: target.url)
                defer { reopened.close() }
                try reopened.recover()
                try reopened.recover()
                let listing = try reopened.list()
                #expect(listing.issues.isEmpty)
                if operation == "folder-delete" { #expect(listing.folders.isEmpty) }
                if operation == "folder-move" {
                    #expect(listing.folders == ["Renamed"])
                    #expect(listing.items.first?.id == originalId)
                    #expect(try reopened.export(id: originalId!) == commandSource())
                }
                if operation == "unpack" {
                    #expect(listing.items.count == (phase == "treeStaged" ? 0 : 2))
                    #expect(listing.folderComments.count == (phase == "treeStaged" ? 0 : 2))
                }
            }
        }
    }

    @Test("Conflicting files after a committed rename preserve preimages and block recovery")
    func conflict() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        let bytes = try commandSource()
        let item = try library.importSource(bytes)
        library.close()
        #expect(
            try commandChild("StorageTestDriver", ["rename-crash", target.url.path, item.id, "fileRemoved"]).0
                == SIGKILL)
        let destination = target.url.appendingPathComponent("library/Renamed.txt")
        try Data("foreign evidence".utf8).write(to: destination)
        #expect(throws: NativeLibraryError.integrity) { try NativeLibrary(at: target.url) }
        #expect(try Data(contentsOf: destination) == Data("foreign evidence".utf8))
        let operations = try FileManager.default.contentsOfDirectory(
            at: target.url.appendingPathComponent("operations"), includingPropertiesForKeys: nil)
        let stage = try #require(operations.first)
        #expect(try Data(contentsOf: stage.appendingPathComponent("before-000000")) == bytes)
        #expect(FileManager.default.fileExists(atPath: stage.appendingPathComponent("intent.json").path))
    }

    @Test("Scoped cache cleanup protects unknown formats and authoritative originals")
    func cleanup() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let bytes = try commandSource()
        let item = try library.importSource(bytes)
        let cache = target.url.appendingPathComponent("cache/\(item.id)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        let temporary = ".tmp-" + LibraryRecords.uuid()
        try Data([1, 2, 3]).write(to: cache.appendingPathComponent(temporary))
        try Data([4]).write(to: cache.appendingPathComponent("unknown.bin"))
        let oldIdentity = LibraryCacheIdentity(
            itemId: item.id, sourceSha256: item.metadata.sourceSha256, entryPath: [], generator: "old",
            assetIdentity: String(repeating: "a", count: 64))
        let key = try oldIdentity.key()
        try LibraryRecords.encode(oldIdentity, maximum: LibraryBounds.journal).write(
            to: cache.appendingPathComponent(key + ".json"))
        try Data([5, 6]).write(to: cache.appendingPathComponent(key + ".png"))
        #expect(try library.cleanupCache().selection.map(\.path) == [item.id + "/" + temporary])
        #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent(temporary).path))
        #expect(try library.cleanupCache(apply: true).selection.count == 1)
        #expect(try library.cleanupCache().selection.isEmpty)
        #expect(throws: NativeLibraryError.invalidInput) { try library.cleanupCache(scope: .obsolete) }
        let obsolete = try library.cleanupCache(
            scope: .obsolete, apply: true, assetIdentity: String(repeating: "a", count: 64))
        #expect(obsolete.selection.count == 2 && obsolete.retainedFiles == 1)
        #expect(try library.export(id: item.id) == bytes)
        #expect(try library.cleanupCache(scope: .all, apply: true).selection.count == 1)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: target.url.appendingPathComponent("cache").path).isEmpty
        )
    }

    @Test("Unsafe aliases block cache cleanup before any deletion; updates and deletes invalidate item caches")
    func cacheSafety() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let item = try library.importSource(commandSource())
        let cache = target.url.appendingPathComponent("cache")
        let safe = cache.appendingPathComponent("safe.bin")
        try Data([1]).write(to: safe)
        let alias = cache.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(
            at: alias, withDestinationURL: target.url.appendingPathComponent("library"))
        #expect(throws: NativeLibraryError.unsafePath) { try library.cleanupCache(scope: .all, apply: true) }
        #expect(FileManager.default.fileExists(atPath: safe.path))
        try FileManager.default.removeItem(at: alias)
        let itemCache = cache.appendingPathComponent(item.id)
        try FileManager.default.createDirectory(at: itemCache, withIntermediateDirectories: false)
        try Data([1]).write(to: itemCache.appendingPathComponent("old.bin"))
        _ = try library.updateSource(id: item.id, bytes: commandSource())
        #expect(!FileManager.default.fileExists(atPath: itemCache.path))
        try FileManager.default.createDirectory(at: itemCache, withIntermediateDirectories: false)
        try Data([1]).write(to: itemCache.appendingPathComponent("old.bin"))
        try library.deleteItem(id: item.id)
        #expect(!FileManager.default.fileExists(atPath: itemCache.path))
        #expect(FileManager.default.fileExists(atPath: safe.path))
    }

    @Test("Orphan cleanup recognizes only native manifests and refuses unsafe shared inodes or asset overlap")
    func cacheClassification() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let item = try library.importSource(commandSource())
        let orphanId = LibraryRecords.uuid()
        let cache = target.url.appendingPathComponent("cache")
        let folder = cache.appendingPathComponent(orphanId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let identity = LibraryCacheIdentity(
            itemId: orphanId, sourceSha256: item.metadata.sourceSha256, entryPath: [], generator: "old",
            assetIdentity: String(repeating: "b", count: 64))
        let key = try identity.key()
        try LibraryRecords.encode(identity, maximum: LibraryBounds.journal).write(
            to: folder.appendingPathComponent(key + ".json"))
        try Data([1]).write(to: folder.appendingPathComponent(key + ".png"))
        let unknown = String(repeating: "c", count: 64)
        try Data("{\"schemaVersion\":99}".utf8).write(to: folder.appendingPathComponent(unknown + ".json"))
        try Data([2]).write(to: folder.appendingPathComponent(unknown + ".png"))
        #expect(try library.cleanupCache().selection.count == 2)
        #expect(try library.cleanupCache().retainedFiles == 2)
        #expect(throws: NativeLibraryError.unsafePath) {
            try library.cleanupCache(scope: .all, apply: true, protectedAssets: cache)
        }
        let shared = cache.appendingPathComponent("shared.txt")
        try FileManager.default.linkItem(
            at: target.url.appendingPathComponent("library/\(item.basename).txt"), to: shared)
        #expect(throws: NativeLibraryError.unsafePath) { try library.cleanupCache(scope: .all, apply: true) }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(key + ".png").path))
        try FileManager.default.removeItem(at: shared)
        #expect(try library.cleanupCache(apply: true).selection.count == 2)
        #expect(try library.cleanupCache().selection.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
        #expect(try library.export(id: item.id) == commandSource())
    }

    @Test("Usage separates categories, counts shared inodes once, and reports incomplete assets or unsafe paths")
    func usage() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        defer { library.close() }
        let bytes = try commandSource()
        _ = try library.importSource(bytes)
        let assets = target.parent.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: false)
        let source = assets.appendingPathComponent("file.bin")
        let alias = assets.appendingPathComponent("hardlink.bin")
        try Data(repeating: 1, count: 4096).write(to: source)
        try FileManager.default.linkItem(at: source, to: alias)
        #expect(try library.diskUsage().complete == false)
        let report = try library.diskUsage(assets: assets)
        #expect(report.complete && report.issues.isEmpty)
        #expect(report.categories["originals"]?.logicalBytes == Int64(bytes.count))
        #expect(report.categories["assets"]?.logicalBytes == 8192)
        #expect(report.categories["assets"]?.uniqueLogicalBytes == 4096)
        #expect(report.categories["assets"]?.files == 2)
        try FileManager.default.createSymbolicLink(
            at: assets.appendingPathComponent("unsafe"), withDestinationURL: source)
        #expect(try library.diskUsage(assets: assets).issues.contains { $0.code == "UNSAFE_PATH" })
    }

    @Test("CLI executes every organization command and reports invalid options without raw-export pollution")
    func cli() throws {
        let target = try CommandLibrary()
        defer { target.cleanup() }
        func call(_ args: [String]) throws -> [String: Any] {
            let response = try commandChild("fb-native", args)
            #expect(response.0 == 0, "\(String(decoding: response.2, as: UTF8.self))")
            return try #require(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
        }
        let input = target.parent.appendingPathComponent("source.txt")
        try commandBook().write(to: input)
        _ = try call(["init", target.url.path])
        let response = try call(["import", target.url.path, input.path])
        let result = try #require(response["result"] as? [String: Any])
        let id = try #require(result["id"] as? String)
        _ = try call(["folder-create", target.url.path, "", "Destination"])
        _ = try call(["rename", target.url.path, id, "Personal"])
        _ = try call(["move", target.url.path, id, "Destination"])
        _ = try call(["folder-move", target.url.path, "Destination", "", "Moved"])
        let comment = try call(["comment-add", target.url.path, id, "Note", "--entry", "5.0"])
        let commented = try #require(comment["result"] as? [String: Any])
        let metadata = try #require(commented["metadata"] as? [String: Any])
        let comments = try #require(metadata["comments"] as? [[String: Any]])
        let commentId = try #require(comments.first?["id"] as? String)
        _ = try call(["comment-delete", target.url.path, id, commentId])
        _ = try call([
            "export", target.url.path, id, "--output", target.parent.appendingPathComponent("export.txt").path,
        ])
        #expect(try commandChild("fb-native", ["export", target.url.path, id]).1 == commandBook())
        _ = try call(["update", target.url.path, id, input.path])
        _ = try call(["usage", target.url.path])
        _ = try call(["cache-cleanup", target.url.path, "all", "--apply"])
        _ = try call(["delete", target.url.path, id])
        _ = try call(["folder-delete", target.url.path, "Moved"])
        _ = try call(["import-unpacked", target.url.path, input.path])
        #expect(try commandChild("fb-native", ["folder-create", target.url.path, ""]).0 == 2)
        #expect(try commandChild("fb-native", ["cache-cleanup", target.url.path, "obsolete"]).0 == 2)
        #expect(try commandChild("fb-native", ["cache-cleanup", target.url.path, "all", "--apply", "--apply"]).0 == 2)
    }
}
