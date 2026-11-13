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

/// A snapshot of one item's source, taken on the owner queue. Rendering happens off the queue;
/// every cache read and publication re-enters the queue and revalidates the snapshot.
package final class LibraryPreviewContext: @unchecked Sendable {
    private unowned let owner: NativeLibrary
    package let itemId: String
    package let source: Data
    package let entryPath: [Int]
    package let sourceSha256: String
    private let lock = NSLock()
    private var active = true

    init(owner: NativeLibrary, item: LibraryItem, source: Data, entryPath: [Int]) {
        self.owner = owner
        itemId = item.id
        self.source = source
        self.entryPath = entryPath
        sourceSha256 = item.metadata.sourceSha256
    }

    func finish() {
        lock.lock()
        active = false
        lock.unlock()
    }

    private func onQueue<T>(_ body: () throws -> T) throws -> T {
        try owner.queue.sync {
            lock.lock()
            let isActive = active
            lock.unlock()
            guard isActive else { throw NativeLibraryError.closed }
            try owner.ready()
            return try body()
        }
    }

    private func check(_ identity: LibraryCacheIdentity) throws {
        dispatchPrecondition(condition: .onQueue(owner.queue))
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
        try onQueue {
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
    }

    package func publish(_ identity: LibraryCacheIdentity, image: Data, report: Data) throws {
        try onQueue {
            try check(identity)
            guard !image.isEmpty, image.count <= 64 * 1024 * 1024, report.count <= 2 * 1024 * 1024 else {
                throw NativeLibraryError.limitExceeded
            }
            _ = try LibraryRecords.parse(report, maximum: 2 * 1024 * 1024)
            // Rendering ran off the queue: refuse pixels for a source that changed or disappeared meanwhile.
            let current: LibraryItem
            do { current = try owner.load(id: itemId).0 } catch NativeLibraryError.notFound {
                throw NativeLibraryError.sourceChanged
            }
            guard current.metadata.sourceSha256 == sourceSha256 else { throw NativeLibraryError.sourceChanged }
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
                try owner.ready()
                try check(identity)
                let current =
                    try directory.info(name) == nil
                    ? nil : directory.fingerprint(name, maximum: 64 * 1024 * 1024).sha256
                guard current == before[name] else { throw NativeLibraryError.integrity }
                try directory.move(temporary, to: directory, as: name, replacing: current != nil)
            }
            try install(imageTemporary, name: key + ".png")
            try owner.hook?(.previewImagePublished)
            try install(metadataTemporary, name: key + ".json")
            try owner.hook?(.previewManifestPublished)
        }
    }

    package func willStartWorker() throws {
        try onQueue { try owner.hook?(.previewWorkerStarting) }
    }
}

extension NativeLibrary {
    /// Takes a source snapshot on the queue, then runs `body` off the queue so other operations proceed.
    /// Close cancels the render through `onCancel` and waits until `body` returns.
    package func withPreviewContext<T>(
        id: String, entryPath: [Int], onCancel: @escaping @Sendable () -> Void,
        _ body: (LibraryPreviewContext) throws -> T
    ) throws -> T {
        let activity = UUID()
        lifecycleLock.lock()
        guard !closing else {
            lifecycleLock.unlock()
            throw NativeLibraryError.closed
        }
        previewCancellations[activity] = onCancel
        previewActivity.enter()
        lifecycleLock.unlock()
        defer {
            lifecycleLock.lock()
            previewCancellations[activity] = nil
            lifecycleLock.unlock()
            previewActivity.leave()
        }
        let context = try queue.sync {
            try ready()
            let (item, document, _) = try load(id: id)
            _ = try document.entry(at: entryPath)
            return LibraryPreviewContext(owner: self, item: item, source: document.original.bytes, entryPath: entryPath)
        }
        defer { context.finish() }
        return try body(context)
    }
}
