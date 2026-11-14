import Darwin
import Foundation

extension NativeLibrary {
    func stageName(_ prefix: String, _ index: Int) -> String { String(format: "%@-%06d", prefix, index) }

    func prepareOperation() throws -> (String, LibraryDirectory) {
        guard try operations.entries(maximum: LibraryBounds.operations).count < LibraryBounds.operations else {
            throw NativeLibraryError.limitExceeded
        }
        let id = LibraryRecords.uuid()
        guard try operations.info(id) == nil else { throw NativeLibraryError.integrity }
        return (id, try operations.child(id, create: true))
    }

    /// `removed` names a folder of exact preimages that moves to the Trash once the change is published.
    func commitChanges(
        _ prepared: [PreparedLibraryChange], cacheIds: [String] = [], removed: LibraryRemovedItem? = nil
    ) throws {
        guard !prepared.isEmpty, prepared.count <= LibraryBounds.changes else { throw NativeLibraryError.invalidInput }
        removedToQuarantine = false
        var total = 0
        for change in prepared {
            _ = try MutationPath.parts(change.path, file: true)
            total += (change.before?.count ?? 0) + (change.after?.count ?? 0)
            guard total <= LibraryBounds.transactionBytes else { throw NativeLibraryError.limitExceeded }
        }
        for id in cacheIds { try validateCacheItem(id) }
        let changes = prepared.map {
            LibraryFileChange(
                path: $0.path, before: $0.before.map { OriginalSource(bytes: $0).sha256 },
                after: $0.after.map { OriginalSource(bytes: $0).sha256 })
        }
        let (id, stage) = try prepareOperation()
        do {
            for (index, change) in prepared.enumerated() {
                if let before = change.before { try stage.writeNew(stageName("before", index), data: before) }
                if let after = change.after { try stage.writeNew(stageName("after", index), data: after) }
            }
            if let removed {
                let folder = try stage.child("removed", create: true).child(removed.folder, create: true)
                for (name, data) in removed.files { try folder.writeNew(name, data: data) }
            }
            try hook?(.changesStaged)
            let intent = LibraryTransaction(
                schemaVersion: 2, operationId: id, kind: "files", changes: changes,
                cacheIds: cacheIds, sourceFolder: nil, destinationFolder: nil, tree: nil)
            try commitTransaction(intent, stage: stage)
        } catch {
            needsRecovery = true
            itemPaths = nil
            throw error
        }
    }

    func commitTree(
        kind: String, source: String?, destination: String?, directories: [String] = [], files: [String: Data] = [:]
    ) throws {
        if let source { _ = try MutationPath.parts(source, file: false) }
        if let destination { _ = try MutationPath.parts(destination, file: false) }
        let (id, stage) = try prepareOperation()
        do {
            let inventory: LibraryTreeInventory
            if kind == "tree-create" {
                let tree = try stage.child("tree", create: true)
                var total = 0
                for path in directories.sorted(by: { $0.split(separator: "/").count < $1.split(separator: "/").count })
                {
                    let (parent, name) = try MutationPath.parent(tree, path, file: false)
                    _ = try parent.child(name, create: true)
                }
                for path in files.keys.sorted() {
                    let data = files[path]!
                    total += data.count
                    guard total <= LibraryBounds.transactionBytes else { throw NativeLibraryError.limitExceeded }
                    let (parent, name) = try MutationPath.parent(tree, path, file: true)
                    try parent.writeNew(name, data: data)
                }
                inventory = try LibraryTrees.inventory(tree)
                try hook?(.treeStaged)
            } else {
                guard let source else { throw NativeLibraryError.invalidInput }
                inventory = try LibraryTrees.inventory(directory(at: source), identity: kind == "tree-move")
            }
            let intent = LibraryTransaction(
                schemaVersion: 2, operationId: id, kind: kind, changes: [], cacheIds: [],
                sourceFolder: source, destinationFolder: destination, tree: inventory)
            try commitTransaction(intent, stage: stage)
            // Tree operations add or move many items at once; rebuild the ID index on next use.
            itemPaths = nil
        } catch {
            needsRecovery = true
            itemPaths = nil
            throw error
        }
    }

    func commitTransaction(_ intent: LibraryTransaction, stage: LibraryDirectory) throws {
        let bytes = try LibraryRecords.encode(intent, maximum: LibraryBounds.transaction)
        _ = try LibraryRecords.transaction(bytes, operationId: intent.operationId)
        try preflightTransaction(intent, stage: stage)
        try stage.writeNew("intent.pending", data: bytes)
        try stage.move("intent.pending", to: stage, as: "intent.json")
        // Commit point: staged bytes and the intent reach permanent storage before live files change.
        try stage.barrier()
        needsRecovery = true
        try hook?(.intentPublished)
        try applyTransaction(intent, stage: stage)
        needsRecovery = false
    }

    func logicalFile(_ path: String, changes: [LibraryFileChange]) throws -> Data? {
        let (parent, name) = try MutationPath.parent(library, path, file: true)
        let matches = try parent.entries().filter { LibraryNames.key($0) == LibraryNames.key(name) }
        guard matches.count <= 1 else { throw NativeLibraryError.integrity }
        guard let actual = matches.first else { return nil }
        if !actual.utf8.elementsEqual(name.utf8) {
            let actualPath = MutationPath.join(
                String(path.split(separator: "/").dropLast().joined(separator: "/")), actual)
            guard changes.contains(where: { $0.path.utf8.elementsEqual(actualPath.utf8) }) else {
                throw NativeLibraryError.integrity
            }
            return nil
        }
        return try parent.read(name, maximum: BlueprintCodecLimits.standard.sourceBytes)
    }

    func preflightTransaction(_ intent: LibraryTransaction, stage: LibraryDirectory) throws {
        try checkControls()
        if intent.kind == "files" {
            var allowed: Set<String> = ["intent.pending", "intent.json"]
            var total = 0
            for (index, change) in intent.changes.enumerated() {
                for (prefix, hash) in [("before", change.before), ("after", change.after)] {
                    if let hash {
                        let name = stageName(prefix, index)
                        allowed.insert(name)
                        let bytes = try stage.read(name, maximum: BlueprintCodecLimits.standard.sourceBytes)
                        total += bytes.count
                        guard total <= LibraryBounds.transactionBytes, OriginalSource(bytes: bytes).sha256 == hash
                        else { throw NativeLibraryError.integrity }
                    }
                }
                let current = try logicalFile(change.path, changes: intent.changes).map {
                    OriginalSource(bytes: $0).sha256
                }
                guard current == change.before || current == change.after else { throw NativeLibraryError.integrity }
            }
            for name in try stage.entries(maximum: LibraryBounds.changes * 2 + 64) {
                if name == "removed" {
                    try validateRemoved(stage)
                    continue
                }
                guard allowed.contains(name) || validPublicationTemporary(name) else {
                    throw NativeLibraryError.recoveryRequired
                }
                guard let info = try stage.info(name), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
                    throw NativeLibraryError.unsafePath
                }
            }
            for id in intent.cacheIds { try validateCacheItem(id) }
        } else {
            guard Set(try stage.entries()).isSubset(of: ["tree", "intent.pending", "intent.json"]) else {
                throw NativeLibraryError.recoveryRequired
            }
            _ = try treeLocation(intent, stage: stage)
        }
    }

    func validPublicationTemporary(_ name: String) -> Bool {
        name.hasPrefix("publish-") && name.hasSuffix(".tmp")
            && LibraryRecords.validUUID(String(name.dropFirst(8).dropLast(4)))
    }

    func applyTransaction(_ intent: LibraryTransaction, stage: LibraryDirectory) throws {
        try preflightTransaction(intent, stage: stage)
        if intent.kind == "files" {
            // Withdraw old names first, including case-only renames on insensitive APFS.
            for change in intent.changes where change.after == nil {
                if let data = try logicalFile(change.path, changes: intent.changes) {
                    guard OriginalSource(bytes: data).sha256 == change.before else {
                        throw NativeLibraryError.integrity
                    }
                    let (parent, name) = try MutationPath.parent(library, change.path, file: true)
                    try parent.remove(name)
                    try hook?(.fileRemoved)
                }
            }
            for (index, change) in intent.changes.enumerated() where change.after != nil {
                let current = try logicalFile(change.path, changes: intent.changes).map {
                    OriginalSource(bytes: $0).sha256
                }
                if current == change.after { continue }
                guard current == change.before else { throw NativeLibraryError.integrity }
                let bytes = try stage.read(
                    stageName("after", index), maximum: BlueprintCodecLimits.standard.sourceBytes)
                let temporary = "publish-\(LibraryRecords.uuid()).tmp"
                try stage.writeNew(temporary, data: bytes)
                guard
                    try logicalFile(change.path, changes: intent.changes).map({ OriginalSource(bytes: $0).sha256 })
                        == current
                else { throw NativeLibraryError.integrity }
                let (parent, name) = try MutationPath.parent(library, change.path, file: true)
                try stage.move(temporary, to: parent, as: name, replacing: change.before != nil)
                try hook?(.filePublished)
            }
            for id in intent.cacheIds {
                try purgeCacheItem(id)
                try hook?(.cacheRemoved)
            }
        } else {
            var location = try treeLocation(intent, stage: stage)
            if location == "source", let source = intent.sourceFolder {
                let (parent, name) = try MutationPath.parent(library, source, file: false)
                try parent.move(name, to: stage, as: "tree")
                try hook?(.treeWithdrawn)
                location = "stage"
            }
            if location == "stage", let destination = intent.destinationFolder {
                let (parent, name) = try MutationPath.parent(library, destination, file: false)
                try stage.move("tree", to: parent, as: name)
                try hook?(.treePublished)
            }
            _ = try treeLocation(intent, stage: stage)
        }
        // Published changes reach permanent storage before the intent that can replay them disappears.
        try stage.barrier()
        // Still under the intent: a crash before this completes replays it; replay skips an emptied stage.
        try retainRemoved(stage, operationId: intent.operationId)
        try stage.remove("intent.json")
        try hook?(.intentRemoved)
        if try stage.info("tree") != nil {
            try LibraryTrees.purge(stage.child("tree"))
            try stage.remove("tree", directory: true)
        }
        for name in try stage.entries(maximum: LibraryBounds.changes * 2 + 64) { try stage.remove(name) }
        try operations.remove(intent.operationId, directory: true)
    }

    func treeLocation(_ intent: LibraryTransaction, stage: LibraryDirectory) throws -> String {
        var found: [(String, LibraryDirectory)] = []
        func probe(_ path: String, tag: String) throws {
            let (parent, name) = try MutationPath.parent(library, path, file: false)
            let matches = try parent.entries().filter { LibraryNames.key($0) == LibraryNames.key(name) }
            guard matches.count <= 1 else { throw NativeLibraryError.integrity }
            if let actual = matches.first {
                if actual.utf8.elementsEqual(name.utf8) {
                    found.append((tag, try parent.child(name)))
                } else {
                    let actualPath = MutationPath.join(
                        String(path.split(separator: "/").dropLast().joined(separator: "/")), actual)
                    guard actualPath == intent.sourceFolder || actualPath == intent.destinationFolder else {
                        throw NativeLibraryError.integrity
                    }
                }
            }
        }
        if let source = intent.sourceFolder { try probe(source, tag: "source") }
        if let destination = intent.destinationFolder { try probe(destination, tag: "destination") }
        if try stage.info("tree") != nil { found.append(("stage", try stage.child("tree"))) }
        guard found.count == 1, let location = found.first, let expected = intent.tree?.withoutFinderMetadata,
            try LibraryTrees.inventory(location.1, identity: expected.rootInode != nil) == expected
        else { throw NativeLibraryError.integrity }
        return location.0
    }

    func validateCacheItem(_ id: String) throws {
        guard LibraryRecords.validUUID(id) else { throw NativeLibraryError.invalidInput }
        if try cache.info(id) != nil { _ = try LibraryTrees.stamps(cache.child(id)) }
    }

    func purgeCacheItem(_ id: String) throws {
        try validateCacheItem(id)
        guard try cache.info(id) != nil else { return }
        try LibraryTrees.purge(cache.child(id))
        try cache.remove(id, directory: true)
    }

    func validateUnpublishedStage(_ stage: LibraryDirectory) throws {
        for name in try stage.entries(maximum: LibraryBounds.changes * 2 + 64) {
            if name == "tree" {
                _ = try LibraryTrees.stamps(stage.child(name), depth: LibraryBounds.folderDepth)
                continue
            }
            if name == "removed" {
                try validateRemoved(stage)
                continue
            }
            let indexed = ["before-", "after-"].contains { prefix in
                name.hasPrefix(prefix) && name.dropFirst(prefix.count).count == 6
                    && name.dropFirst(prefix.count).utf8.allSatisfy { (48...57).contains($0) }
            }
            guard
                ["source.txt", "metadata.json", "intent.pending"].contains(name) || indexed
                    || validPublicationTemporary(name),
                let info = try stage.info(name), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
                info.st_size <= BlueprintCodecLimits.standard.sourceBytes
            else { throw NativeLibraryError.recoveryRequired }
        }
    }
}

/// Where the originals of a deleted or replaced item went (spec ORG-9).
public enum LibraryRemovalPlace: String, Codable, Sendable {
    /// The macOS Trash (or `FB_NATIVE_TRASH_DIRECTORY`).
    case trash
    /// `operations-quarantine/` inside the library, because the Trash refused them.
    case quarantine
}

/// The result of replacing an item's source.
public struct LibraryReplacement: Sendable {
    public let item: LibraryItem
    /// Comments whose book entries no longer exist, now on the root with a `[Former book entry …]` prefix.
    public let promotedComments: Int
    public let originals: LibraryRemovalPlace
}

/// Exact preimages of a deleted or replaced item, staged as one folder for the Trash.
struct LibraryRemovedItem {
    let folder: String
    let files: [(String, Data)]
}

extension NativeLibrary {
    func validateRemoved(_ stage: LibraryDirectory) throws {
        guard let info = try stage.info("removed"), info.st_mode & S_IFMT == S_IFDIR else {
            throw NativeLibraryError.unsafePath
        }
        let members = try LibraryTrees.stamps(stage.child("removed"), depth: 1)
        guard members.count <= 64, members.allSatisfy({ $0.bytes <= BlueprintCodecLimits.standard.sourceBytes }) else {
            throw NativeLibraryError.recoveryRequired
        }
    }

    /// Moves staged preimages to the Trash. If the Trash cannot take them, they move to
    /// `operations-quarantine/` instead, so an unavailable Trash never blocks the library.
    func retainRemoved(_ stage: LibraryDirectory, operationId: String) throws {
        guard try stage.info("removed") != nil else { return }
        try validateRemoved(stage)
        let removed = try stage.child("removed")
        for name in try removed.entries() {
            try LibraryNames.validateBasename(name)
            let source = removed.url.appendingPathComponent(name)
            do {
                try Self.moveToTrash(source, name: name, operationId: operationId)
            } catch {
                let quarantine = try root.child(Self.quarantineName, create: true)
                try removed.move(name, to: quarantine, as: "\(operationId) \(name)")
                removedToQuarantine = true
            }
            try hook?(.removedRetained)
        }
        try stage.remove("removed", directory: true)
    }

    /// `FB_NATIVE_TRASH_DIRECTORY` redirects removed items for tests and development; otherwise the macOS Trash.
    static func moveToTrash(_ source: URL, name: String, operationId: String) throws {
        if let override = ProcessInfo.processInfo.environment["FB_NATIVE_TRASH_DIRECTORY"], override.hasPrefix("/") {
            let directory = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var destination = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = directory.appendingPathComponent("\(name) \(operationId)")
            }
            try FileManager.default.moveItem(at: source, to: destination)
        } else {
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
        }
    }

    static func removedFolderName(_ basename: String, action: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        // Keep the folder name within one filename component (255 bytes) for any valid basename.
        var name = ""
        for character in basename {
            guard name.utf8.count + character.utf8.count <= 180 else { break }
            name.append(character)
        }
        return "\(name) (\(action) \(formatter.string(from: Date())) UTC)"
    }
}
