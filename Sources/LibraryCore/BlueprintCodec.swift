import Foundation

public enum BlueprintEntryKind: String, CaseIterable, Sendable {
    case blueprint
    case book = "blueprint_book"
    case upgradePlanner = "upgrade_planner"
    case deconstructionPlanner = "deconstruction_planner"
}

public struct BlueprintEntry: Sendable {
    public let path: [Int]
    public let kind: BlueprintEntryKind
    public let value: JSONValue
    public let body: JSONValue
    public let version: Int

    public var label: String? { body["label"]?.string }

    public var description: String {
        if kind == .upgradePlanner || kind == .deconstructionPlanner,
           let text = body["settings"]?["description"]?.string { return text }
        return body["description"]?.string ?? ""
    }

    init(value: JSONValue, path: [Int]) throws {
        let kinds = BlueprintEntryKind.allCases.filter { value[$0.rawValue] != nil }
        guard value.isObject, kinds.count == 1,
              let kind = kinds.first, let body = value[kind.rawValue], body.isObject,
              let version = body["version"]?.safeInteger else {
            throw BlueprintCodecError.invalidSource("Expected one versioned blueprint, book, or planner object.")
        }
        self.value = value
        self.path = path
        self.kind = kind
        self.body = body
        self.version = version
    }
}

public struct BlueprintDocument: Sendable {
    public let original: OriginalSource
    public let root: BlueprintEntry
    private let limits: BlueprintCodecLimits

    init(original: OriginalSource, root: BlueprintEntry, limits: BlueprintCodecLimits) {
        self.original = original
        self.root = root
        self.limits = limits
    }

    public func entry(at path: [Int]) throws -> BlueprintEntry {
        guard path.count <= limits.bookDepth,
              path.allSatisfy({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }) else {
            throw BlueprintCodecError.invalidEntryPath
        }
        var current = root
        for (offset, index) in path.enumerated() {
            guard current.kind == .book,
                  let child = current.body["blueprints"]?.array?.first(where: { $0["index"]?.safeInteger == index }) else {
                throw BlueprintCodecError.invalidEntryPath
            }
            current = try BlueprintEntry(value: child, path: Array(path.prefix(offset + 1)))
        }
        return current
    }

    /// Root exports return the exact imported bytes. Selected entries are new format-0 strings.
    public func export(at path: [Int] = []) throws -> Data {
        guard !path.isEmpty else { return original.bytes }
        let selected = try entry(at: path)
        guard case .object(let members) = selected.value else { throw BlueprintCodecError.invalidEntryPath }
        let standalone = JSONValue.object(members.filter { !$0.key.utf8.elementsEqual("index".utf8) })
        let json = try standalone.encoded(maximum: limits.decodedBytes)
        let compressedMaximum = max(0, (limits.sourceBytes - 1) / 4) * 3
        let compressed = try ZlibCodec.compress(json, maximum: compressedMaximum)
        let bytes = Data(("0" + compressed.base64EncodedString()).utf8)
        guard bytes.count <= limits.sourceBytes else { throw BlueprintCodecError.limitExceeded(.sourceBytes) }
        return bytes
    }
}

public enum BlueprintCodec {
    public static func decode(_ bytes: Data, limits: BlueprintCodecLimits = .standard) throws -> BlueprintDocument {
        try limits.validate()
        guard bytes.count <= limits.sourceBytes else { throw BlueprintCodecError.limitExceeded(.sourceBytes) }
        guard let source = String(data: bytes, encoding: .utf8) else {
            throw BlueprintCodecError.invalidSource("Blueprint source is not valid UTF-8.")
        }
        let whitespace = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))
        let encoded = source.trimmingCharacters(in: whitespace)
        guard encoded.first == "0" else {
            throw BlueprintCodecError.invalidSource("Only Factorio blueprint string format 0 is supported.")
        }
        let payload = String(encoded.dropFirst())
        guard !payload.isEmpty, payload.utf8.count.isMultiple(of: 4),
              let compressed = Data(base64Encoded: payload), compressed.base64EncodedString() == payload else {
            throw BlueprintCodecError.invalidSource("Blueprint base64 must be valid and canonical.")
        }
        let json = try ZlibCodec.decompress(compressed, maximum: limits.decodedBytes)
        var parser = try BoundedJSONParser(data: json, limits: limits)
        let value = try parser.parse()
        let root = try BlueprintEntry(value: value, path: [])
        try validateEntries(root, limits: limits)
        return BlueprintDocument(original: OriginalSource(bytes: bytes), root: root, limits: limits)
    }

    private static func validateEntries(_ root: BlueprintEntry, limits: BlueprintCodecLimits) throws {
        var pending: [(BlueprintEntry, Int)] = [(root, 0)]
        var count = 0
        var objects = 0
        while let (entry, depth) = pending.popLast() {
            count += 1
            guard count <= limits.entries else { throw BlueprintCodecError.limitExceeded(.entries) }
            guard depth <= limits.bookDepth else { throw BlueprintCodecError.limitExceeded(.bookDepth) }
            if let label = entry.body["label"], label.string == nil {
                throw BlueprintCodecError.invalidSource("Entry labels must be text.")
            }
            if entry.kind == .book {
                if let children = entry.body["blueprints"] {
                    guard let children = children.array else {
                        throw BlueprintCodecError.invalidSource("Book entries must be an array.")
                    }
                    guard count + pending.count + children.count <= limits.entries else {
                        throw BlueprintCodecError.limitExceeded(.entries)
                    }
                    var indices = Set<Int>()
                    for child in children {
                        guard let index = child["index"]?.safeInteger, indices.insert(index).inserted else {
                            throw BlueprintCodecError.invalidSource("Book entry indices must be unique nonnegative safe integers.")
                        }
                        pending.append((try BlueprintEntry(value: child, path: []), depth + 1))
                    }
                }
            } else if entry.kind == .blueprint {
                for key in ["entities", "tiles"] {
                    guard let rows = entry.body[key] else { continue }
                    guard let rows = rows.array else {
                        throw BlueprintCodecError.invalidSource("Entities and tiles must be arrays.")
                    }
                    objects += rows.count
                    guard objects <= limits.entitiesAndTiles else {
                        throw BlueprintCodecError.limitExceeded(.entitiesAndTiles)
                    }
                    for row in rows {
                        guard row.isObject, row["name"]?.string != nil,
                              let position = row["position"], position.isObject,
                              position["x"]?.isFiniteNumber == true, position["y"]?.isFiniteNumber == true else {
                            throw BlueprintCodecError.invalidSource("Entity and tile names and finite positions are required.")
                        }
                    }
                }
            }
        }
    }
}
