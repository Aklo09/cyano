import Foundation

/// One directory beneath `operations/`: `committed` has a published intent, `unpublished` never committed.
public struct LibraryOperationRecord: Codable, Sendable, Equatable {
    public let id: String
    public let state: String
    public let kind: String?
}

public struct StagingCleanupReport: Codable, Sendable {
    public let apply: Bool
    public let selection: [LibraryOperationRecord]
}

extension NativeLibrary {
    static let quarantineName = "operations-quarantine"
    static let allowedRootEntries: Set<String> = [
        ".owner.lock", ".library-format.json", "library", "operations", "cache", quarantineName,
    ]

    /// Ownership without replay, so operations that block opening can still be inspected and quarantined.
    private static func withControls<T>(
        at url: URL, _ body: (LibraryDirectory, LibraryDirectory?) throws -> T
    ) throws -> T {
        try LibraryDirectory.validateURL(url)
        let root = try LibraryDirectory(url: url)
        try root.qualify()
        guard try root.info(".library-format.json") != nil else { throw NativeLibraryError.invalidFormat }
        _ = try LibraryRecords.format(root.read(".library-format.json", maximum: LibraryBounds.journal))
        let lease = try LibraryLease(directory: root, create: false)
        defer { lease.close() }
        guard Set(try root.entries()).isSubset(of: allowedRootEntries) else { throw NativeLibraryError.invalidFormat }
        let operations = try root.info("operations") == nil ? nil : try root.child("operations")
        return try body(root, operations)
    }

    private static func record(_ id: String, in operations: LibraryDirectory) throws -> LibraryOperationRecord {
        let stage = try operations.child(id)
        guard try stage.info("intent.json") != nil else {
            return LibraryOperationRecord(id: id, state: "unpublished", kind: nil)
        }
        // Report the kind when the intent parses; an unreadable intent is still a committed operation.
        let bytes = try? stage.read("intent.json", maximum: LibraryBounds.transaction)
        let value = bytes.flatMap { try? LibraryRecords.parse($0, maximum: LibraryBounds.transaction) }
        return LibraryOperationRecord(id: id, state: "committed", kind: value?["kind"]?.string)
    }

    /// Lists pending operations without replaying them.
    public static func inspectOperations(at url: URL) throws -> [LibraryOperationRecord] {
        try withControls(at: url) { _, operations in
            guard let operations else { return [] }
            return try operations.entries(maximum: LibraryBounds.directoryEntries).map { id in
                guard LibraryRecords.validUUID(id) else {
                    return LibraryOperationRecord(id: id, state: "invalid", kind: nil)
                }
                return try record(id, in: operations)
            }
        }
    }

    /// Moves one operation, unchanged, to `operations-quarantine/` so replay no longer blocks opening.
    /// A quarantined committed operation may leave partial live changes; they appear as listing issues.
    public static func quarantineOperation(at url: URL, id: String) throws -> LibraryOperationRecord {
        guard LibraryRecords.validUUID(id) else { throw NativeLibraryError.invalidInput }
        return try withControls(at: url) { root, operations in
            guard let operations, try operations.info(id) != nil else { throw NativeLibraryError.notFound }
            let selected = try record(id, in: operations)
            let quarantine = try root.child(quarantineName, create: true)
            guard try quarantine.info(id) == nil else { throw NativeLibraryError.nameCollision }
            try operations.move(id, to: quarantine, as: id)
            try root.barrier()
            return selected
        }
    }

    /// Removes operation directories that never committed an intent. Replay ignores them and they never
    /// changed the library; they still count toward the operation limit. Dry run by default.
    public func cleanupStaging(apply: Bool = false) throws -> StagingCleanupReport {
        try queue.sync {
            try ready()
            var selection: [LibraryOperationRecord] = []
            for id in try operations.entries(maximum: LibraryBounds.operations) {
                guard LibraryRecords.validUUID(id) else { throw NativeLibraryError.recoveryRequired }
                let stage = try operations.child(id)
                guard try stage.info("intent.json") == nil else { continue }
                try validateUnpublishedStage(stage)
                selection.append(LibraryOperationRecord(id: id, state: "unpublished", kind: nil))
                if apply {
                    try LibraryTrees.purge(stage)
                    try operations.remove(id, directory: true)
                }
            }
            return StagingCleanupReport(apply: apply, selection: selection)
        }
    }
}
