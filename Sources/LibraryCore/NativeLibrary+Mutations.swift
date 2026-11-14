import Foundation

public struct UnpackedImport: Codable, Sendable {
    public let folder: String
    public let folderCount: Int
    public let itemCount: Int
}

extension NativeLibrary {
    func vacant(_ parent: LibraryDirectory, names: [String], allowing: [String] = []) throws {
        let existing = try parent.entries()
        for name in names {
            for actual in existing where LibraryNames.key(actual) == LibraryNames.key(name) {
                guard allowing.contains(where: { $0.utf8.elementsEqual(actual.utf8) }) else {
                    throw NativeLibraryError.nameCollision
                }
            }
        }
    }

    func named(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            name.count <= 1024, name.utf8.count <= LibraryBounds.metadata
        else { throw NativeLibraryError.invalidInput }
    }

    public func createFolder(parent: String = "", name: String) throws -> String {
        try queue.sync {
            try ready()
            try LibraryNames.validateBasename(name)
            let path = MutationPath.join(parent, name)
            _ = try LibraryNames.folderComponents(path)
            try vacant(directory(at: parent), names: [name])
            try commitTree(kind: "tree-create", source: nil, destination: path)
            return path
        }
    }

    public func moveFolder(_ folder: String, parent: String, name: String? = nil) throws -> String {
        try queue.sync {
            try ready()
            let parts = try LibraryNames.folderComponents(folder)
            guard let oldName = parts.last else { throw NativeLibraryError.invalidInput }
            _ = try directory(at: folder)
            let newName = name ?? oldName
            try LibraryNames.validateBasename(newName)
            let destination = MutationPath.join(parent, newName)
            _ = try LibraryNames.folderComponents(destination)
            guard LibraryNames.key(parent) != LibraryNames.key(folder),
                !LibraryNames.key(parent).hasPrefix(LibraryNames.key(folder) + "/")
            else { throw NativeLibraryError.invalidInput }
            if destination.utf8.elementsEqual(folder.utf8) { return folder }
            let oldParent = parts.dropLast().joined(separator: "/")
            try vacant(directory(at: parent), names: [newName], allowing: parent == oldParent ? [oldName] : [])
            // Validate the resulting depth as well as the moved root.
            let inventory = try LibraryTrees.inventory(directory(at: folder), identity: true)
            for path in inventory.directories { _ = try LibraryNames.folderComponents(destination + "/" + path) }
            for file in inventory.files { _ = try MutationPath.parts(destination + "/" + file.path, file: true) }
            try commitTree(kind: "tree-move", source: folder, destination: destination)
            return destination
        }
    }

    public func deleteFolder(_ folder: String) throws {
        try queue.sync {
            try ready()
            guard !folder.isEmpty else { throw NativeLibraryError.invalidInput }
            let selected = try directory(at: folder)
            for name in try selected.entries() {
                switch name {
                case ".folder.json":
                    _ = try LibraryRecords.folderMetadata(selected.read(name, maximum: LibraryBounds.metadata))
                default: throw NativeLibraryError.folderNotEmpty
                }
            }
            try commitTree(kind: "tree-delete", source: folder, destination: nil)
        }
    }

    public func moveItem(id: String, folder: String) throws -> LibraryItem {
        try queue.sync {
            try ready()
            let (found, document, metadata) = try load(id: id)
            return try relocate(
                found, document: document, originalMetadata: metadata, folder: folder,
                basename: found.basename, updatedMetadata: metadata)
        }
    }

    public func renameItem(id: String, name: String) throws -> LibraryItem {
        try queue.sync {
            try ready()
            try named(name)
            let (found, document, before) = try load(id: id)
            let metadata = LibraryItemMetadata(
                schemaVersion: 1, id: found.id, createdAt: found.metadata.createdAt,
                updatedAt: max(LibraryRecords.now(), found.metadata.updatedAt),
                sourceSha256: found.metadata.sourceSha256,
                displayNameOverride: name, comments: found.metadata.comments)
            let after = try LibraryRecords.encode(metadata, maximum: LibraryBounds.metadata)
            return try relocate(
                found, document: document, originalMetadata: before, folder: found.folder,
                basename: LibraryNames.basename(label: name, kind: document.root.kind), updatedMetadata: after)
        }
    }

    func relocate(
        _ found: LibraryItem, document: BlueprintDocument, originalMetadata: Data,
        folder: String, basename: String, updatedMetadata: Data
    ) throws -> LibraryItem {
        let destination = try directory(at: folder)
        try vacant(
            destination, names: [basename + ".txt", basename + ".json"],
            allowing: folder == found.folder ? [found.basename + ".txt", found.basename + ".json"] : [])
        let oldBase = MutationPath.join(found.folder, found.basename)
        let newBase = MutationPath.join(folder, basename)
        if oldBase.utf8.elementsEqual(newBase.utf8) {
            if originalMetadata != updatedMetadata {
                try commitChanges([
                    PreparedLibraryChange(path: oldBase + ".json", before: originalMetadata, after: updatedMetadata)
                ])
            }
        } else {
            try commitChanges([
                PreparedLibraryChange(path: oldBase + ".txt", before: document.original.bytes, after: nil),
                PreparedLibraryChange(path: oldBase + ".json", before: originalMetadata, after: nil),
                PreparedLibraryChange(path: newBase + ".txt", before: nil, after: document.original.bytes),
                PreparedLibraryChange(path: newBase + ".json", before: nil, after: updatedMetadata),
            ])
            itemPaths?[found.id] = [newBase]
        }
        return item(
            metadata: try LibraryRecords.metadata(updatedMetadata), document: document, folder: folder,
            basename: basename)
    }

    public func deleteItem(id: String) throws {
        try queue.sync {
            try ready()
            let (found, document, metadata) = try load(id: id)
            let base = MutationPath.join(found.folder, found.basename)
            let removed = LibraryRemovedItem(
                folder: Self.removedFolderName(found.basename, action: "deleted"),
                files: [(found.basename + ".txt", document.original.bytes), (found.basename + ".json", metadata)])
            try commitChanges(
                [
                    PreparedLibraryChange(path: base + ".txt", before: document.original.bytes, after: nil),
                    PreparedLibraryChange(path: base + ".json", before: metadata, after: nil),
                ], cacheIds: [id], removed: removed)
            itemPaths?[id] = nil
        }
    }

    public func updateSource(id: String, bytes: Data) throws -> LibraryItem {
        try queue.sync {
            try ready()
            let document = try BlueprintCodec.decode(bytes)
            let (found, oldDocument, before) = try load(id: id)
            let comments = try found.metadata.comments.map { comment -> LibraryComment in
                if (try? document.entry(at: comment.entryPath)) != nil { return comment }
                let text =
                    "[Former book entry \(comment.entryPath.map(String.init).joined(separator: "."))]\n\n"
                    + comment.text
                guard text.utf8.count <= LibraryBounds.comment else { throw NativeLibraryError.limitExceeded }
                return LibraryComment(id: comment.id, entryPath: [], text: text, createdAt: comment.createdAt)
            }
            let metadata = LibraryItemMetadata(
                schemaVersion: 1, id: found.id, createdAt: found.metadata.createdAt,
                updatedAt: max(LibraryRecords.now(), found.metadata.updatedAt), sourceSha256: document.original.sha256,
                displayNameOverride: found.metadata.displayNameOverride, comments: comments)
            let after = try LibraryRecords.encode(metadata, maximum: LibraryBounds.metadata)
            let base = MutationPath.join(found.folder, found.basename)
            let removed = LibraryRemovedItem(
                folder: Self.removedFolderName(found.basename, action: "replaced"),
                files: [
                    (found.basename + ".txt", oldDocument.original.bytes), (found.basename + ".json", before),
                ])
            try commitChanges(
                [
                    PreparedLibraryChange(path: base + ".txt", before: oldDocument.original.bytes, after: bytes),
                    PreparedLibraryChange(path: base + ".json", before: before, after: after),
                ], cacheIds: [id], removed: removed)
            return item(metadata: metadata, document: document, folder: found.folder, basename: found.basename)
        }
    }

    public func deleteComment(id: String, commentId: String) throws -> LibraryItem {
        try queue.sync {
            try ready()
            guard LibraryRecords.validUUID(commentId) else { throw NativeLibraryError.invalidInput }
            let (found, document, before) = try load(id: id)
            guard found.metadata.comments.contains(where: { $0.id == commentId }) else {
                throw NativeLibraryError.notFound
            }
            var metadata = found.metadata
            metadata.comments.removeAll { $0.id == commentId }
            metadata.updatedAt = max(LibraryRecords.now(), metadata.updatedAt)
            try commitChanges([
                PreparedLibraryChange(
                    path: MutationPath.join(found.folder, found.basename + ".json"), before: before,
                    after: LibraryRecords.encode(metadata, maximum: LibraryBounds.metadata))
            ])
            return item(metadata: metadata, document: document, folder: found.folder, basename: found.basename)
        }
    }

    public func export(id: String, entryPath: [Int] = [], to url: URL) throws -> Int {
        try queue.sync {
            try ready()
            try LibraryDirectory.validateURL(url)
            let (_, document, _) = try load(id: id)
            let bytes = try document.export(at: entryPath)
            let parent = try LibraryDirectory(url: url.deletingLastPathComponent())
            // Export must not bypass authoritative storage or the asset/cache boundaries.
            let managed = root.url.path
            guard parent.url.path != managed, !parent.url.path.hasPrefix(managed + "/") else {
                throw NativeLibraryError.unsafePath
            }
            try parent.writeNew(url.lastPathComponent, data: bytes)
            return bytes.count
        }
    }

    public func importUnpacked(_ bytes: Data, folder: String = "") throws -> UnpackedImport {
        try queue.sync {
            try ready()
            let document = try BlueprintCodec.decode(bytes)
            guard document.root.kind == .book else { throw NativeLibraryError.invalidInput }
            let parent = try directory(at: folder)
            let base = LibraryNames.basename(label: document.root.label, kind: .book)
            let existing = Set(try parent.entries().map(LibraryNames.key))
            var name = base
            var suffix = 2
            while existing.contains(LibraryNames.key(name)) {
                guard suffix <= LibraryBounds.directoryEntries else { throw NativeLibraryError.limitExceeded }
                name = "\(base) (\(suffix))"
                suffix += 1
            }
            let destination = MutationPath.join(folder, name)
            _ = try LibraryNames.folderComponents(destination)
            var directories: [String] = []
            var files: [String: Data] = [:]
            var items = 0
            var total = 0
            let now = LibraryRecords.now()
            func put(_ data: Data, at path: String) throws {
                total += data.count
                guard total <= LibraryBounds.transactionBytes else { throw NativeLibraryError.limitExceeded }
                files[path] = data
            }
            func book(_ entry: BlueprintEntry, path: String) throws {
                _ = try LibraryNames.folderComponents(path.isEmpty ? destination : MutationPath.join(destination, path))
                if !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let record = LibraryFolderMetadata(schemaVersion: 1, comment: entry.description, createdAt: now)
                    let data = try LibraryRecords.encode(record, maximum: LibraryBounds.metadata)
                    _ = try LibraryRecords.folderMetadata(data)
                    try put(data, at: MutationPath.join(path, ".folder.json"))
                }
                for value in entry.body["blueprints"]?.array ?? [] {
                    let index = value["index"]!.safeInteger!
                    let child = try BlueprintEntry(value: value, path: entry.path + [index])
                    let prefix = "\(index) - "
                    var label = ""
                    for character in LibraryNames.basename(label: child.label, kind: child.kind) {
                        if (prefix + label + String(character)).utf8.count > 180 { break }
                        label.append(character)
                    }
                    while label.hasSuffix(".") || label.hasSuffix(" ") { label.removeLast() }
                    let childName = prefix + (label.isEmpty ? "_" : label)
                    let relative = MutationPath.join(path, childName)
                    if child.kind == .book {
                        directories.append(relative)
                        try book(child, path: relative)
                    } else {
                        _ = try MutationPath.parts(MutationPath.join(destination, relative + ".txt"), file: true)
                        let source = try document.standaloneSource(for: child)
                        let metadata = LibraryItemMetadata(
                            schemaVersion: 1, id: LibraryRecords.uuid(), createdAt: now,
                            updatedAt: now, sourceSha256: OriginalSource(bytes: source).sha256,
                            displayNameOverride: nil, comments: [])
                        try put(source, at: relative + ".txt")
                        try put(
                            LibraryRecords.encode(metadata, maximum: LibraryBounds.metadata), at: relative + ".json")
                        items += 1
                    }
                }
            }
            try book(document.root, path: "")
            try commitTree(
                kind: "tree-create", source: nil, destination: destination, directories: directories, files: files)
            return UnpackedImport(folder: destination, folderCount: directories.count + 1, itemCount: items)
        }
    }
}
