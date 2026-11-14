import Foundation

public struct LibraryComment: Codable, Sendable, Equatable {
    public let id: String
    public let entryPath: [Int]
    public let text: String
    public let createdAt: String
}

public struct LibraryItemMetadata: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let id: String
    public let createdAt: String
    public var updatedAt: String
    public let sourceSha256: String
    public let displayNameOverride: String?
    public var comments: [LibraryComment]
}

public struct LibraryItem: Codable, Sendable {
    public let id: String
    public let folder: String
    public let basename: String
    public let name: String
    public let kind: String
    public let sourceBytes: Int
    public let metadata: LibraryItemMetadata
}

public struct LibraryIssue: Codable, Sendable {
    public let path: String
    public let code: String
}

public struct LibraryListing: Codable, Sendable {
    public var folders: [String] = []
    public var items: [LibraryItem] = []
    public var issues: [LibraryIssue] = []
    public var folderComments: [String: String] = [:]
}

struct LibraryFolderMetadata: Codable {
    let schemaVersion: Int
    let comment: String
    let createdAt: String
}

public enum LibraryOwnershipStatus: String, Codable, Sendable {
    case uninitialized, owned, idle
}

struct LibraryFormat: Codable, Equatable {
    let format: String
    let schemaVersion: Int
    let id: String
    let createdAt: String

    static func fresh() -> Self {
        Self(format: "fb-native-library", schemaVersion: 1, id: LibraryRecords.uuid(), createdAt: LibraryRecords.now())
    }
}

struct LibraryIntent: Codable {
    let schemaVersion: Int
    let operationId: String
    let kind: String
    let folder: String
    let basename: String
    let itemId: String
    let sourceSha256: String
    let metadataSha256: String
    let beforeMetadataSha256: String?
}

enum LibraryRecords {
    static func uuid() -> String { UUID().uuidString.lowercased() }

    static func validUUID(_ value: String) -> Bool {
        guard value.utf8.count == 36,
            value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) || $0 == 45 })
        else { return false }
        return UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func now() -> String { withFormatter { $0.string(from: Date()) } }

    static func validDate(_ value: String) -> Bool {
        guard value.utf8.count == 24 else { return false }
        return withFormatter { formatter in
            guard let date = formatter.date(from: value) else { return false }
            return formatter.string(from: date) == value
        }
    }

    // Creating a formatter dominated metadata validation; share one behind a lock.
    private static let formatterLock = NSLock()
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let result = ISO8601DateFormatter()
        result.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        result.timeZone = TimeZone(secondsFromGMT: 0)
        return result
    }()

    private static func withFormatter<T>(_ body: (ISO8601DateFormatter) -> T) -> T {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return body(formatter)
    }

    static func encode<T: Encodable>(_ value: T, maximum: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var bytes = try encoder.encode(value)
        bytes.append(10)
        guard bytes.count <= maximum else { throw NativeLibraryError.limitExceeded }
        return bytes
    }

    static func parse(_ data: Data, maximum: Int) throws -> JSONValue {
        guard data.count <= maximum else { throw NativeLibraryError.limitExceeded }
        var limits = BlueprintCodecLimits()
        limits.decodedBytes = maximum
        limits.jsonDepth = 16
        limits.jsonNodes = BlueprintCodecLimits.standard.jsonNodes
        do {
            var parser = try BoundedJSONParser(data: data, limits: limits)
            return try parser.parse()
        } catch { throw NativeLibraryError.invalidMetadata }
    }

    static func fields(_ value: JSONValue, required: Set<String>, optional: Set<String> = []) throws {
        guard case .object(let members) = value else { throw NativeLibraryError.invalidMetadata }
        guard members.allSatisfy({ $0.key.utf8.allSatisfy({ $0 < 128 }) }) else {
            throw NativeLibraryError.invalidMetadata
        }
        let keys = Set(members.map(\.key))
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
            throw NativeLibraryError.invalidMetadata
        }
    }

    static func format(_ data: Data) throws -> LibraryFormat {
        let value = try parse(data, maximum: LibraryBounds.journal)
        try fields(value, required: ["format", "schemaVersion", "id", "createdAt"])
        guard value["format"]?.string == "fb-native-library" else { throw NativeLibraryError.invalidFormat }
        guard value["schemaVersion"]?.safeInteger == 1 else { throw NativeLibraryError.unsupportedVersion }
        guard let record = try? JSONDecoder().decode(LibraryFormat.self, from: data),
            validUUID(record.id), validDate(record.createdAt)
        else { throw NativeLibraryError.invalidFormat }
        return record
    }

    static func metadata(_ data: Data) throws -> LibraryItemMetadata {
        let value = try parse(data, maximum: LibraryBounds.metadata)
        try fields(
            value, required: ["schemaVersion", "id", "createdAt", "updatedAt", "sourceSha256", "comments"],
            optional: ["displayNameOverride"])
        guard value["schemaVersion"]?.safeInteger == 1 else { throw NativeLibraryError.unsupportedVersion }
        guard let comments = value["comments"]?.array, comments.count <= LibraryBounds.comments else {
            throw NativeLibraryError.invalidMetadata
        }
        if let name = value["displayNameOverride"], name.string == nil { throw NativeLibraryError.invalidMetadata }
        for comment in comments {
            try fields(comment, required: ["id", "entryPath", "text", "createdAt"])
            guard let path = comment["entryPath"]?.array, path.count <= LibraryBounds.folderDepth,
                path.allSatisfy({ $0.safeInteger != nil })
            else { throw NativeLibraryError.invalidMetadata }
        }
        guard let record = try? JSONDecoder().decode(LibraryItemMetadata.self, from: data),
            validUUID(record.id), validHash(record.sourceSha256),
            validDate(record.createdAt), validDate(record.updatedAt), record.updatedAt >= record.createdAt,
            record.comments.allSatisfy({ validUUID($0.id) }),
            Set(record.comments.map(\.id)).count == record.comments.count
        else { throw NativeLibraryError.invalidMetadata }
        for comment in record.comments {
            guard validUUID(comment.id), validDate(comment.createdAt),
                !comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                comment.text.utf8.count <= LibraryBounds.comment
            else { throw NativeLibraryError.invalidMetadata }
        }
        return record
    }

    static func folderMetadata(_ data: Data) throws -> LibraryFolderMetadata {
        let value = try parse(data, maximum: LibraryBounds.metadata)
        try fields(value, required: ["schemaVersion", "comment", "createdAt"])
        guard value["schemaVersion"]?.safeInteger == 1 else { throw NativeLibraryError.unsupportedVersion }
        guard let record = try? JSONDecoder().decode(LibraryFolderMetadata.self, from: data),
            !record.comment.isEmpty, record.comment.utf8.count <= LibraryBounds.comment,
            validDate(record.createdAt)
        else { throw NativeLibraryError.invalidMetadata }
        return record
    }

    static func intent(_ data: Data, operationId: String) throws -> LibraryIntent {
        let value = try parse(data, maximum: LibraryBounds.journal)
        try fields(
            value,
            required: [
                "schemaVersion", "operationId", "kind", "folder", "basename", "itemId", "sourceSha256",
                "metadataSha256",
            ], optional: ["beforeMetadataSha256"])
        guard value["schemaVersion"]?.safeInteger == 1 else { throw NativeLibraryError.unsupportedVersion }
        guard let record = try? JSONDecoder().decode(LibraryIntent.self, from: data),
            record.operationId == operationId, validUUID(operationId), validUUID(record.itemId),
            validHash(record.sourceSha256), validHash(record.metadataSha256),
            ["import", "comment"].contains(record.kind),
            (record.kind == "import" && value["beforeMetadataSha256"] == nil)
                || (record.kind == "comment" && record.beforeMetadataSha256.map(validHash) == true)
        else {
            throw NativeLibraryError.recoveryRequired
        }
        try LibraryNames.validateBasename(record.basename)
        _ = try LibraryNames.folderComponents(record.folder)
        return record
    }
}

enum LibraryNames {
    /// Collision key matching APFS case-insensitive name equivalence on every volume, including case-sensitive ones.
    /// Lowercasing alone misses pairs such as `ß`/`SS` and `σ`/`ς`; Foundation's folding alone misses
    /// Unicode 9 letters such as U+1C80. Round-tripping through uppercase first covers both, and is stricter than
    /// APFS only for dotless `ı`, which it equates with `i`.
    static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.uppercased().lowercased()
            .folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping
    }

    static func validateBasename(_ value: String) throws {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "<>:\"/\\|?*"))
        let reserved = ["con", "prn", "aux", "nul", "clock$"] + (1...9).flatMap { ["com\($0)", "lpt\($0)"] }
        guard !value.isEmpty, value.utf8.count <= 220, !value.hasPrefix("."), !value.hasSuffix("."),
            !value.hasSuffix(" "), value.unicodeScalars.allSatisfy({ !forbidden.contains($0) }),
            !reserved.contains(key(String(value.split(separator: ".").first ?? "")))
        else {
            throw NativeLibraryError.invalidInput
        }
    }

    static func folderComponents(_ path: String) throws -> [String] {
        guard path.utf8.count <= 4096 else { throw NativeLibraryError.unsafePath }
        if path.isEmpty { return [] }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= LibraryBounds.folderDepth else { throw NativeLibraryError.unsafePath }
        for part in parts { try validateBasename(part) }
        return parts
    }

    static func basename(label: String?, kind: BlueprintEntryKind) -> String {
        let fallback: String
        switch kind {
        case .blueprint: fallback = "Untitled Blueprint"
        case .book: fallback = "Untitled Book"
        case .upgradePlanner: fallback = "Untitled Upgrade Planner"
        case .deconstructionPlanner: fallback = "Untitled Deconstruction Planner"
        }
        // Only the filename projection is shortened; the saved source and label are untouched.
        let prefix = String(decoding: (label ?? fallback).utf8.prefix(4096), as: UTF8.self)
        let stripped = prefix.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "<>:\"/\\|?*"))
        var clean = String(
            String.UnicodeScalarView(stripped.unicodeScalars.map { forbidden.contains($0) ? UnicodeScalar(32)! : $0 }))
        clean = clean.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix(".") { clean.removeFirst() }
        while clean.hasSuffix(".") || clean.hasSuffix(" ") { clean.removeLast() }
        var result = ""
        for character in clean {
            guard result.utf8.count + character.utf8.count <= 180 else { break }
            result.append(character)
        }
        if (try? validateBasename(result)) == nil { return fallback }
        return result
    }
}
