import Darwin
import Foundation

/// Native preview identity. Unknown manifest versions are protected by scoped cleanup.
public struct LibraryCacheIdentity: Codable, Sendable {
    public let schemaVersion: Int
    public let itemId: String
    public let sourceSha256: String
    public let entryPath: [Int]
    public let generator: String
    public let assetIdentity: String

    public init(itemId: String, sourceSha256: String, entryPath: [Int], generator: String, assetIdentity: String) {
        schemaVersion = 1
        self.itemId = itemId
        self.sourceSha256 = sourceSha256
        self.entryPath = entryPath
        self.generator = generator
        self.assetIdentity = assetIdentity
    }

    public func key() throws -> String {
        try validate()
        return OriginalSource(bytes: try LibraryRecords.encode(self, maximum: LibraryBounds.journal)).sha256
    }

    func validate() throws {
        guard schemaVersion == 1, LibraryRecords.validUUID(itemId), LibraryRecords.validHash(sourceSha256),
            LibraryRecords.validHash(assetIdentity), !generator.isEmpty, generator.utf8.count <= 256,
            entryPath.count <= 32, entryPath.allSatisfy({ $0 >= 0 && $0 <= 9_007_199_254_740_991 })
        else { throw NativeLibraryError.invalidMetadata }
    }

    static func read(_ data: Data) throws -> Self {
        let value = try LibraryRecords.parse(data, maximum: LibraryBounds.journal)
        try LibraryRecords.fields(
            value, required: ["schemaVersion", "itemId", "sourceSha256", "entryPath", "generator", "assetIdentity"])
        guard value["schemaVersion"]?.safeInteger == 1,
            value["entryPath"]?.array?.allSatisfy({ $0.safeInteger != nil }) == true,
            let result = try? JSONDecoder().decode(Self.self, from: data)
        else { throw NativeLibraryError.invalidMetadata }
        try result.validate()
        return result
    }
}

public enum CacheCleanupScope: String, Codable, Sendable { case abandoned, obsolete, all }
public struct CacheCleanupSelection: Codable, Sendable {
    public let path: String
    public let reason: String
    public let bytes: Int
}
public struct CacheCleanupReport: Codable, Sendable {
    public let scope: CacheCleanupScope
    public let apply: Bool
    public let selection: [CacheCleanupSelection]
    public let selectedDirectories: [String]
    public let retainedFiles: Int
    public let selectedBytes: Int64
    public let allocatedBytes: Int64
}

public struct DiskUsageCategory: Codable, Sendable {
    public var files = 0
    public var directories = 0
    public var logicalBytes: Int64 = 0
    public var uniqueLogicalBytes: Int64 = 0
    public var allocatedBytes: Int64 = 0
}
public struct DiskUsageReport: Codable, Sendable {
    public var complete = true
    public var categories: [String: DiskUsageCategory] = [:]
    public var total = DiskUsageCategory()
    public var issues: [LibraryIssue] = []
    public var filesystemTotalBytes: UInt64 = 0
    public var filesystemFreeBytes: UInt64 = 0
    public var filesystemAvailableBytes: UInt64 = 0
}

extension NativeLibrary {
    public func cleanupCache(
        scope: CacheCleanupScope = .abandoned, apply: Bool = false,
        assetIdentity: String? = nil, generator: String = "native-preview-v1",
        protectedAssets: URL? = nil
    ) throws -> CacheCleanupReport {
        try queue.sync {
            try ready()
            if scope == .obsolete {
                guard let assetIdentity, LibraryRecords.validHash(assetIdentity), !generator.isEmpty,
                    generator.utf8.count <= 256
                else { throw NativeLibraryError.invalidInput }
            }
            if let protectedAssets {
                let assets = try LibraryDirectory(url: protectedAssets)
                let a = assets.url.path
                let c = cache.url.path
                guard a != c, !a.hasPrefix(c + "/"), !c.hasPrefix(a + "/") else { throw NativeLibraryError.unsafePath }
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            let snapshot = try LibraryTrees.stamps(cache, deadline: deadline)
            var known: [String: LibraryItem] = [:]
            var documents: [String: BlueprintDocument] = [:]
            if scope != .all {
                let catalog = try listing()
                guard catalog.issues.isEmpty else { throw NativeLibraryError.integrity }
                for item in catalog.items {
                    guard ContinuousClock.now < deadline else { throw NativeLibraryError.limitExceeded }
                    known[item.id] = item
                }
            }
            let files = snapshot.filter { !$0.directory }
            let paths = Set(files.map(\.path))
            var selected: [TreeStamp] = []
            var selection: [CacheCleanupSelection] = []
            for file in files {
                guard ContinuousClock.now < deadline else { throw NativeLibraryError.limitExceeded }
                let parts = file.path.split(separator: "/").map(String.init)
                var reason: String?
                if scope == .all {
                    reason = "all-derived"
                } else if parts.count == 2, LibraryRecords.validUUID(parts[0]) {
                    let name = parts[1]
                    if name.hasPrefix(".tmp-"), LibraryRecords.validUUID(String(name.dropFirst(5))) {
                        reason = "abandoned-temporary"
                    }
                    if name.hasSuffix(".png") || name.hasSuffix(".json") {
                        let key = String(name.dropLast(name.hasSuffix(".png") ? 4 : 5))
                        if LibraryRecords.validHash(key) {
                            let manifestPath = parts[0] + "/" + key + ".json"
                            if !paths.contains(manifestPath) {
                                reason = "abandoned-image"
                            } else {
                                let (parent, name) = try LibraryTrees.descendant(cache, manifestPath)
                                // Unknown, damaged, or foreign manifests stay protected in scoped cleanup.
                                if let identity = try? LibraryCacheRecords.identity(
                                    parent.read(name, maximum: LibraryBounds.metadata)),
                                    identity.itemId == parts[0], (try? identity.key()) == key
                                {
                                    if let item = known[identity.itemId] {
                                        if scope == .obsolete {
                                            if documents[item.id] == nil {
                                                documents[item.id] = try readItem(
                                                    folder: item.folder, basename: item.basename
                                                ).1
                                            }
                                            let document = documents[item.id]!
                                            if identity.sourceSha256 != document.original.sha256
                                                || (try? document.entry(at: identity.entryPath)) == nil
                                                || identity.assetIdentity != assetIdentity
                                                || identity.generator != generator
                                            {
                                                reason = "obsolete-source-generator-or-assets"
                                            }
                                        }
                                    } else {
                                        reason = "orphaned-item"
                                    }
                                }
                            }
                        }
                    }
                }
                if let reason {
                    selected.append(file)
                    selection.append(CacheCleanupSelection(path: file.path, reason: reason, bytes: file.bytes))
                }
            }
            var selectedPaths = Set(selected.map(\.path))
            var directories: [TreeStamp] = []
            var childrenByParent: [String: [String]] = [:]
            for entry in snapshot {
                let parent = entry.path.split(separator: "/").dropLast().joined(separator: "/")
                childrenByParent[parent, default: []].append(entry.path)
            }
            for directory in snapshot.reversed() where directory.directory {
                guard ContinuousClock.now < deadline else { throw NativeLibraryError.limitExceeded }
                let children = childrenByParent[directory.path] ?? []
                let orphan = LibraryRecords.validUUID(directory.path) && known[directory.path] == nil
                if (scope == .all || orphan) && children.allSatisfy({ selectedPaths.contains($0) }) {
                    directories.append(directory)
                    selectedPaths.insert(directory.path)
                }
            }
            if apply {
                // Recompute on this call, then reject changes before the first unlink.
                guard try LibraryTrees.stamps(cache, deadline: deadline) == snapshot else {
                    throw NativeLibraryError.integrity
                }
                for entry in selected + directories {
                    try checkControls()
                    let (parent, name) = try LibraryTrees.descendant(cache, entry.path)
                    guard let info = try parent.info(name), info.st_dev == entry.device, info.st_ino == entry.inode
                    else { throw NativeLibraryError.integrity }
                    if !entry.directory {
                        guard TreeStamp(path: entry.path, info: info) == entry else {
                            throw NativeLibraryError.integrity
                        }
                    } else {
                        guard info.st_mode & S_IFMT == S_IFDIR else { throw NativeLibraryError.unsafePath }
                    }
                    try parent.remove(name, directory: entry.directory)
                }
            }
            return CacheCleanupReport(
                scope: scope, apply: apply, selection: selection, selectedDirectories: directories.map(\.path),
                retainedFiles: files.count - selected.count,
                selectedBytes: selected.reduce(0) { $0 + Int64($1.bytes) },
                allocatedBytes: (selected + directories).reduce(0) { $0 + $1.allocated })
        }
    }

    public func diskUsage(assets url: URL? = nil) throws -> DiskUsageReport {
        try queue.sync {
            try ready()
            var report = DiskUsageReport()
            for name in ["originals", "metadata", "libraryOther", "cache", "operations", "controls", "assets"] {
                report.categories[name] = DiskUsageCategory()
            }
            var totalSeen = Set<String>()
            var categorySeen: [String: Set<String>] = [:]
            var visited = 0
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            func issue(_ path: String, _ code: String) {
                report.complete = false
                report.issues.append(LibraryIssue(path: path, code: code))
            }
            func count(_ info: stat, category: String) {
                let identity = "\(info.st_dev):\(info.st_ino)"
                let directory = info.st_mode & S_IFMT == S_IFDIR
                let logical = directory ? 0 : Int64(info.st_size)
                func add(_ value: inout DiskUsageCategory, unique: Bool) {
                    if directory { value.directories += 1 } else { value.files += 1 }
                    value.logicalBytes += logical
                    if unique {
                        value.uniqueLogicalBytes += logical
                        value.allocatedBytes += Int64(info.st_blocks) * 512
                    }
                }
                var categoryValue = report.categories[category]!
                var seen = categorySeen[category] ?? []
                add(&categoryValue, unique: seen.insert(identity).inserted)
                categorySeen[category] = seen
                report.categories[category] = categoryValue
                add(&report.total, unique: totalSeen.insert(identity).inserted)
            }
            func walk(_ directory: LibraryDirectory, prefix: String, fixed: String?, level: Int) throws {
                guard level <= 64, ContinuousClock.now < deadline else { throw NativeLibraryError.limitExceeded }
                for name in try directory.entries() {
                    visited += 1
                    guard visited <= LibraryBounds.directoryEntries, ContinuousClock.now < deadline else {
                        throw NativeLibraryError.limitExceeded
                    }
                    let path = MutationPath.join(prefix, name)
                    do {
                        guard let info = try directory.info(name), info.st_dev == directory.device else {
                            throw NativeLibraryError.unsafePath
                        }
                        let mode = info.st_mode & S_IFMT
                        guard mode == S_IFDIR || mode == S_IFREG, info.st_size >= 0 else {
                            throw NativeLibraryError.unsafePath
                        }
                        let category =
                            fixed
                            ?? (mode == S_IFDIR
                                ? "libraryOther"
                                : name.hasSuffix(".txt")
                                    ? "originals" : name.hasSuffix(".json") ? "metadata" : "libraryOther")
                        count(info, category: category)
                        if mode == S_IFDIR {
                            try walk(directory.child(name), prefix: path, fixed: fixed, level: level + 1)
                        }
                    } catch let error as NativeLibraryError {
                        issue(path, error.code)
                        if error == .limitExceeded { throw error }
                    }
                }
            }
            var scanned: [(LibraryDirectory, String, String?)] = [
                (library, "library", nil), (cache, "cache", "cache"), (operations, "operations", "operations"),
            ]
            if try root.info(Self.quarantineName) != nil {
                scanned.append((try root.child(Self.quarantineName), Self.quarantineName, "operations"))
            }
            for (directory, prefix, category) in scanned {
                if let info = try root.info(prefix) { count(info, category: category ?? "libraryOther") }
                do { try walk(directory, prefix: prefix, fixed: category, level: 0) } catch {
                    issue(prefix, (error as? NativeLibraryError)?.code ?? "IO_ERROR")
                }
            }
            var rootInfo = stat()
            guard fstat(root.fd, &rootInfo) == 0 else { throw NativeLibraryError.io(errno) }
            count(rootInfo, category: "controls")
            for name in [".library-format.json", ".owner.lock", ".DS_Store"] {
                if let info = try root.info(name) {
                    if info.st_mode & S_IFMT == S_IFREG {
                        count(info, category: "controls")
                    } else {
                        issue(name, "UNSAFE_PATH")
                    }
                }
            }
            if let url {
                do {
                    let assets = try LibraryDirectory(url: url)
                    let a = assets.url.path
                    let r = root.url.path
                    guard a != r, !a.hasPrefix(r + "/"), !r.hasPrefix(a + "/") else {
                        throw NativeLibraryError.unsafePath
                    }
                    var info = stat()
                    guard fstat(assets.fd, &info) == 0 else { throw NativeLibraryError.io(errno) }
                    count(info, category: "assets")
                    try walk(assets, prefix: "assets", fixed: "assets", level: 0)
                } catch { issue("assets", (error as? NativeLibraryError)?.code ?? "IO_ERROR") }
            } else {
                issue("assets", "ASSETS_NOT_SELECTED")
            }
            var volume = statfs()
            guard fstatfs(root.fd, &volume) == 0 else { throw NativeLibraryError.io(errno) }
            report.filesystemTotalBytes = UInt64(volume.f_blocks) * UInt64(volume.f_bsize)
            report.filesystemFreeBytes = UInt64(volume.f_bfree) * UInt64(volume.f_bsize)
            report.filesystemAvailableBytes = UInt64(volume.f_bavail) * UInt64(volume.f_bsize)
            return report
        }
    }
}
