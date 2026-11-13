import Foundation

public enum NativeLibraryError: Error, Equatable, Sendable, CustomStringConvertible {
    case inUse, closed, unsupportedFilesystem, unsafePath, invalidFormat, unsupportedVersion
    case invalidMetadata, integrity, recoveryRequired, notFound, limitExceeded, invalidInput
    case nameCollision, folderNotEmpty, sourceChanged, ambiguousId
    case io(Int32)

    public var code: String {
        switch self {
        case .inUse: "LIBRARY_IN_USE"
        case .closed: "LIBRARY_CLOSED"
        case .unsupportedFilesystem: "UNSUPPORTED_FILESYSTEM"
        case .unsafePath: "UNSAFE_PATH"
        case .invalidFormat: "INVALID_LIBRARY_FORMAT"
        case .unsupportedVersion: "UNSUPPORTED_VERSION"
        case .invalidMetadata: "INVALID_METADATA"
        case .integrity: "INTEGRITY_CONFLICT"
        case .recoveryRequired: "RECOVERY_REQUIRED"
        case .notFound: "ITEM_NOT_FOUND"
        case .limitExceeded: "LIBRARY_LIMIT"
        case .invalidInput: "INVALID_INPUT"
        case .nameCollision: "NAME_COLLISION"
        case .folderNotEmpty: "FOLDER_NOT_EMPTY"
        case .sourceChanged: "SOURCE_CHANGED"
        case .ambiguousId: "AMBIGUOUS_ID"
        case .io: "FILESYSTEM_ERROR"
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .inUse, .closed, .unsupportedFilesystem: 3
        case .integrity, .recoveryRequired, .ambiguousId: 4
        case .invalidFormat, .unsupportedVersion, .invalidMetadata: 5
        case .io: 6
        case .unsafePath, .notFound, .limitExceeded, .invalidInput, .nameCollision, .folderNotEmpty, .sourceChanged:
            7
        }
    }

    public var category: String {
        switch exitCode {
        case 3: "ownership"
        case 4: "recovery"
        case 5: "compatibility"
        case 6: "io"
        default: "validation"
        }
    }

    public var description: String {
        switch self {
        case .inUse: "Another application or CLI process owns this library."
        case .closed: "This library session is closed."
        case .unsupportedFilesystem: "Choose local APFS storage outside known synchronized locations."
        case .unsafePath: "An unsafe path, link, or filesystem object was refused."
        case .invalidFormat: "The directory is not a recognized native library or empty initialization target."
        case .unsupportedVersion: "The native format version is unsupported."
        case .invalidMetadata: "Metadata is malformed, unsupported, or contains unexpected fields."
        case .integrity: "Stored bytes conflict with their expected hashes; evidence has been preserved."
        case .recoveryRequired: "An interrupted operation needs recovery; close and reopen or run recover."
        case .notFound: "No unique matching saved item exists."
        case .limitExceeded: "A bounded library scan or metadata limit was exceeded."
        case .invalidInput: "The requested name, comment, or identifier is invalid."
        case .nameCollision: "The destination already contains a conflicting name."
        case .folderNotEmpty: "Only an empty folder can be deleted."
        case .ambiguousId: "More than one saved item has this ID; resolve the duplicate files before using it."
        case .sourceChanged: "The item changed while its preview was rendering; the result was not saved. Retry."
        case .io(let number): "A filesystem operation failed (errno \(number))."
        }
    }
}

enum LibraryBounds {
    static let metadata = 4 * 1024 * 1024
    static let journal = 64 * 1024
    static let comment = 64 * 1024
    static let comments = 10_000
    static let directoryEntries = 100_000
    static let operations = 128
    static let folderDepth = 32
    static let transaction = 16 * 1024 * 1024
    static let transactionBytes = 256 * 1024 * 1024
    static let changes = 10_000
}
