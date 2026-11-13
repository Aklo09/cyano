import Foundation
import LibraryCore
import Testing

@testable import FactorioData

/// The prototype-map test fixture, extended with every prototype the statistics rules exercise.
/// Geometry uses binary-exact values so expected footprints are exact.
func statisticsMapJSON(dropSecondary: Bool = false) -> [String: Any] {
    var map = syntheticPrototypeMap()
    func box(_ halfWidth: Double, _ halfHeight: Double, _ orientation: Double = 0) -> [Any] {
        [[-halfWidth, -halfHeight], [halfWidth, halfHeight], orientation]
    }
    func shape(_ direction: Int, _ width: Int, _ height: Int, _ collision: [Any]) -> [String: Any] {
        [
            "direction": direction, "orientation": Double(direction) / 16, "source": "entity", "tileWidth": width,
            "tileHeight": height, "collisionBox": collision, "selectionBox": collision,
        ]
    }
    func entity(
        _ type: String, placement: String, count: Int = 1, offGrid: Bool = false, rotates: Bool = false,
        directions: [Int: [String: Any]]
    ) -> [String: Any] {
        [
            "type": type, "placement": [["name": placement, "count": count]], "tileWidth": 1, "tileHeight": 1,
            "collisionBox": box(0.25, 0.25), "selectionBox": box(0.5, 0.5), "offGrid": offGrid,
            "notBlueprintable": false, "supportsDirection": directions.count > 1,
            "orientationAffectsCollision": rotates,
            "directions": Dictionary(uniqueKeysWithValues: directions.map { (String($0.key), $0.value) }),
        ]
    }
    func all(_ width: Int, _ height: Int, _ collision: [Any]) -> [Int: [String: Any]] {
        Dictionary(uniqueKeysWithValues: (0...15).map { ($0, shape($0, width, height, collision)) })
    }
    var entities = map["entities"] as! [String: Any]
    entities["assembling-machine-3"] = entity(
        "assembling-machine", placement: "assembling-machine-3", directions: all(3, 3, box(1.19921875, 1.19921875)))
    entities["boiler"] = entity(
        "boiler", placement: "boiler",
        directions: [
            0: shape(0, 3, 2, box(1.2890625, 0.7890625)), 4: shape(4, 2, 3, box(0.7890625, 1.2890625)),
        ])
    entities["requester-chest"] = entity(
        "logistic-container", placement: "requester-chest", directions: all(1, 1, box(0.34765625, 0.34765625)))
    entities["spidertron"] = entity(
        "spider-vehicle", placement: "spidertron", offGrid: true, directions: [0: shape(0, 2, 2, box(1, 1))])
    entities["car"] = entity(
        "car", placement: "car", offGrid: true, rotates: true, directions: [0: shape(0, 1, 2, box(0.69921875, 1))])
    entities["locomotive"] = entity(
        "locomotive", placement: "locomotive", offGrid: true, rotates: true,
        directions: [0: shape(0, 2, 6, box(0.59765625, 2.59765625))])
    entities["construction-robot"] = entity(
        "construction-robot", placement: "construction-robot", offGrid: true,
        directions: [0: shape(0, 1, 1, box(0.25, 0.25))])
    entities["curved-rail-a"] = entity(
        "curved-rail-a", placement: "rail", count: 3, directions: all(2, 2, box(0.75, 2.5)))
    entities["half-diagonal-rail"] = entity(
        "half-diagonal-rail", placement: "rail", count: 2, directions: all(2, 2, box(0.75, 1.5)))
    // Direction 2 is diagonal: the box itself is oriented an eighth of a turn.
    entities["straight-rail"] = entity(
        "straight-rail", placement: "rail", directions: [2: shape(2, 2, 2, box(0.69921875, 1.98828125, 0.125))])
    entities["rail-ramp"] = entity(
        "rail-ramp", placement: "rail-ramp", directions: [4: shape(4, 16, 4, box(7.796875, 1.796875))])
    if dropSecondary {
        var rail = entities["legacy-curved-rail"] as! [String: Any]
        var directions = rail["directions"] as! [String: Any]
        var zero = directions["0"] as! [String: Any]
        zero["secondaryCollisionBox"] = nil
        directions["0"] = zero
        rail["directions"] = directions
        entities["legacy-curved-rail"] = rail
    }
    map["entities"] = entities
    var items = map["items"] as! [String: Any]
    for name in [
        "assembling-machine-3", "requester-chest", "spidertron", "locomotive", "construction-robot", "rail-ramp",
        "coal", "iron-plate", "stone-brick",
    ] { items[name] = ["type": "item"] }
    items["speed-module-3"] = ["type": "module"]
    map["items"] = items
    var tiles = map["tiles"] as! [String: Any]
    tiles["stone-path"] = ["placement": [["name": "stone-brick", "count": 1]]]
    map["tiles"] = tiles
    map["qualities"] = ["normal": true, "uncommon": true, "rare": true, "epic": true, "legendary": true]
    return map
}

private let statisticsMap = try! PrototypeMap.parse(
    assetJSON(statisticsMapJSON()), assetIdentity: String(repeating: "b", count: 64))

private func blueprint(
    _ entities: [[String: Any]] = [], tiles: [[String: Any]]? = nil, kind: String = "blueprint", path: [Int] = []
) throws -> BlueprintEntry {
    var body: [String: Any] = ["version": 1, "entities": entities]
    if let tiles { body["tiles"] = tiles }
    var parser = try BoundedJSONParser(
        data: JSONSerialization.data(withJSONObject: [kind: body]), limits: .standard)
    return try BlueprintEntry(value: parser.parse(), path: path)
}

private func entity(_ name: String, _ x: Double = 0.5, _ y: Double = 0.5, _ extra: [String: Any] = [:])
    -> [String: Any]
{
    ["entity_number": 1, "name": name, "position": ["x": x, "y": y]].merging(extra) { _, new in new }
}

private func stats(_ entry: BlueprintEntry, map: PrototypeMap = statisticsMap) throws -> BlueprintStatistics {
    guard case .applicable(let result) = try BlueprintStatisticsCalculator.calculate(entry, map: map) else {
        throw StatisticsError.invalidData("expected an applicable result")
    }
    return result
}

private func dimensions(_ entry: BlueprintEntry, map: PrototypeMap = statisticsMap) throws -> [Double?] {
    let footprint = try stats(entry, map: map).footprint
    return [footprint.width, footprint.height]
}

private func item(_ name: String, _ quality: String = "normal", _ count: Int = 1) -> StatisticsItem {
    StatisticsItem(name: name, quality: quality, count: count)
}

/// Speed modules in two inventory slots, counts omitted: one module per slot.
private func qualityAndModules() -> [[String: Any]] {
    [
        entity(
            "assembling-machine-3", 0.5, 0.5,
            [
                "quality": "legendary",
                "items": [
                    [
                        "id": ["name": "speed-module-3", "quality": "epic"],
                        "items": ["in_inventory": [["inventory": 4, "stack": 0], ["inventory": 4, "stack": 1]]],
                    ]
                ],
            ]),
        entity("assembling-machine-3", 5.5, 0.5, ["entity_number": 2]),
    ]
}

@Suite("Construction statistics")
struct BlueprintStatisticsTests {
    @Test("Footprints use game tiles, not collision-box widths or image pixels")
    func gameUnits() throws {
        #expect(try dimensions(blueprint([entity("wooden-chest")])) == [1, 1])
        #expect(try dimensions(blueprint([entity("assembling-machine-3")])) == [3, 3])
        let empty = try stats(blueprint())
        #expect(empty.footprint.width == 0 && empty.footprint.height == 0 && empty.footprint.bounds == nil)
        #expect(empty.complete)
    }

    @Test("Cardinal rotation uses the direction's own geometry")
    func cardinalRotation() throws {
        #expect(try dimensions(blueprint([entity("boiler", 0, 0, ["direction": 0])])) == [3, 2])
        #expect(try dimensions(blueprint([entity("boiler", 0, 0, ["direction": 4])])) == [2, 3])
    }

    @Test("The rectangle contains gaps, negative coordinates, and tiles")
    func gapsAndTiles() throws {
        let gap = [entity("wooden-chest", -5.5, -2.5), entity("wooden-chest", 4.5, -2.5, ["entity_number": 2])]
        #expect(try dimensions(blueprint(gap)) == [11, 1])
        let tiles: [[String: Any]] = [
            ["name": "stone-path", "position": ["x": -2, "y": 3]], ["name": "concrete", "position": ["x": 2, "y": 5]],
        ]
        #expect(try dimensions(blueprint(tiles: tiles)) == [5, 3])
        let mixed = try blueprint(
            [entity("wooden-chest")], tiles: [["name": "concrete", "position": ["x": 4, "y": 2]]])
        #expect(try dimensions(mixed) == [5, 3])
    }

    @Test("Dimensions are invariant under arbitrary translation")
    func translation() throws {
        let shifted = qualityAndModules().map { value -> [String: Any] in
            var moved = value
            let position = value["position"] as! [String: Double]
            moved["position"] = ["x": position["x"]! + 0.125, "y": position["y"]! - 100.75]
            return moved
        }
        #expect(try dimensions(blueprint(shifted)) == dimensions(blueprint(qualityAndModules())))
    }

    @Test("Rail costs use prototype quantities; diagonal geometry uses the oriented box")
    func rails() throws {
        #expect(try stats(blueprint([entity("curved-rail-a", 0, 0)])).constructionItems == [item("rail", "normal", 3)])
        #expect(
            try stats(blueprint([entity("half-diagonal-rail", 0, 0)])).constructionItems == [item("rail", "normal", 2)])
        #expect(try dimensions(blueprint([entity("straight-rail", 0, 0, ["direction": 2])])) == [4, 4])
        #expect(try dimensions(blueprint([entity("rail-ramp", 0, 0, ["direction": 4])])) == [16, 4])
    }

    @Test("Secondary collision boxes contribute to a rail footprint")
    func secondaryBoxes() throws {
        let without = try PrototypeMap.parse(
            assetJSON(statisticsMapJSON(dropSecondary: true)), assetIdentity: String(repeating: "b", count: 64))
        let rail = try blueprint([entity("legacy-curved-rail", 0, 0)])
        #expect(try dimensions(rail) != dimensions(rail, map: without))
    }

    @Test("Qualities stay distinct and an inserted module counts one per slot by default")
    func qualitiesAndModules() throws {
        let result = try stats(blueprint(qualityAndModules()))
        #expect(result.modules == [item("speed-module-3", "epic", 2)])
        #expect(
            result.placement == [item("assembling-machine-3", "legendary"), item("assembling-machine-3", "normal")])
    }

    @Test("Installed equipment counts once; bare equipment requests stay out of the totals")
    func equipment() throws {
        let grid = try blueprint([
            entity(
                "spidertron", 0, 0,
                [
                    "grid": [
                        ["equipment": ["name": "battery-equipment", "quality": "rare"], "position": ["x": 0, "y": 0]]
                    ]
                ])
        ])
        #expect(try stats(grid).equipment == [item("battery-equipment", "rare")])
        let plan = try stats(
            blueprint([
                entity(
                    "spidertron", 0, 0,
                    ["items": [["id": ["name": "battery-equipment", "quality": "rare"], "items": ["grid_count": 1]]]])
            ]))
        #expect(!plan.constructionItems.contains { $0.name == "battery-equipment" })
        #expect(plan.equipmentRequests == [item("battery-equipment", "rare")])
    }

    @Test("Inserted fuel counts; logistics requests and filters do not")
    func fuelAndLogistics() throws {
        let fuel = try blueprint([
            entity(
                "locomotive", 0, 0,
                [
                    "items": [
                        [
                            "id": ["name": "coal"],
                            "items": ["in_inventory": [["inventory": 1, "stack": 0, "count": 5]]],
                        ]
                    ]
                ])
        ])
        #expect(try stats(fuel).otherInserted == [item("coal", "normal", 5)])
        let filters: [String: Any] = [
            "sections": [
                [
                    "index": 1,
                    "filters": [
                        [
                            "index": 1, "min": 100,
                            "value": ["type": "item", "name": "iron-plate", "quality": "normal", "comparator": "="],
                        ]
                    ],
                ]
            ]
        ]
        let requester = try blueprint([entity("requester-chest", 0.5, 0.5, ["request_filters": filters])])
        #expect(try stats(requester).constructionItems == [item("requester-chest")])
    }

    @Test("Off-grid vehicles keep fractional extents; a spidertron's orientation does not rotate its body")
    func offGrid() throws {
        let straight = try dimensions(blueprint([entity("car", 0.25, -0.125, ["orientation": 0])]))
        let turned = try dimensions(blueprint([entity("car", 0.25, -0.125, ["orientation": 0.25])]))
        #expect(straight[0] == 1.3984375)
        #expect(straight[0] == turned[1] && straight[1] == turned[0])
        #expect(try dimensions(blueprint([entity("spidertron", 0, 0, ["orientation": 0.125])])) == [2, 2])
    }

    @Test("Unknown prototypes give incomplete results without guessed dimensions")
    func unknownPrototypes() throws {
        let unknown = try stats(blueprint([entity("fb-unknown")]))
        #expect(!unknown.complete && unknown.footprint.width == nil && unknown.footprint.knownBounds == nil)
        let tile = try stats(blueprint(tiles: [["name": "fb-unknown", "position": ["x": 0, "y": 0]]]))
        #expect(!tile.requirementsComplete && tile.footprint.complete)
        #expect(tile.footprint.width == 1 && tile.footprint.height == 1)
    }

    @Test("Invalid directions, orientations, counts, and positions fail instead of producing totals")
    func invalidData() throws {
        let negative = [
            entity(
                "locomotive", 0, 0,
                [
                    "items": [
                        [
                            "id": ["name": "coal"],
                            "items": ["in_inventory": [["inventory": 1, "stack": 0, "count": -1]]],
                        ]
                    ]
                ])
        ]
        let cases: [[[String: Any]]] = [
            [entity("wooden-chest", 0.5, 0.5, ["direction": 16])],
            [entity("wooden-chest", 0.5, 0.5, ["direction": 1.5])],
            [entity("car", 0, 0, ["orientation": 1.5])],
            negative,
            [["entity_number": 1, "name": "wooden-chest"]],
        ]
        for entities in cases {
            #expect(throws: StatisticsError.self) { try stats(blueprint(entities)) }
        }
    }

    @Test("Robots are not blueprint-buildable and leave requirements incomplete")
    func robots() throws {
        let result = try stats(blueprint([entity("construction-robot", 0, 0)]))
        #expect(!result.requirementsComplete && result.footprint.complete)
        #expect(result.warnings.map(\.code) == ["NOT_BLUEPRINT_BUILDABLE"])
    }

    @Test("Identical warnings are grouped with counts in order of first occurrence")
    func groupedWarnings() throws {
        let result = try stats(
            blueprint(
                [
                    entity("fb-x"), entity("boiler", 0, 0, ["direction": 1]), entity("fb-y"), entity("fb-x"),
                    entity("wooden-chest", 0.5, 0.5, ["quality": "mythic"]), entity("fb-x"),
                    entity("locomotive", 0, 0, ["items": ["coal": 5]]),
                ], tiles: [["name": "fb-tile", "position": ["x": 0, "y": 0]]]))
        let summary = result.warnings.map { [$0.code, $0.name ?? $0.quality ?? "", String($0.count)] }
        #expect(
            summary == [
                ["UNKNOWN_ENTITY", "fb-x", "3"], ["UNMEASURED_GEOMETRY", "boiler", "1"],
                ["UNKNOWN_ENTITY", "fb-y", "1"],
                ["UNKNOWN_QUALITY", "mythic", "1"], ["LEGACY_ITEM_FORMAT", "locomotive", "1"],
                ["UNKNOWN_TILE", "fb-tile", "1"],
            ])
        #expect(result.warnings[1].direction == 1 && result.warnings[1].affects == "footprint")
        #expect(result.warnings[0].affects == "both" && result.warnings[0].direction == nil)
        #expect(!result.complete && !result.requirementsComplete && !result.footprint.complete)
    }

    @Test("Items sort by UTF-8 bytes of name, then quality")
    func byteOrder() throws {
        let result = try stats(
            blueprint([
                entity("wooden-chest", 0.5, 0.5, ["quality": "rare"]), entity("boiler", 3, 3, ["direction": 0]),
                entity("wooden-chest", 9.5, 9.5, ["quality": "epic"]), entity("car", -5, -5),
            ]))
        #expect(
            result.placement.map { "\($0.name)/\($0.quality)" } == [
                "boiler/normal", "car/normal", "wooden-chest/epic", "wooden-chest/rare",
            ])
    }

    @Test("Books and planners report not applicable with their kind and stored path")
    func notApplicable() throws {
        for kind in ["blueprint_book", "upgrade_planner", "deconstruction_planner"] {
            let entry = try blueprint(kind: kind, path: [5, 0])
            #expect(
                try BlueprintStatisticsCalculator.calculate(entry, map: statisticsMap)
                    == .notApplicable(NotApplicableStatistics(entryPath: [5, 0], entryKind: kind)))
        }
    }

    @Test("Rounding matches JavaScript Math.round: halves toward positive infinity")
    func rounding() {
        let round = BlueprintStatisticsCalculator.roundHalfUp
        #expect(round(2.5) == 3 && round(-2.5) == -2 && round(-0.5) == 0)
        #expect(round(0.49999999999999994) == 0 && round(-1.5000000000000002) == -2)
    }

    @Test("Results encode explicit nulls, knownBounds only when incomplete, and no prose")
    func encoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func json(_ result: StatisticsResult) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: encoder.encode(result)) as! [String: Any]
        }
        let incomplete = try json(
            BlueprintStatisticsCalculator.calculate(blueprint([entity("fb-x")]), map: statisticsMap))
        let footprint = incomplete["footprint"] as! [String: Any]
        #expect(footprint["bounds"] is NSNull && footprint["width"] is NSNull && footprint.keys.contains("knownBounds"))
        let warning = (incomplete["warnings"] as! [[String: Any]])[0]
        #expect(Set(warning.keys) == ["code", "name", "affects", "count"])
        #expect(incomplete["schemaVersion"] as? Int == 1 && incomplete["applicable"] as? Bool == true)
        #expect(incomplete["assetIdentity"] as? String == String(repeating: "b", count: 64))
        let complete = try json(
            BlueprintStatisticsCalculator.calculate(blueprint([entity("wooden-chest")]), map: statisticsMap))
        #expect(!(complete["footprint"] as! [String: Any]).keys.contains("knownBounds"))
        #expect(
            (complete["footprint"] as! [String: Any])["bounds"] as? [String: Double]
                == ["minX": 0, "minY": 0, "maxX": 1, "maxY": 1])
    }
}
