import Foundation

/// Versioned derived metadata, independent of authoritative item schemas and journals.
struct LibraryPreviewManifest: Codable {
    let schemaVersion: Int
    let identity: LibraryCacheIdentity
    let imageSha256: String
    let imageBytes: Int
    let report: Data
    let reportSha256: String

    static func read(_ bytes: Data) throws -> Self {
        let value = try LibraryRecords.parse(bytes, maximum: LibraryBounds.metadata)
        try LibraryRecords.fields(
            value, required: ["schemaVersion", "identity", "imageSha256", "imageBytes", "report", "reportSha256"])
        guard value["schemaVersion"]?.safeInteger == 2 else { throw NativeLibraryError.unsupportedVersion }
        guard value["imageBytes"]?.safeInteger != nil,
            let identity = value["identity"]
        else { throw NativeLibraryError.invalidMetadata }
        _ = try LibraryCacheIdentity.read(identity.encoded(maximum: LibraryBounds.journal))
        guard let record = try? JSONDecoder().decode(Self.self, from: bytes),
            LibraryRecords.validHash(record.imageSha256), LibraryRecords.validHash(record.reportSha256),
            (1...64 * 1024 * 1024).contains(record.imageBytes), record.report.count <= 2 * 1024 * 1024,
            OriginalSource(bytes: record.report).sha256 == record.reportSha256
        else { throw NativeLibraryError.invalidMetadata }
        return record
    }
}

enum LibraryCacheRecords {
    static func identity(_ bytes: Data) throws -> LibraryCacheIdentity {
        let value = try LibraryRecords.parse(bytes, maximum: LibraryBounds.metadata)
        if value["schemaVersion"]?.safeInteger == 1 { return try LibraryCacheIdentity.read(bytes) }
        return try LibraryPreviewManifest.read(bytes).identity
    }
}

package struct LibraryPreviewCacheBytes {
    package let image: Data
    package let report: Data
}

/// Valid only on the owning library queue, during withPreviewContext.
package final class LibraryPreviewContext {
    private unowned let owner: NativeLibrary
    package let itemId: String
    package let source: Data
    package let entryPath: [Int]
    package let sourceSha256: String
    private var active = true

    init(owner: NativeLibrary, item: LibraryItem, source: Data, entryPath: [Int]) {
        self.owner = owner
        itemId = item.id
        self.source = source
        self.entryPath = entryPath
        sourceSha256 = item.metadata.sourceSha256
    }

    func finish() { active = false }

    private func check(_ identity: LibraryCacheIdentity) throws {
        dispatchPrecondition(condition: .onQueue(owner.queue))
        guard active else { throw NativeLibraryError.closed }
        try owner.ready()
        try identity.validate()
        guard identity.itemId == itemId, identity.entryPath == entryPath, identity.sourceSha256 == sourceSha256 else {
            throw NativeLibraryError.integrity
        }
    }

    package func checkAssets(_ url: URL) throws {
        let assets = try LibraryDirectory(url: url).url.path
        let root = owner.root.url.path
        guard assets != root, !assets.hasPrefix(root + "/"), !root.hasPrefix(assets + "/") else {
            throw NativeLibraryError.unsafePath
        }
    }

    private func directory(create: Bool) throws -> LibraryDirectory? {
        let matches = try owner.cache.entries().filter { LibraryNames.key($0) == itemId }
        guard matches.count <= 1, matches.first.map({ $0.utf8.elementsEqual(itemId.utf8) }) ?? true else {
            throw NativeLibraryError.unsafePath
        }
        if matches.isEmpty && !create { return nil }
        return try owner.cache.child(itemId, create: create)
    }

    private func checkNames(_ directory: LibraryDirectory, key: String) throws {
        for name in [key + ".png", key + ".json"] {
            let matches = try directory.entries().filter { LibraryNames.key($0) == name }
            guard matches.count <= 1, matches.first.map({ $0.utf8.elementsEqual(name.utf8) }) ?? true else {
                throw NativeLibraryError.unsafePath
            }
        }
    }

    private func manifest(_ directory: LibraryDirectory, identity: LibraryCacheIdentity) throws -> (
        record: LibraryPreviewManifest?, hash: String?
    ) {
        let key = try identity.key()
        try checkNames(directory, key: key)
        guard try directory.info(key + ".json") != nil else { return (nil, nil) }
        let bytes = try directory.read(key + ".json", maximum: LibraryBounds.metadata)
        let saved = try LibraryCacheRecords.identity(bytes)
        guard try saved.key() == key else { throw NativeLibraryError.integrity }
        let value = try LibraryRecords.parse(bytes, maximum: LibraryBounds.metadata)
        let hash = OriginalSource(bytes: bytes).sha256
        if value["schemaVersion"]?.safeInteger == 1 { return (nil, hash) }
        return (try LibraryPreviewManifest.read(bytes), hash)
    }

    package func cached(_ identity: LibraryCacheIdentity) throws -> LibraryPreviewCacheBytes? {
        try check(identity)
        guard let directory = try directory(create: false) else { return nil }
        let record = try manifest(directory, identity: identity).record
        let name = try identity.key() + ".png"
        guard try directory.info(name) != nil else { return nil }
        let bytes = try directory.read(name, maximum: 64 * 1024 * 1024)
        guard let record, bytes.count == record.imageBytes,
            OriginalSource(bytes: bytes).sha256 == record.imageSha256
        else { return nil }
        return LibraryPreviewCacheBytes(image: bytes, report: record.report)
    }

    package func publish(_ identity: LibraryCacheIdentity, image: Data, report: Data) throws {
        try check(identity)
        guard !image.isEmpty, image.count <= 64 * 1024 * 1024, report.count <= 2 * 1024 * 1024 else {
            throw NativeLibraryError.limitExceeded
        }
        _ = try LibraryRecords.parse(report, maximum: 2 * 1024 * 1024)
        // Detect concurrent external changes rather than binding stale pixels to a changed item.
        let (current, _, _) = try owner.load(id: itemId)
        guard current.metadata.sourceSha256 == sourceSha256 else { throw NativeLibraryError.integrity }
        guard let directory = try directory(create: true) else { throw NativeLibraryError.integrity }
        // Bind the precondition to the validated bytes.
        let metadataBefore = try manifest(directory, identity: identity).hash
        let key = try identity.key()
        var before: [String: String] = [:]
        before[key + ".json"] = metadataBefore
        for (name, maximum) in [(key + ".png", 64 * 1024 * 1024)] {
            if try directory.info(name) != nil {
                before[name] = try directory.fingerprint(name, maximum: maximum).sha256
            }
        }
        let record = LibraryPreviewManifest(
            schemaVersion: 2, identity: identity, imageSha256: OriginalSource(bytes: image).sha256,
            imageBytes: image.count, report: report, reportSha256: OriginalSource(bytes: report).sha256)
        let metadata = try LibraryRecords.encode(record, maximum: LibraryBounds.metadata)
        _ = try LibraryPreviewManifest.read(metadata)
        let imageTemporary = ".tmp-" + LibraryRecords.uuid()
        let metadataTemporary = ".tmp-" + LibraryRecords.uuid()
        try directory.writeNew(imageTemporary, data: image)
        try owner.hook?(.previewImageStaged)
        try directory.writeNew(metadataTemporary, data: metadata)
        try owner.hook?(.previewManifestStaged)
        func install(_ temporary: String, name: String) throws {
            try check(identity)
            let current =
                try directory.info(name) == nil ? nil : directory.fingerprint(name, maximum: 64 * 1024 * 1024).sha256
            guard current == before[name] else { throw NativeLibraryError.integrity }
            try directory.move(temporary, to: directory, as: name, replacing: current != nil)
        }
        try install(imageTemporary, name: key + ".png")
        try owner.hook?(.previewImagePublished)
        try install(metadataTemporary, name: key + ".json")
        try owner.hook?(.previewManifestPublished)
    }

    package func willStartWorker() throws {
        try owner.ready()
        try owner.hook?(.previewWorkerStarting)
    }
}

extension NativeLibrary {
    package func withPreviewContext<T>(
        id: String, entryPath: [Int], onCancel: @escaping @Sendable () -> Void,
        _ body: (LibraryPreviewContext) throws -> T
    ) throws -> T {
        try queue.sync {
            try ready()
            lifecycleLock.lock()
            guard !closing else {
                lifecycleLock.unlock()
                throw NativeLibraryError.closed
            }
            previewCancellation = onCancel
            lifecycleLock.unlock()
            defer {
                lifecycleLock.lock()
                previewCancellation = nil
                lifecycleLock.unlock()
            }
            let (item, document, _) = try load(id: id)
            _ = try document.entry(at: entryPath)
            let context = LibraryPreviewContext(
                owner: self, item: item, source: document.original.bytes, entryPath: entryPath)
            defer { context.finish() }
            return try body(context)
        }
    }
}
