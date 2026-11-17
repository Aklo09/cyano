import Darwin
import Dispatch
import Foundation

@_spi(Testing) public enum LibraryWritePhase: String, CaseIterable, Sendable {
    case formatPublished, formatMigrationStaged, formatMigrated, sourceStaged, metadataStaged, intentPublished
    case sourcePublished, metadataPublished, intentRemoved
    case changesStaged, fileRemoved, filePublished, treeStaged, treeWithdrawn, treePublished, cacheRemoved
    case previewImageStaged, previewManifestStaged, previewImagePublished, previewManifestPublished
    case previewWorkerStarting, removedRetained
}

/// Owns one local library until close. Every complete operation runs on one serial queue.
public final class NativeLibrary: @unchecked Sendable {
    let queue = DispatchQueue(label: "cyano.library")
    let root: LibraryDirectory
    let lease: LibraryLease
    let library: LibraryDirectory
    let operations: LibraryDirectory
    let cache: LibraryDirectory
    let formatBytes: Data
    let hook: ((LibraryWritePhase) throws -> Void)?
    var needsRecovery = false
    /// Set by the last commit when the Trash refused removed originals; read on the queue right after it.
    var removedToQuarantine = false
    /// Committed operations that opening this session replayed, oldest directory name first. An interrupted change
    /// was completed for each; applications tell the owner (spec REC-1). Empty when nothing was pending.
    public private(set) var completedOnOpen: [LibraryOperationRecord] = []
    /// Item ID to relative "folder/basename" paths, built by the first full scan and kept current by this
    /// session's own mutations. External edits are unsupported while owned; every hit is still re-verified.
    var itemPaths: [String: [String]]?
    let lifecycleLock = NSLock()
    var closing = false
    /// Renders run off the serial queue; close cancels each one and waits for its cleanup.
    var previewCancellations: [UUID: @Sendable () -> Void] = [:]
    let previewActivity = DispatchGroup()
    package var isClosing: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return closing
    }

    public convenience init(at url: URL) throws {
        try self.init(at: url, initializing: false, hook: nil)
    }

    public static func initialize(at url: URL) throws -> NativeLibrary {
        try NativeLibrary(at: url, initializing: true, hook: nil)
    }

    @_spi(Testing) public static func testingOpen(
        at url: URL, initializing: Bool = false,
        hook: @escaping (LibraryWritePhase) throws -> Void
    ) throws -> NativeLibrary {
        try NativeLibrary(at: url, initializing: initializing, hook: hook)
    }

    private init(at url: URL, initializing: Bool, hook: ((LibraryWritePhase) throws -> Void)?) throws {
        try LibraryDirectory.validateURL(url)
        if initializing, !FileManager.default.fileExists(atPath: url.path) {
            let parent = try LibraryDirectory(url: url.deletingLastPathComponent())
            try parent.qualify()
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try parent.sync()
        }
        let root = try LibraryDirectory(url: url)
        try root.qualify()
        let initial = try root.entries()
        let recognized = try root.info(".library-format.json") != nil
        if recognized {
            _ = try LibraryRecords.format(root.read(".library-format.json", maximum: LibraryBounds.journal))
        }
        if !recognized {
            guard initializing, Set(initial).isSubset(of: [".owner.lock", ".format.pending"]),
                initial.isEmpty || initial.contains(".format.pending")
            else {
                throw NativeLibraryError.invalidFormat
            }
            // Bootstrap only a native identity before ownership, never library content.
            // A bare foreign .owner.lock cannot identify a native initialization.
            if initial.isEmpty {
                do {
                    try root.writeNew(
                        ".format.pending",
                        data: LibraryRecords.encode(LibraryFormat.fresh(), maximum: LibraryBounds.journal))
                } catch NativeLibraryError.io(EEXIST) {
                    // A competing initializer published the same control location.
                }
            }
            _ = try LibraryRecords.format(root.read(".format.pending", maximum: LibraryBounds.journal))
        }
        let lease = try LibraryLease(directory: root, create: initializing && !recognized)
        do {
            if try root.info(".library-format.json") == nil {
                guard initializing else { throw NativeLibraryError.invalidFormat }
                let existing = try root.entries()
                guard Set(existing).isSubset(of: [".owner.lock", ".format.pending"]) else {
                    throw NativeLibraryError.invalidFormat
                }
                _ = try LibraryRecords.format(root.read(".format.pending", maximum: LibraryBounds.journal))
                try root.move(".format.pending", to: root, as: ".library-format.json")
                try root.barrier()
                try hook?(.formatPublished)
            }
            var formatBytes = try root.read(".library-format.json", maximum: LibraryBounds.journal)
            let format = try LibraryRecords.format(formatBytes)
            if format.format != LibraryFormat.current {
                formatBytes = try Self.migrateFormat(format, in: root, hook: hook)
            }
            guard Set(try root.entries()).isSubset(of: Self.allowedRootEntries) else {
                throw NativeLibraryError.invalidFormat
            }
            self.root = root
            self.lease = lease
            self.formatBytes = formatBytes
            self.hook = hook
            library = try root.child("library", create: true)
            operations = try root.child("operations", create: true)
            cache = try root.child("cache", create: true)
            try root.sync()
            completedOnOpen = try replay()
        } catch {
            lease.close()
            throw error
        }
    }

    deinit { lease.close() }

    static let formatMigrationName = ".format.migrating"

    /// Rewrites a marker from before the rename to the current format name, keeping its identity and version.
    /// The new marker is staged beside the old one and replaces it in one rename, so an interruption leaves one
    /// complete marker. A stage left behind holds nothing the old marker lacks, so it is removed and staged again.
    private static func migrateFormat(
        _ record: LibraryFormat, in root: LibraryDirectory, hook: ((LibraryWritePhase) throws -> Void)?
    ) throws -> Data {
        let migrated = LibraryFormat(
            format: LibraryFormat.current, schemaVersion: record.schemaVersion, id: record.id,
            createdAt: record.createdAt)
        let bytes = try LibraryRecords.encode(migrated, maximum: LibraryBounds.journal)
        if try root.info(formatMigrationName) != nil { try root.remove(formatMigrationName) }
        try root.writeNew(formatMigrationName, data: bytes)
        try hook?(.formatMigrationStaged)
        try root.move(formatMigrationName, to: root, as: ".library-format.json", replacing: true)
        try root.barrier()
        try hook?(.formatMigrated)
        return bytes
    }

    public func close() {
        lifecycleLock.lock()
        closing = true
        let cancellations = Array(previewCancellations.values)
        lifecycleLock.unlock()
        for cancel in cancellations { cancel() }
        previewActivity.wait()
        queue.sync { lease.close() }
    }

    public static func inspectOwnership(at url: URL) throws -> LibraryOwnershipStatus {
        try LibraryDirectory.validateURL(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return .uninitialized }
        let directory = try LibraryDirectory(url: url)
        try directory.qualify()
        let recognized = try directory.info(".library-format.json") != nil
        if recognized {
            _ = try LibraryRecords.format(directory.read(".library-format.json", maximum: LibraryBounds.journal))
        } else {
            let names = try directory.entries()
            guard
                names.isEmpty
                    || (names.contains(".format.pending")
                        && Set(names).isSubset(of: [".format.pending", ".owner.lock"]))
            else {
                throw NativeLibraryError.invalidFormat
            }
            if names.contains(".format.pending") {
                _ = try LibraryRecords.format(directory.read(".format.pending", maximum: LibraryBounds.journal))
            }
        }
        guard try directory.info(".owner.lock") != nil else {
            if recognized { throw NativeLibraryError.unsafePath }
            return .uninitialized
        }
        do {
            let lease = try LibraryLease(directory: directory, create: false)
            defer { lease.close() }
            return try directory.info(".library-format.json") == nil ? .uninitialized : .idle
        } catch NativeLibraryError.inUse { return .owned }
    }

    public static func readSourceFile(at url: URL) throws -> Data {
        try LibraryDirectory.validateURL(url)
        let directory = try LibraryDirectory(url: url.deletingLastPathComponent())
        return try directory.read(url.lastPathComponent, maximum: BlueprintCodecLimits.standard.sourceBytes)
    }

    public func list() throws -> LibraryListing {
        try queue.sync {
            try ready()
            return try listing()
        }
    }

    /// Whether a failed mutation has blocked this session until `recover()` succeeds (spec REC-5).
    public var requiresRecovery: Bool { queue.sync { needsRecovery } }

    /// Replays committed operations and returns those it completed.
    @discardableResult public func recover() throws -> [LibraryOperationRecord] {
        try queue.sync {
            guard !isClosing else { throw NativeLibraryError.closed }
            try checkControls()
            itemPaths = nil
            do {
                let completed = try replay()
                needsRecovery = false
                return completed
            } catch {
                needsRecovery = true
                throw error
            }
        }
    }

    public func importSource(_ bytes: Data, name: String? = nil, folder: String = "") throws -> LibraryItem {
        try queue.sync {
            try ready()
            let document = try BlueprintCodec.decode(bytes)
            if let name {
                guard name.utf8.count <= LibraryBounds.metadata,
                    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 1024
                else {
                    throw NativeLibraryError.invalidInput
                }
            }
            let parent = try directory(at: folder)
            let base = LibraryNames.basename(label: name ?? document.root.label, kind: document.root.kind)
            let existing = Set(try parent.entries().map(LibraryNames.key))
            var basename = base
            var suffix = 2
            while existing.contains(LibraryNames.key(basename + ".txt"))
                || existing.contains(LibraryNames.key(basename + ".json"))
            {
                guard suffix <= LibraryBounds.directoryEntries else { throw NativeLibraryError.limitExceeded }
                basename = "\(base) (\(suffix))"
                suffix += 1
            }
            let now = LibraryRecords.now()
            // A label with rich-text tags keeps them as the item's name; the file name drops them (ICN-8).
            let tagged = name == nil ? LibraryNames.taggedName(document.root.label) : nil
            let metadata = LibraryItemMetadata(
                schemaVersion: 1, id: LibraryRecords.uuid(), createdAt: now, updatedAt: now,
                sourceSha256: document.original.sha256,
                displayNameOverride: name ?? tagged.map { $0 + basename.dropFirst(base.count) }, comments: []
            )
            let result = item(metadata: metadata, document: document, folder: folder, basename: basename)
            try transact(
                kind: "import", folder: folder, basename: basename, metadata: metadata, source: bytes, before: nil)
            return result
        }
    }

    /// A snapshot of one saved entry, addressed by actual stored indices, for derived work such as statistics
    /// that runs off the library queue. The snapshot is a value: later library changes do not affect it.
    public func entry(id: String, entryPath: [Int] = []) throws -> BlueprintEntry {
        try queue.sync {
            try ready()
            let (_, document, _) = try load(id: id)
            return try document.entry(at: entryPath)
        }
    }

    public func export(id: String, entryPath: [Int] = []) throws -> Data {
        try queue.sync {
            try ready()
            let (_, document, _) = try load(id: id)
            return try document.export(at: entryPath)
        }
    }

    public func addComment(id: String, entryPath: [Int] = [], text: String) throws -> LibraryItem {
        try queue.sync {
            try ready()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                text.utf8.count <= LibraryBounds.comment
            else { throw NativeLibraryError.invalidInput }
            let (found, document, metadataBytes) = try load(id: id)
            let original = found.metadata
            _ = try document.entry(at: entryPath)
            guard original.comments.count < LibraryBounds.comments else { throw NativeLibraryError.limitExceeded }
            var metadata = original
            let now = max(LibraryRecords.now(), original.updatedAt)
            metadata.updatedAt = now
            metadata.comments.append(
                LibraryComment(id: LibraryRecords.uuid(), entryPath: entryPath, text: text, createdAt: now))
            try transact(
                kind: "comment", folder: found.folder, basename: found.basename, metadata: metadata,
                source: nil, before: OriginalSource(bytes: metadataBytes).sha256)
            return item(metadata: metadata, document: document, folder: found.folder, basename: found.basename)
        }
    }

    func checkControls() throws {
        try lease.check()
        try library.check()
        try operations.check()
        try cache.check()
        guard try root.read(".library-format.json", maximum: LibraryBounds.journal) == formatBytes else {
            throw NativeLibraryError.integrity
        }
    }

    func ready() throws {
        lifecycleLock.lock()
        let isClosing = closing
        lifecycleLock.unlock()
        guard !isClosing else { throw NativeLibraryError.closed }
        try checkControls()
        guard !needsRecovery else { throw NativeLibraryError.recoveryRequired }
    }

    func directory(at folder: String) throws -> LibraryDirectory {
        var result = library
        for part in try LibraryNames.folderComponents(folder) {
            let matches = try result.entries().filter { LibraryNames.key($0) == LibraryNames.key(part) }
            guard matches.count == 1, matches[0].utf8.elementsEqual(part.utf8) else {
                throw NativeLibraryError.unsafePath
            }
            result = try result.child(part)
        }
        return result
    }

    func readItem(folder: String, basename: String) throws -> (LibraryItemMetadata, BlueprintDocument, Data) {
        try LibraryNames.validateBasename(basename)
        let parent = try directory(at: folder)
        let data = try parent.read(basename + ".json", maximum: LibraryBounds.metadata)
        let metadata = try LibraryRecords.metadata(data)
        let bytes = try parent.read(basename + ".txt", maximum: BlueprintCodecLimits.standard.sourceBytes)
        guard OriginalSource(bytes: bytes).sha256 == metadata.sourceSha256 else { throw NativeLibraryError.integrity }
        let document = try BlueprintCodec.decode(bytes)
        for comment in metadata.comments {
            do { _ = try document.entry(at: comment.entryPath) } catch { throw NativeLibraryError.invalidMetadata }
        }
        return (metadata, document, data)
    }

    func item(metadata: LibraryItemMetadata, document: BlueprintDocument, folder: String, basename: String)
        -> LibraryItem
    {
        LibraryItem(
            id: metadata.id, folder: folder, basename: basename, name: metadata.displayNameOverride ?? basename,
            kind: document.root.kind.rawValue, sourceBytes: document.original.bytes.count, metadata: metadata,
            entryIcons: document.root.icons)
    }

    /// Lists an item from its metadata and source hash. Sources decode only when the kind index lacks them.
    func listedItem(
        _ parent: LibraryDirectory, folder: String, basename: String, index: inout LibrarySourceIndex
    ) throws -> (LibraryItem, metadataBytes: Int) {
        try LibraryNames.validateBasename(basename)
        let data = try parent.read(basename + ".json", maximum: LibraryBounds.metadata)
        let metadata = try LibraryRecords.metadata(data)
        let source = try parent.fingerprint(basename + ".txt", maximum: BlueprintCodecLimits.standard.sourceBytes)
        guard source.sha256 == metadata.sourceSha256 else { throw NativeLibraryError.integrity }
        let kind: String
        let icons: [EntryIcon]
        if let indexed = index.kinds[source.sha256] {
            kind = indexed
            icons = index.icons[source.sha256] ?? []
        } else {
            let bytes = try parent.read(basename + ".txt", maximum: BlueprintCodecLimits.standard.sourceBytes)
            guard OriginalSource(bytes: bytes).sha256 == metadata.sourceSha256 else {
                throw NativeLibraryError.integrity
            }
            let document = try BlueprintCodec.decode(bytes)
            for comment in metadata.comments {
                do { _ = try document.entry(at: comment.entryPath) } catch { throw NativeLibraryError.invalidMetadata }
            }
            kind = document.root.kind.rawValue
            icons = document.root.icons
            index.kinds[source.sha256] = kind
            if !icons.isEmpty { index.icons[source.sha256] = icons }
        }
        let listed = LibraryItem(
            id: metadata.id, folder: folder, basename: basename, name: metadata.displayNameOverride ?? basename,
            kind: kind, sourceBytes: source.bytes, metadata: metadata, entryIcons: icons)
        return (listed, data.count)
    }

    func listing() throws -> LibraryListing {
        var result = LibraryListing()
        var visited = 0
        var scannedBytes = 0
        var identities = Set<String>()
        let storedIndex = LibrarySourceIndex.read(cache)
        var index = storedIndex
        func walk(_ parent: LibraryDirectory, folder: String, depth: Int) throws {
            guard depth <= LibraryBounds.folderDepth else { throw NativeLibraryError.limitExceeded }
            let names = try parent.entries()
            visited += names.count
            guard visited <= LibraryBounds.directoryEntries else { throw NativeLibraryError.limitExceeded }
            let groups = Dictionary(grouping: names, by: LibraryNames.key)
            for name in names {
                let path = folder.isEmpty ? name : folder + "/" + name
                do {
                    guard groups[LibraryNames.key(name)]?.count == 1 else { throw NativeLibraryError.integrity }
                    guard let info = try parent.info(name) else { throw NativeLibraryError.integrity }
                    if info.st_mode & S_IFMT == S_IFDIR {
                        try LibraryNames.validateBasename(name)
                        result.folders.append(path)
                        try walk(parent.child(name), folder: path, depth: depth + 1)
                    } else if name == ".folder.json" {
                        let data = try parent.read(name, maximum: LibraryBounds.metadata)
                        let record = try LibraryRecords.folderMetadata(data)
                        scannedBytes += data.count
                        guard scannedBytes <= LibraryBounds.transactionBytes else {
                            throw NativeLibraryError.limitExceeded
                        }
                        result.folderComments[folder] = record.comment
                    } else if name.hasSuffix(".json") {
                        let basename = String(name.dropLast(5))
                        guard names.contains(where: { $0.utf8.elementsEqual((basename + ".txt").utf8) }) else {
                            throw NativeLibraryError.integrity
                        }
                        let (listed, metadataBytes) = try listedItem(
                            parent, folder: folder, basename: basename, index: &index)
                        scannedBytes += metadataBytes + listed.sourceBytes
                        guard scannedBytes <= 256 * 1024 * 1024 else { throw NativeLibraryError.limitExceeded }
                        if !identities.insert(listed.id).inserted {
                            result.issues.append(LibraryIssue(path: path, code: NativeLibraryError.ambiguousId.code))
                        }
                        result.items.append(listed)
                    } else if name.hasSuffix(".txt") {
                        let metadataName = String(name.dropLast(4)) + ".json"
                        guard names.contains(where: { $0.utf8.elementsEqual(metadataName.utf8) }) else {
                            throw NativeLibraryError.integrity
                        }
                        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
                            throw NativeLibraryError.unsafePath
                        }
                    } else {
                        throw NativeLibraryError.unsafePath
                    }
                } catch NativeLibraryError.limitExceeded { throw NativeLibraryError.limitExceeded } catch {
                    result.issues.append(
                        LibraryIssue(path: path, code: (error as? NativeLibraryError)?.code ?? "INVALID_SOURCE"))
                }
            }
        }
        try walk(library, folder: "", depth: 0)
        // Keep only sources this library still uses; a failed index write merely costs decodes next time.
        let used = Set(result.items.map(\.metadata.sourceSha256))
        index.kinds = index.kinds.filter { used.contains($0.key) }
        index.icons = index.icons.filter { used.contains($0.key) }
        if index != storedIndex { try? index.write(cache) }
        itemPaths = Dictionary(grouping: result.items, by: \.id).mapValues {
            $0.map { MutationPath.join($0.folder, $0.basename) }
        }
        return result
    }

    func find(id: String) throws -> LibraryItem {
        try load(id: id).0
    }

    func load(id: String) throws -> (LibraryItem, BlueprintDocument, Data) {
        guard LibraryRecords.validUUID(id) else { throw NativeLibraryError.invalidInput }
        var rescanned = false
        while true {
            if itemPaths == nil {
                itemPaths = try scanItemPaths()
                rescanned = true
            }
            let paths = itemPaths?[id] ?? []
            guard paths.count <= 1 else { throw NativeLibraryError.ambiguousId }
            if let path = paths.first {
                let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                let folder = parts.dropLast().joined(separator: "/")
                let basename = parts.last ?? ""
                if let (metadata, document, data) = try? readItem(folder: folder, basename: basename),
                    metadata.id == id
                {
                    return (
                        item(metadata: metadata, document: document, folder: folder, basename: basename), document, data
                    )
                }
                if rescanned { throw NativeLibraryError.notFound }
            } else if rescanned {
                throw NativeLibraryError.notFound
            }
            // A stale or missing entry: rebuild once from the filesystem.
            itemPaths = nil
        }
    }

    /// Full scan for item IDs. Reads each metadata file's ID without full validation; the match is validated.
    func scanItemPaths() throws -> [String: [String]] {
        var matches: [String: [String]] = [:]
        var visited = 0
        var bytes = 0
        func visit(_ directory: LibraryDirectory, folder: String, depth: Int) throws {
            guard depth <= LibraryBounds.folderDepth else { throw NativeLibraryError.limitExceeded }
            let names = try directory.entries()
            visited += names.count
            guard visited <= LibraryBounds.directoryEntries else { throw NativeLibraryError.limitExceeded }
            for name in names {
                guard let info = try directory.info(name) else { throw NativeLibraryError.integrity }
                if info.st_mode & S_IFMT == S_IFDIR {
                    try LibraryNames.validateBasename(name)
                    try visit(directory.child(name), folder: MutationPath.join(folder, name), depth: depth + 1)
                } else if name.hasSuffix(".json"), name != ".folder.json" {
                    do {
                        let data = try directory.read(name, maximum: LibraryBounds.metadata)
                        bytes += data.count
                        guard bytes <= LibraryBounds.transactionBytes else { throw NativeLibraryError.limitExceeded }
                        let value = try LibraryRecords.parse(data, maximum: LibraryBounds.metadata)
                        if let found = value["id"]?.string, LibraryRecords.validUUID(found) {
                            matches[found, default: []].append(MutationPath.join(folder, String(name.dropLast(5))))
                        }
                    } catch NativeLibraryError.limitExceeded { throw NativeLibraryError.limitExceeded } catch {
                        continue
                    }
                }
            }
        }
        try visit(library, folder: "", depth: 0)
        return matches
    }

    func transact(
        kind: String, folder: String, basename: String, metadata: LibraryItemMetadata, source: Data?, before: String?
    ) throws {
        guard try operations.entries(maximum: LibraryBounds.operations).count < LibraryBounds.operations else {
            throw NativeLibraryError.limitExceeded
        }
        let metadataBytes = try LibraryRecords.encode(metadata, maximum: LibraryBounds.metadata)
        _ = try LibraryRecords.metadata(metadataBytes)
        let id = LibraryRecords.uuid()
        let stage = try operations.child(id, create: true)
        do {
            if let source {
                try stage.writeNew("source.txt", data: source)
                try hook?(.sourceStaged)
            }
            try stage.writeNew("metadata.json", data: metadataBytes)
            try hook?(.metadataStaged)
            let intent = LibraryIntent(
                schemaVersion: 1, operationId: id, kind: kind, folder: folder, basename: basename,
                itemId: metadata.id, sourceSha256: metadata.sourceSha256,
                metadataSha256: OriginalSource(bytes: metadataBytes).sha256, beforeMetadataSha256: before)
            try stage.writeNew("intent.pending", data: LibraryRecords.encode(intent, maximum: LibraryBounds.journal))
            try stage.move("intent.pending", to: stage, as: "intent.json")
            // Commit point: staged bytes and the intent reach permanent storage before live files change.
            try stage.barrier()
            needsRecovery = true
            try hook?(.intentPublished)
            try apply(intent, stage: stage)
            needsRecovery = false
            if kind == "import" { itemPaths?[metadata.id, default: []].append(MutationPath.join(folder, basename)) }
        } catch {
            needsRecovery = true
            itemPaths = nil
            throw error
        }
    }

    func validateStage(_ stage: LibraryDirectory) throws -> [String] {
        let names = try stage.entries(maximum: 64)
        for name in names {
            let standard = ["source.txt", "metadata.json", "intent.pending", "intent.json"].contains(name)
            let temporary =
                name.hasPrefix("publish-") && name.hasSuffix(".tmp")
                && LibraryRecords.validUUID(String(name.dropFirst(8).dropLast(4)))
            guard standard || temporary, let info = try stage.info(name),
                info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
                info.st_size <= BlueprintCodecLimits.standard.sourceBytes
            else { throw NativeLibraryError.recoveryRequired }
        }
        return names
    }

    func replay() throws -> [LibraryOperationRecord] {
        var completed: [LibraryOperationRecord] = []
        for id in try operations.entries(maximum: LibraryBounds.operations) {
            guard LibraryRecords.validUUID(id) else { throw NativeLibraryError.recoveryRequired }
            let stage = try operations.child(id)
            guard try stage.info("intent.json") != nil else {
                try validateUnpublishedStage(stage)
                continue
            }
            let bytes = try stage.read("intent.json", maximum: LibraryBounds.transaction)
            let value = try LibraryRecords.parse(bytes, maximum: LibraryBounds.transaction)
            if value["schemaVersion"]?.safeInteger == 1 {
                _ = try validateStage(stage)
                let intent = try LibraryRecords.intent(bytes, operationId: id)
                try apply(intent, stage: stage)
                completed.append(LibraryOperationRecord(id: id, state: "committed", kind: intent.kind))
            } else {
                let transaction = try LibraryRecords.transaction(bytes, operationId: id)
                try applyTransaction(transaction, stage: stage)
                completed.append(LibraryOperationRecord(id: id, state: "committed", kind: transaction.kind))
            }
        }
        return completed
    }

    func apply(_ intent: LibraryIntent, stage: LibraryDirectory) throws {
        let stagedNames = try validateStage(stage)
        guard !stagedNames.contains("intent.pending"),
            stagedNames.contains("source.txt") == (intent.kind == "import")
        else {
            throw NativeLibraryError.recoveryRequired
        }
        let data = try stage.read("metadata.json", maximum: LibraryBounds.metadata)
        guard OriginalSource(bytes: data).sha256 == intent.metadataSha256 else { throw NativeLibraryError.integrity }
        let metadata = try LibraryRecords.metadata(data)
        guard metadata.id == intent.itemId, metadata.sourceSha256 == intent.sourceSha256 else {
            throw NativeLibraryError.integrity
        }
        let destination = try directory(at: intent.folder)
        let names = try destination.entries()
        for ext in [".txt", ".json"] {
            let target = intent.basename + ext
            let matches = names.filter { LibraryNames.key($0) == LibraryNames.key(target) }
            guard matches.allSatisfy({ $0.utf8.elementsEqual(target.utf8) }) else { throw NativeLibraryError.integrity }
        }
        if try destination.info(intent.basename + ".json") != nil {
            let current = OriginalSource(
                bytes: try destination.read(intent.basename + ".json", maximum: LibraryBounds.metadata)
            ).sha256
            guard current == intent.metadataSha256 || current == intent.beforeMetadataSha256 else {
                throw NativeLibraryError.integrity
            }
        } else if intent.kind == "comment" {
            throw NativeLibraryError.integrity
        }
        if intent.kind == "import" {
            let source = try stage.read("source.txt", maximum: BlueprintCodecLimits.standard.sourceBytes)
            guard OriginalSource(bytes: source).sha256 == intent.sourceSha256 else {
                throw NativeLibraryError.integrity
            }
            let document = try BlueprintCodec.decode(source)
            for comment in metadata.comments { _ = try document.entry(at: comment.entryPath) }
            try install(
                source, target: intent.basename + ".txt", destination: destination, stage: stage,
                expected: intent.sourceSha256, before: nil)
            try hook?(.sourcePublished)
        } else {
            let source = try destination.read(
                intent.basename + ".txt", maximum: BlueprintCodecLimits.standard.sourceBytes)
            guard OriginalSource(bytes: source).sha256 == intent.sourceSha256 else {
                throw NativeLibraryError.integrity
            }
            let document = try BlueprintCodec.decode(source)
            for comment in metadata.comments { _ = try document.entry(at: comment.entryPath) }
        }
        try install(
            data, target: intent.basename + ".json", destination: destination, stage: stage,
            expected: intent.metadataSha256, before: intent.beforeMetadataSha256)
        try hook?(.metadataPublished)
        // Published files reach permanent storage before the intent that can replay them disappears.
        try stage.barrier()
        try stage.remove("intent.json")
        try hook?(.intentRemoved)
        for name in try validateStage(stage) { try stage.remove(name) }
        try operations.remove(intent.operationId, directory: true)
    }

    func install(
        _ data: Data, target: String, destination: LibraryDirectory, stage: LibraryDirectory, expected: String,
        before: String?
    ) throws {
        func currentHash() throws -> String? {
            guard try destination.info(target) != nil else { return nil }
            return OriginalSource(
                bytes: try destination.read(target, maximum: BlueprintCodecLimits.standard.sourceBytes)
            ).sha256
        }
        let current = try currentHash()
        if current == expected { return }
        guard current == before else { throw NativeLibraryError.integrity }
        // A comment cannot recreate a missing sidecar; imports never replace an existing member.
        guard before == nil || current != nil else { throw NativeLibraryError.integrity }
        let temporary = "publish-\(LibraryRecords.uuid()).tmp"
        try stage.writeNew(temporary, data: data)
        guard try currentHash() == current else { throw NativeLibraryError.integrity }
        try stage.move(temporary, to: destination, as: target, replacing: before != nil)
    }
}
