import Foundation
import LibraryCore

public enum PrototypeMapError: Error, Equatable, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self {
        case .invalid(let message): "Invalid prototype map: \(message)"
        }
    }
}

/// An oriented collision box: corners in entity-local game tiles, plus the box's own orientation (0–1 turns).
public struct CollisionBox: Equatable, Sendable {
    public let left, top, right, bottom, orientation: Double
}

/// Collision geometry for one entity direction.
public struct EntityShape: Equatable, Sendable {
    public let tileWidth: Int
    public let tileHeight: Int
    public let collisionBox: CollisionBox
    public let secondaryCollisionBox: CollisionBox?
}

public struct ItemCount: Equatable, Sendable {
    public let name: String
    public let count: Int
}

public struct EntityPrototype: Equatable, Sendable {
    public let type: String
    /// Engine-resolved placement choices; construction robots use the first.
    public let placement: [ItemCount]
    public let offGrid: Bool
    public let notBlueprintable: Bool
    public let orientationAffectsCollision: Bool
    /// Geometry for directions 0–15.
    public let directions: [Int: EntityShape]
}

/// Prototype data for construction statistics, loaded only from a verified asset release
/// and bound to that release's identity (statistics contract, "Prototype data").
public struct PrototypeMap: Sendable {
    public static let path = "statistics/prototype-map.json"
    public static let maximumBytes = 16 * 1024 * 1024
    static let maximumPrototypes = 100_000

    public let assetIdentity: String
    public let gameVersion: String
    public let mods: [String: String]
    public let qualities: Set<String>
    public let entities: [String: EntityPrototype]
    /// Tile name to its placement choices.
    public let tiles: [String: [ItemCount]]
    /// Item name to its item type, e.g. `module`.
    public let items: [String: String]
    /// Equipment name to the items that place it.
    public let equipmentItems: [String: [String]]

    /// Verifies the release, then loads the exact map bytes its inventory lists.
    public static func load(release url: URL) throws -> PrototypeMap {
        let report = try AssetRelease.verify(at: url)
        let root = try LibraryDirectory(url: url)
        let bytes = try root.child("statistics").read("prototype-map.json", maximum: maximumBytes)
        // The map may have changed since verification; only the verified bytes are accepted.
        guard OriginalSource(bytes: bytes).sha256 == report.prototypeMapSha256 else {
            throw PrototypeMapError.invalid("the map changed after release verification")
        }
        return try parse(bytes, assetIdentity: report.identity)
    }

    package static func parse(_ data: Data, assetIdentity: String) throws -> PrototypeMap {
        guard data.count <= maximumBytes else { throw PrototypeMapError.invalid("larger than 16 MiB") }
        var limits = BlueprintCodecLimits()
        limits.decodedBytes = maximumBytes
        let root: JSONValue
        do {
            var parser = try BoundedJSONParser(data: data, limits: limits)
            root = try parser.parse()
        } catch { throw PrototypeMapError.invalid("malformed JSON") }
        return try PrototypeMapReader(assetIdentity: assetIdentity).read(root)
    }
}

/// Strict reader: every field has a known type, unknown fields are refused, and references must resolve.
private struct PrototypeMapReader {
    let assetIdentity: String

    func fail(_ message: String) -> PrototypeMapError { .invalid(message) }

    func members(_ value: JSONValue?, _ context: String) throws -> [JSONMember] {
        guard case .object(let members) = value else { throw fail("\(context) must be an object") }
        guard members.count <= PrototypeMap.maximumPrototypes else { throw fail("\(context) is too large") }
        return members
    }

    func fields(
        _ value: JSONValue?, _ context: String, required: Set<String>, optional: Set<String> = []
    ) throws -> [String: JSONValue] {
        let list = try members(value, context)
        let keys = Set(list.map(\.key))
        guard required.isSubset(of: keys) else {
            throw fail("\(context) lacks \(required.subtracting(keys).sorted().joined(separator: ", "))")
        }
        let unknown = keys.subtracting(required.union(optional))
        guard unknown.isEmpty else { throw fail("\(context) has unknown \(unknown.sorted().joined(separator: ", "))") }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0.value) })
    }

    func string(_ value: JSONValue?, _ context: String) throws -> String {
        guard let text = value?.string, !text.isEmpty, text.utf8.count <= 1024 else {
            throw fail("\(context) must be a nonempty string")
        }
        return text
    }

    func bool(_ value: JSONValue?, _ context: String) throws -> Bool {
        guard case .bool(let flag) = value else { throw fail("\(context) must be a boolean") }
        return flag
    }

    func integer(_ value: JSONValue?, _ context: String, _ range: ClosedRange<Int>) throws -> Int {
        guard let number = value?.safeInteger, range.contains(number) else {
            throw fail("\(context) must be an integer in \(range.lowerBound)...\(range.upperBound)")
        }
        return number
    }

    func number(_ value: JSONValue?, _ context: String) throws -> Double {
        guard let number = value?.finiteDouble else { throw fail("\(context) must be a finite number") }
        return number
    }

    func box(_ value: JSONValue?, _ context: String) throws -> CollisionBox {
        guard let parts = value?.array, parts.count == 3,
            let first = parts[0].array, first.count == 2, let second = parts[1].array, second.count == 2
        else { throw fail("\(context) must be [[x1, y1], [x2, y2], orientation]") }
        let box = CollisionBox(
            left: try number(first[0], context), top: try number(first[1], context),
            right: try number(second[0], context), bottom: try number(second[1], context),
            orientation: try number(parts[2], context))
        guard box.left <= box.right, box.top <= box.bottom, (0..<1).contains(box.orientation) else {
            throw fail("\(context) has inverted corners or an orientation outside 0..<1")
        }
        return box
    }

    func placement(_ value: JSONValue?, _ context: String) throws -> [ItemCount] {
        guard let choices = value?.array, choices.count <= 64 else { throw fail("\(context) must be an array") }
        return try choices.map { choice in
            let field = try fields(choice, context, required: ["name", "count"])
            return ItemCount(
                name: try string(field["name"], context),
                count: try integer(field["count"], context, 1...9_007_199_254_740_991))
        }
    }

    func entity(_ name: String, _ value: JSONValue) throws -> EntityPrototype {
        let context = "entity \(name)"
        let field = try fields(
            value, context,
            required: [
                "type", "placement", "tileWidth", "tileHeight", "collisionBox", "selectionBox", "offGrid",
                "notBlueprintable", "supportsDirection", "orientationAffectsCollision", "directions",
            ])
        // Entity-level size and boxes duplicate direction 0; they are validated but statistics use directions.
        _ = try integer(field["tileWidth"], context, 0...1024)
        _ = try integer(field["tileHeight"], context, 0...1024)
        _ = try box(field["collisionBox"], context)
        _ = try box(field["selectionBox"], context)
        _ = try bool(field["supportsDirection"], context)
        var directions: [Int: EntityShape] = [:]
        for member in try members(field["directions"], "\(context) directions") {
            guard let direction = Int(member.key), (0...15).contains(direction), String(direction) == member.key
            else { throw fail("\(context) has direction key \(member.key)") }
            let shapeContext = "\(context) direction \(direction)"
            let shape = try fields(
                member.value, shapeContext,
                required: [
                    "direction", "orientation", "source", "tileWidth", "tileHeight", "collisionBox", "selectionBox",
                ], optional: ["secondaryCollisionBox"])
            // The key is the requested blueprint direction; `direction` is the engine-resolved one it maps to
            // (a chest resolves every direction to 0). Statistics use the geometry stored under the key.
            _ = try integer(shape["direction"], shapeContext, 0...15)
            let orientation = try number(shape["orientation"], shapeContext)
            guard (0..<1).contains(orientation) else { throw fail("\(shapeContext) orientation outside 0..<1") }
            guard ["entity", "ghost"].contains(try string(shape["source"], shapeContext)) else {
                throw fail("\(shapeContext) source must be entity or ghost")
            }
            _ = try box(shape["selectionBox"], shapeContext)
            directions[direction] = EntityShape(
                tileWidth: try integer(shape["tileWidth"], shapeContext, 0...1024),
                tileHeight: try integer(shape["tileHeight"], shapeContext, 0...1024),
                collisionBox: try box(shape["collisionBox"], shapeContext),
                secondaryCollisionBox: try shape["secondaryCollisionBox"].map {
                    try box($0, "\(shapeContext) secondary")
                })
        }
        return EntityPrototype(
            type: try string(field["type"], context), placement: try placement(field["placement"], context),
            offGrid: try bool(field["offGrid"], context),
            notBlueprintable: try bool(field["notBlueprintable"], context),
            orientationAffectsCollision: try bool(field["orientationAffectsCollision"], context),
            directions: directions)
    }

    func read(_ root: JSONValue) throws -> PrototypeMap {
        let field = try fields(
            root, "map",
            required: [
                "schema", "gameVersion", "mods", "qualities", "entities", "tiles", "items", "equipmentItems",
            ], optional: ["footprintDefinition"])
        guard field["schema"]?.safeInteger == 1 else { throw fail("schema must be 1") }
        if let definition = field["footprintDefinition"] { _ = try string(definition, "footprintDefinition") }
        var mods: [String: String] = [:]
        for member in try members(field["mods"], "mods") { mods[member.key] = try string(member.value, "mod version") }
        guard !mods.isEmpty else { throw fail("mods must not be empty") }
        var qualities = Set<String>()
        for member in try members(field["qualities"], "qualities") {
            guard case .bool(true) = member.value, !member.key.isEmpty else {
                throw fail("qualities must map names to true")
            }
            qualities.insert(member.key)
        }
        guard qualities.contains("normal") else { throw fail("qualities must include normal") }
        var items: [String: String] = [:]
        var equipmentPlacers: [String: String] = [:]
        for member in try members(field["items"], "items") {
            let item = try fields(member.value, "item \(member.key)", required: ["type"], optional: ["equipment"])
            items[member.key] = try string(item["type"], "item \(member.key) type")
            if let equipment = item["equipment"] {
                equipmentPlacers[member.key] = try string(equipment, "item \(member.key) equipment")
            }
        }
        var entities: [String: EntityPrototype] = [:]
        for member in try members(field["entities"], "entities") {
            entities[member.key] = try entity(member.key, member.value)
        }
        var tiles: [String: [ItemCount]] = [:]
        for member in try members(field["tiles"], "tiles") {
            let tile = try fields(member.value, "tile \(member.key)", required: ["placement"])
            tiles[member.key] = try placement(tile["placement"], "tile \(member.key) placement")
        }
        var equipmentItems: [String: [String]] = [:]
        for member in try members(field["equipmentItems"], "equipmentItems") {
            guard let names = member.value.array, !names.isEmpty, names.count <= 64 else {
                throw fail("equipmentItems \(member.key) must be a nonempty array")
            }
            equipmentItems[member.key] = try names.map { try string($0, "equipmentItems \(member.key)") }
        }
        // Every reference must resolve, so a statistics warning always means the blueprint, never the map.
        for (name, entity) in entities {
            for choice in entity.placement where items[choice.name] == nil {
                throw fail("entity \(name) places unknown item \(choice.name)")
            }
        }
        for (name, choices) in tiles {
            for choice in choices where items[choice.name] == nil {
                throw fail("tile \(name) places unknown item \(choice.name)")
            }
        }
        for (equipment, names) in equipmentItems {
            for name in names where equipmentPlacers[name] != equipment {
                throw fail("equipmentItems \(equipment) lists \(name), which does not place it")
            }
        }
        return PrototypeMap(
            assetIdentity: assetIdentity, gameVersion: try string(field["gameVersion"], "gameVersion"), mods: mods,
            qualities: qualities, entities: entities, tiles: tiles, items: items, equipmentItems: equipmentItems)
    }
}
