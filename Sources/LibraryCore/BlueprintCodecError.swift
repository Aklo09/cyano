public enum BlueprintCodecLimit: String, Sendable {
    case sourceBytes, decodedBytes, jsonDepth, bookDepth, entries, entitiesAndTiles, jsonNodes
}

public enum BlueprintCodecError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidSource(String)
    case limitExceeded(BlueprintCodecLimit)
    case invalidEntryPath
    case invalidLimits
    case compressionFailure

    public var description: String {
        switch self {
        case .invalidSource(let reason): reason
        case .limitExceeded(let limit): "Blueprint exceeds the \(limit.rawValue) limit."
        case .invalidEntryPath: "The path does not identify an entry in this document."
        case .invalidLimits: "Codec limits must be nonnegative and cannot exceed the supported defaults."
        case .compressionFailure: "The system compression operation failed."
        }
    }
}

public struct BlueprintCodecLimits: Sendable {
    public var sourceBytes = 16 * 1024 * 1024
    public var decodedBytes = 64 * 1024 * 1024
    public var jsonDepth = 128
    public var bookDepth = 32
    public var entries = 10_000
    public var entitiesAndTiles = 100_000
    public var jsonNodes = 1_000_000

    public init() {}

    public static let standard = BlueprintCodecLimits()

    func validate() throws {
        let ceilings = Self.standard
        for (value, maximum) in [
            (sourceBytes, ceilings.sourceBytes), (decodedBytes, ceilings.decodedBytes),
            (jsonDepth, ceilings.jsonDepth), (bookDepth, ceilings.bookDepth),
            (entries, ceilings.entries), (entitiesAndTiles, ceilings.entitiesAndTiles),
            (jsonNodes, ceilings.jsonNodes),
        ] {
            guard value >= 0, value <= maximum else { throw BlueprintCodecError.invalidLimits }
        }
    }
}
