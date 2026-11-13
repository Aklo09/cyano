import Darwin
import Foundation

struct LibraryFileChange: Codable {
    let path: String
    let before: String?
    let after: String?
}

struct LibraryTreeFile: Codable, Equatable {
    let path: String
    let bytes: Int
    let sha256: String
}

struct LibraryTreeInventory: Codable, Equatable {
    let directories: [String]
    let files: [LibraryTreeFile]
}

struct LibraryTransaction: Codable {
    let schemaVersion: Int
    let operationId: String
    let kind: String
    let changes: [LibraryFileChange]
    let cacheIds: [String]
    let sourceFolder: String?
    let destinationFolder: String?
    let tree: LibraryTreeInventory?
}

struct PreparedLibraryChange {
    let path: String
    let before: Data?
    let after: Data?
}

enum MutationPath {
    static func parts(_ path: String, file: Bool) throws -> [String] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, path.utf8.count <= 4096,
              parts.count <= LibraryBounds.folderDepth + (file ? 1 : 0) else { throw NativeLibraryError.unsafePath }
        for (index, part) in parts.enumerated() {
            if file && index == parts.count - 1 && [".folder.json", ".DS_Store"].contains(part) { continue }
            try LibraryNames.validateBasename(part)
        }
        return parts
    }

    static func parent(_ root: LibraryDirectory, _ path: String, file: Bool) throws -> (LibraryDirectory, String) {
        var parts = try parts(path, file: file)
        let name = parts.removeLast()
        var directory = root
        for part in parts { directory = try directory.child(part) }
        return (directory, name)
    }

    static func join(_ parent: String, _ name: String) -> String { parent.isEmpty ? name : parent + "/" + name }
}

struct TreeStamp: Equatable {
    let path: String
    let directory: Bool
    let device: dev_t
    let inode: ino_t
    let bytes: Int
    let allocated: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init(path: String, info: stat) {
        self.path = path; directory = info.st_mode & S_IFMT == S_IFDIR
        device = info.st_dev; inode = info.st_ino; bytes = Int(info.st_size)
        allocated = Int64(info.st_blocks) * 512
        modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanoseconds = info.st_mtimespec.tv_nsec
        changedSeconds = info.st_ctimespec.tv_sec; changedNanoseconds = info.st_ctimespec.tv_nsec
    }
}

enum LibraryTrees {
    static func stamps(_ root: LibraryDirectory, depth: Int = 64, deadline: ContinuousClock.Instant? = nil) throws -> [TreeStamp] {
        var result: [TreeStamp] = []
        func visit(_ directory: LibraryDirectory, prefix: String, level: Int) throws {
            guard level <= depth else { throw NativeLibraryError.limitExceeded }
            if let deadline, ContinuousClock.now > deadline { throw NativeLibraryError.limitExceeded }
            for name in try directory.entries() {
                guard result.count < LibraryBounds.directoryEntries else { throw NativeLibraryError.limitExceeded }
                guard let info = try directory.info(name), info.st_dev == root.device else { throw NativeLibraryError.unsafePath }
                let path = MutationPath.join(prefix, name)
                if info.st_mode & S_IFMT == S_IFDIR {
                    result.append(TreeStamp(path: path, info: info))
                    try visit(directory.child(name), prefix: path, level: level + 1)
                } else {
                    guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size >= 0 else { throw NativeLibraryError.unsafePath }
                    result.append(TreeStamp(path: path, info: info))
                }
                if let deadline, ContinuousClock.now > deadline { throw NativeLibraryError.limitExceeded }
            }
        }
        try visit(root, prefix: "", level: 0)
        return result
    }

    static func descendant(_ root: LibraryDirectory, _ path: String) throws -> (LibraryDirectory, String) {
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.popLast(), !name.isEmpty else { throw NativeLibraryError.unsafePath }
        var directory = root
        for part in parts { directory = try directory.child(part) }
        return (directory, name)
    }

    static func inventory(_ root: LibraryDirectory) throws -> LibraryTreeInventory {
        let snapshot = try stamps(root, depth: LibraryBounds.folderDepth)
        var files: [LibraryTreeFile] = []
        var total = 0
        for member in snapshot where !member.directory {
            _ = try MutationPath.parts(member.path, file: true)
            let (directory, name) = try descendant(root, member.path)
            let hash = try directory.fingerprint(name, maximum: min(BlueprintCodecLimits.standard.sourceBytes, LibraryBounds.transactionBytes - total))
            total += hash.bytes
            files.append(LibraryTreeFile(path: member.path, bytes: hash.bytes, sha256: hash.sha256))
        }
        for member in snapshot where member.directory { _ = try MutationPath.parts(member.path, file: false) }
        guard try stamps(root, depth: LibraryBounds.folderDepth) == snapshot else { throw NativeLibraryError.integrity }
        return LibraryTreeInventory(directories: snapshot.filter(\.directory).map(\.path).sorted(), files: files.sorted { $0.path < $1.path })
    }

    static func purge(_ root: LibraryDirectory) throws {
        let snapshot = try stamps(root)
        guard try stamps(root) == snapshot else { throw NativeLibraryError.integrity }
        for member in snapshot.reversed() {
            let (directory, name) = try descendant(root, member.path)
            guard let info = try directory.info(name) else { throw NativeLibraryError.integrity }
            if !member.directory {
                guard TreeStamp(path: member.path, info: info) == member else { throw NativeLibraryError.integrity }
            } else {
                guard info.st_dev == member.device, info.st_ino == member.inode,
                      info.st_mode & S_IFMT == S_IFDIR else { throw NativeLibraryError.integrity }
            }
            try directory.remove(name, directory: member.directory)
        }
    }
}

extension LibraryRecords {
    static func transaction(_ data: Data, operationId: String) throws -> LibraryTransaction {
        let value = try parse(data, maximum: LibraryBounds.transaction)
        try fields(value, required: ["schemaVersion", "operationId", "kind", "changes", "cacheIds"], optional: ["sourceFolder", "destinationFolder", "tree"])
        guard value["schemaVersion"]?.safeInteger == 2 else { throw NativeLibraryError.unsupportedVersion }
        guard let changes = value["changes"]?.array, changes.count <= LibraryBounds.changes else { throw NativeLibraryError.recoveryRequired }
        for change in changes {
            try fields(change, required: ["path"], optional: ["before", "after"])
            for key in ["before", "after"] {
                if let hash = change[key] { guard let hash = hash.string, validHash(hash) else { throw NativeLibraryError.recoveryRequired } }
            }
        }
        if let tree = value["tree"] {
            try fields(tree, required: ["directories", "files"])
            guard let files = tree["files"]?.array else { throw NativeLibraryError.recoveryRequired }
            for file in files {
                try fields(file, required: ["path", "bytes", "sha256"])
                guard file["bytes"]?.safeInteger != nil else { throw NativeLibraryError.recoveryRequired }
            }
        }
        guard let record = try? JSONDecoder().decode(LibraryTransaction.self, from: data), record.operationId == operationId,
              validUUID(operationId), ["files", "tree-create", "tree-move", "tree-delete"].contains(record.kind),
              record.cacheIds.allSatisfy(validUUID), Set(record.cacheIds).count == record.cacheIds.count,
              Set(record.changes.map(\.path)).count == record.changes.count else { throw NativeLibraryError.recoveryRequired }
        for change in record.changes {
            _ = try MutationPath.parts(change.path, file: true)
            guard change.before != nil || change.after != nil else { throw NativeLibraryError.recoveryRequired }
        }
        if record.kind == "files" {
            guard !record.changes.isEmpty, record.cacheIds.count <= 1,
                  record.sourceFolder == nil, record.destinationFolder == nil, record.tree == nil else { throw NativeLibraryError.recoveryRequired }
        } else {
            guard record.changes.isEmpty, record.cacheIds.isEmpty, let tree = record.tree,
                  tree.files.count + tree.directories.count <= LibraryBounds.directoryEntries,
                  Set(tree.files.map(\.path)).count == tree.files.count,
                  Set(tree.directories).count == tree.directories.count,
                  Set(tree.files.map(\.path)).isDisjoint(with: tree.directories) else { throw NativeLibraryError.recoveryRequired }
            var total = 0
            for file in tree.files {
                _ = try MutationPath.parts(file.path, file: true)
                guard validHash(file.sha256), file.bytes >= 0, file.bytes <= BlueprintCodecLimits.standard.sourceBytes else { throw NativeLibraryError.recoveryRequired }
                total += file.bytes
                guard total <= LibraryBounds.transactionBytes else { throw NativeLibraryError.limitExceeded }
            }
            for directory in tree.directories { _ = try MutationPath.parts(directory, file: false) }
            if record.kind == "tree-delete" {
                guard tree.directories.isEmpty, tree.files.allSatisfy({ [".folder.json", ".DS_Store"].contains($0.path) }) else {
                    throw NativeLibraryError.folderNotEmpty
                }
            }
            if let source = record.sourceFolder { _ = try MutationPath.parts(source, file: false) }
            if let destination = record.destinationFolder { _ = try MutationPath.parts(destination, file: false) }
            guard (record.kind == "tree-create" && record.sourceFolder == nil && record.destinationFolder != nil) ||
                  (record.kind == "tree-move" && record.sourceFolder != nil && record.destinationFolder != nil) ||
                  (record.kind == "tree-delete" && record.sourceFolder != nil && record.destinationFolder == nil) else { throw NativeLibraryError.recoveryRequired }
        }
        return record
    }
}
