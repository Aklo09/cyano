import Foundation
import LibraryCore

/// Data that would make totals misleading (statistics contract, "Completeness, warnings, and errors").
public enum StatisticsError: Error, Equatable, CustomStringConvertible {
    case invalidData(String)
    public var code: String { "STATISTICS_INVALID_INPUT" }
    public var description: String {
        switch self {
        case .invalidData(let message): "Statistics refused misleading blueprint data: \(message)"
        }
    }
}

public struct StatisticsItem: Codable, Equatable, Sendable {
    public let name: String
    public let quality: String
    public let count: Int
}

public struct StatisticsWarning: Codable, Equatable, Sendable {
    public let code: String
    public let name: String?
    public let quality: String?
    public let direction: Int?
    public let affects: String
    public let count: Int
}

public struct StatisticsBounds: Codable, Equatable, Sendable {
    public let minX, minY, maxX, maxY: Double
}

public struct StatisticsFootprint: Encodable, Equatable, Sendable {
    public let units = "game tiles"
    public let complete: Bool
    public let bounds: StatisticsBounds?
    public let width: Double?
    public let height: Double?
    /// The understood part of an incomplete footprint; absent when complete.
    public let knownBounds: StatisticsBounds?

    private enum CodingKeys: String, CodingKey { case units, complete, bounds, width, height, knownBounds }

    // Unknown dimensions are explicit nulls; knownBounds appears only for incomplete footprints.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(units, forKey: .units)
        try container.encode(complete, forKey: .complete)
        try container.encode(bounds, forKey: .bounds)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        if !complete { try container.encode(knownBounds, forKey: .knownBounds) }
    }
}

public struct BlueprintStatistics: Encodable, Equatable, Sendable {
    public let schemaVersion = 1
    public let applicable = true
    public let entryPath: [Int]
    public let entryKind: String
    public let gameVersion: String
    public let assetIdentity: String
    public let basis = "source-blueprint"
    public let entities: Int
    public let tiles: Int
    public let complete: Bool
    public let requirementsComplete: Bool
    public let warnings: [StatisticsWarning]
    public let footprint: StatisticsFootprint
    public let constructionItems: [StatisticsItem]
    public let placement: [StatisticsItem]
    public let modules: [StatisticsItem]
    public let equipment: [StatisticsItem]
    public let otherInserted: [StatisticsItem]
    public let equipmentRequests: [StatisticsItem]
}

/// Books and planners have no construction statistics.
public struct NotApplicableStatistics: Encodable, Equatable, Sendable {
    public let schemaVersion = 1
    public let applicable = false
    public let entryPath: [Int]
    public let entryKind: String
}

public enum StatisticsResult: Encodable, Equatable, Sendable {
    case applicable(BlueprintStatistics)
    case notApplicable(NotApplicableStatistics)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .applicable(let value): try value.encode(to: encoder)
        case .notApplicable(let value): try value.encode(to: encoder)
        }
    }
}

/// Construction requirements and footprint of one saved blueprint entry, from the saved source and a verified
/// prototype map. Pure: no I/O, no game process, input unchanged. See docs/contracts/Statistics.md.
public enum BlueprintStatisticsCalculator {
    static let maximumCount = 9_007_199_254_740_991
    static let epsilon = 1e-9

    public static func calculate(_ entry: BlueprintEntry, map: PrototypeMap) throws -> StatisticsResult {
        guard entry.kind == .blueprint else {
            return .notApplicable(NotApplicableStatistics(entryPath: entry.path, entryKind: entry.kind.rawValue))
        }
        var run = Run(map: map)
        let entities = try list(entry.body["entities"], "entities")
        let tiles = try list(entry.body["tiles"], "tiles")
        for entity in entities { try run.entity(entity) }
        for tile in tiles { try run.tile(tile) }
        return .applicable(try run.result(entry: entry, entities: entities.count, tiles: tiles.count))
    }

    /// JavaScript `Math.round`: nearest integer, halves toward positive infinity, exact for all doubles.
    static func roundHalfUp(_ value: Double) -> Double {
        let floor = value.rounded(.down)
        return value - floor >= 0.5 ? floor + 1 : floor
    }

    static func rounded(_ value: Double) -> Double { roundHalfUp(value * 1e9) / 1e9 }

    static func list(_ value: JSONValue?, _ context: String) throws -> [JSONValue] {
        guard let value else { return [] }
        guard let array = value.array else { throw StatisticsError.invalidData("\(context) must be an array") }
        return array
    }

    /// Axis-aligned extent of an oriented box rotated about the entity origin by `rotation` turns.
    static func extent(_ box: CollisionBox, rotation: Double) -> (Double, Double, Double, Double) {
        let tau = Double.pi * 2
        let centerX = (box.left + box.right) / 2
        let centerY = (box.top + box.bottom) / 2
        let turn = rotation * tau
        let x = centerX * cos(turn) - centerY * sin(turn)
        let y = centerX * sin(turn) + centerY * cos(turn)
        let angle = (box.orientation + rotation) * tau
        let width = box.right - box.left
        let height = box.bottom - box.top
        let halfX = (abs(cos(angle)) * width) / 2 + (abs(sin(angle)) * height) / 2
        let halfY = (abs(sin(angle)) * width) / 2 + (abs(cos(angle)) * height) / 2
        return (x - halfX, y - halfY, x + halfX, y + halfY)
    }
}

private struct WarningKey: Hashable {
    let code: String
    let name: String?
    let quality: String?
    let direction: Int?
}

private struct ItemKey: Hashable {
    let name: String
    let quality: String
}

private enum Bucket: CaseIterable {
    case placement, modules, equipment, otherInserted, equipmentRequests
}

private struct Run {
    let map: PrototypeMap
    var warningOrder: [WarningKey] = []
    var warningCounts: [WarningKey: Int] = [:]
    var footprintComplete = true
    var requirementsComplete = true
    var bounds: (Double, Double, Double, Double)?
    var buckets: [Bucket: [ItemKey: Int]] = [:]

    init(map: PrototypeMap) { self.map = map }

    static let affects: [String: String] = [
        "UNKNOWN_ENTITY": "both", "UNMEASURED_GEOMETRY": "footprint", "UNKNOWN_ITEM": "requirements",
        "UNKNOWN_QUALITY": "requirements", "NO_PLACEMENT_ITEM": "requirements",
        "NOT_BLUEPRINT_BUILDABLE": "requirements", "LEGACY_ITEM_FORMAT": "requirements",
        "UNKNOWN_EQUIPMENT": "requirements", "UNKNOWN_TILE": "requirements",
    ]

    mutating func warn(_ code: String, name: String? = nil, quality: String? = nil, direction: Int? = nil) {
        let affects = Self.affects[code]!
        if affects != "requirements" { footprintComplete = false }
        if affects != "footprint" { requirementsComplete = false }
        let key = WarningKey(code: code, name: name, quality: quality, direction: direction)
        if warningCounts[key] == nil { warningOrder.append(key) }
        warningCounts[key, default: 0] += 1
    }

    func invalid(_ message: String) -> StatisticsError { .invalidData(message) }

    func checkedCount(_ value: JSONValue?, default fallback: Int, _ context: String) throws -> Int {
        guard let value else { return fallback }
        guard let count = value.safeInteger else {
            throw invalid("\(context) must be an integer from 0 to 2^53 - 1")
        }
        return count
    }

    mutating func add(_ bucket: Bucket, name: String, quality: String = "normal", count: Int = 1) throws {
        guard map.items[name] != nil else { return warn("UNKNOWN_ITEM", name: name) }
        guard map.qualities.contains(quality) else { return warn("UNKNOWN_QUALITY", quality: quality) }
        guard (0...BlueprintStatisticsCalculator.maximumCount).contains(count) else {
            throw invalid("item count for \(name) is out of range")
        }
        guard count > 0 else { return }
        let key = ItemKey(name: name, quality: quality)
        let (total, overflow) = (buckets[bucket]?[key] ?? 0).addingReportingOverflow(count)
        guard !overflow, total <= BlueprintStatisticsCalculator.maximumCount else {
            throw invalid("item count overflow for \(name)")
        }
        buckets[bucket, default: [:]][key] = total
    }

    mutating func placement(_ choices: [ItemCount], quality: String, label: String) throws {
        // Construction robots use the first engine-resolved choice.
        guard let choice = choices.first else { return warn("NO_PLACEMENT_ITEM", name: label) }
        try add(.placement, name: choice.name, quality: quality, count: choice.count)
    }

    mutating func include(_ rect: (Double, Double, Double, Double)) throws {
        guard rect.0.isFinite, rect.1.isFinite, rect.2.isFinite, rect.3.isFinite else {
            throw invalid("non-finite position or geometry")
        }
        if let current = bounds {
            bounds = (min(current.0, rect.0), min(current.1, rect.1), max(current.2, rect.2), max(current.3, rect.3))
        } else {
            bounds = rect
        }
    }

    func position(_ value: JSONValue, _ context: String) throws -> (Double, Double) {
        guard let x = value["position"]?["x"]?.finiteDouble, let y = value["position"]?["y"]?.finiteDouble else {
            throw invalid("\(context) needs a finite position")
        }
        return (x, y)
    }

    func quality(_ value: JSONValue?, _ context: String) throws -> String {
        guard let value else { return "normal" }
        guard let text = value.string else { throw invalid("\(context) quality must be text") }
        return text
    }

    mutating func entity(_ value: JSONValue) throws {
        guard let name = value["name"]?.string else { throw invalid("entity needs a name") }
        let origin = try position(value, "entity \(name)")
        guard let prototype = map.entities[name] else { return warn("UNKNOWN_ENTITY", name: name) }
        if prototype.notBlueprintable || ["construction-robot", "logistic-robot"].contains(prototype.type) {
            warn("NOT_BLUEPRINT_BUILDABLE", name: name)
        }
        try placement(prototype.placement, quality: try quality(value["quality"], "entity \(name)"), label: name)
        let direction: Int
        if let raw = value["direction"] {
            guard let parsed = raw.safeInteger, (0...15).contains(parsed) else {
                throw invalid("direction of \(name) must be an integer from 0 to 15")
            }
            direction = parsed
        } else {
            direction = 0
        }
        if let shape = prototype.directions[prototype.offGrid ? 0 : direction] {
            var rotation = 0.0
            if prototype.orientationAffectsCollision {
                if let raw = value["orientation"] {
                    guard let parsed = raw.finiteDouble else { throw invalid("orientation of \(name) must be finite") }
                    rotation = parsed
                } else {
                    rotation = Double(direction) / 16
                }
                guard (0...1).contains(rotation) else { throw invalid("orientation of \(name) must be from 0 to 1") }
            }
            for box in [shape.collisionBox, shape.secondaryCollisionBox].compactMap({ $0 }) {
                var (x1, y1, x2, y2) = BlueprintStatisticsCalculator.extent(box, rotation: rotation)
                if !prototype.offGrid {
                    // Snap in the entity's local placement phase, preserving translation invariance.
                    let epsilon = BlueprintStatisticsCalculator.epsilon
                    let phaseX = Double(shape.tileWidth % 2) / 2
                    let phaseY = Double(shape.tileHeight % 2) / 2
                    x1 = (x1 + phaseX + epsilon).rounded(.down) - phaseX
                    y1 = (y1 + phaseY + epsilon).rounded(.down) - phaseY
                    x2 = (x2 + phaseX - epsilon).rounded(.up) - phaseX
                    y2 = (y2 + phaseY - epsilon).rounded(.up) - phaseY
                }
                try include((x1 + origin.0, y1 + origin.1, x2 + origin.0, y2 + origin.1))
            }
        } else {
            warn("UNMEASURED_GEOMETRY", name: name, direction: direction)
        }
        if let items = value["items"] {
            if let requests = items.array {
                for request in requests { try inserted(request, entity: name) }
            } else {
                // Pre-2.0 object format: contents are not counted.
                warn("LEGACY_ITEM_FORMAT", name: name)
            }
        }
        for entry in try BlueprintStatisticsCalculator.list(value["grid"], "grid of \(name)") {
            try installed(entry, entity: name)
        }
    }

    mutating func inserted(_ request: JSONValue, entity: String) throws {
        guard let name = request["id"]?["name"]?.string else { throw invalid("item request on \(entity) needs a name") }
        let quality = try quality(request["id"]?["quality"], "item \(name)")
        var count = 0
        for stack in try BlueprintStatisticsCalculator.list(request["items"]?["in_inventory"], "inventory of \(name)") {
            let amount = try checkedCount(stack["count"], default: 1, "inserted count of \(name)")
            let (total, overflow) = count.addingReportingOverflow(amount)
            guard !overflow, total <= BlueprintStatisticsCalculator.maximumCount else {
                throw invalid("inserted count overflow for \(name)")
            }
            count = total
        }
        if count > 0 {
            try add(map.items[name] == "module" ? .modules : .otherInserted, name: name, quality: quality, count: count)
        }
        // Bare grid requests are reported separately: the game's building cost counts installed equipment only.
        let requested = try checkedCount(request["items"]?["grid_count"], default: 0, "grid_count of \(name)")
        if requested > 0 { try add(.equipmentRequests, name: name, quality: quality, count: requested) }
    }

    mutating func installed(_ entry: JSONValue, entity: String) throws {
        let name: String?
        let qualityValue: JSONValue?
        if let text = entry["equipment"]?.string {
            (name, qualityValue) = (text, nil)
        } else if let equipment = entry["equipment"] {
            (name, qualityValue) = (equipment["name"]?.string, equipment["quality"])
        } else {
            (name, qualityValue) = (entry["name"]?.string, entry["quality"])
        }
        guard let name else { throw invalid("equipment in the grid of \(entity) needs a name") }
        let quality = try quality(qualityValue, "equipment \(name)")
        let candidates = map.equipmentItems[name] ?? []
        guard candidates.count == 1 else { return warn("UNKNOWN_EQUIPMENT", name: name) }
        try add(.equipment, name: candidates[0], quality: quality)
    }

    mutating func tile(_ value: JSONValue) throws {
        guard let name = value["name"]?.string else { throw invalid("tile needs a name") }
        let origin = try position(value, "tile \(name)")
        if let choices = map.tiles[name] {
            try placement(choices, quality: "normal", label: name)
        } else {
            warn("UNKNOWN_TILE", name: name)
        }
        // A tile always covers its 1 x 1 square, even when its placement item is unknown.
        try include((origin.0, origin.1, origin.0 + 1, origin.1 + 1))
    }

    static func sorted(_ items: [ItemKey: Int]) -> [StatisticsItem] {
        items.map { StatisticsItem(name: $0.key.name, quality: $0.key.quality, count: $0.value) }.sorted {
            $0.name != $1.name
                ? $0.name.utf8.lexicographicallyPrecedes($1.name.utf8)
                : $0.quality.utf8.lexicographicallyPrecedes($1.quality.utf8)
        }
    }

    func result(entry: BlueprintEntry, entities: Int, tiles: Int) throws -> BlueprintStatistics {
        var combined: [ItemKey: Int] = [:]
        for bucket in [Bucket.placement, .modules, .equipment, .otherInserted] {
            for (key, count) in buckets[bucket] ?? [:] {
                let (total, overflow) = (combined[key] ?? 0).addingReportingOverflow(count)
                guard !overflow, total <= BlueprintStatisticsCalculator.maximumCount else {
                    throw invalid("construction count overflow for \(key.name)")
                }
                combined[key] = total
            }
        }
        let round = BlueprintStatisticsCalculator.rounded
        let known = bounds.map {
            StatisticsBounds(minX: round($0.0), minY: round($0.1), maxX: round($0.2), maxY: round($0.3))
        }
        let footprint = StatisticsFootprint(
            complete: footprintComplete, bounds: footprintComplete ? known : nil,
            width: footprintComplete ? round(bounds.map { $0.2 - $0.0 } ?? 0) : nil,
            height: footprintComplete ? round(bounds.map { $0.3 - $0.1 } ?? 0) : nil,
            knownBounds: footprintComplete ? nil : known)
        let warnings = warningOrder.map { key in
            StatisticsWarning(
                code: key.code, name: key.name, quality: key.quality, direction: key.direction,
                affects: Self.affects[key.code]!, count: warningCounts[key]!)
        }
        func group(_ bucket: Bucket) -> [StatisticsItem] { Self.sorted(buckets[bucket] ?? [:]) }
        return BlueprintStatistics(
            entryPath: entry.path, entryKind: entry.kind.rawValue, gameVersion: map.gameVersion,
            assetIdentity: map.assetIdentity, entities: entities, tiles: tiles,
            complete: footprintComplete && requirementsComplete, requirementsComplete: requirementsComplete,
            warnings: warnings, footprint: footprint, constructionItems: Self.sorted(combined),
            placement: group(.placement), modules: group(.modules), equipment: group(.equipment),
            otherInserted: group(.otherInserted), equipmentRequests: group(.equipmentRequests))
    }
}
