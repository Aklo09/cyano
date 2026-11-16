import Foundation
import LibraryCore
import Testing

@testable import FactorioData

/// A small hand-written map covering every shape the statistics calculator reads. Values are dyadic, so exact.
func syntheticPrototypeMap() -> [String: Any] {
    let chestBox: [Any] = [[-0.34765625, -0.34765625], [0.34765625, 0.34765625], 0]
    func shape(_ direction: Int, width: Int = 1, height: Int = 1, box: [Any] = chestBox) -> [String: Any] {
        [
            "direction": direction, "orientation": Double(direction) / 16, "source": "entity", "tileWidth": width,
            "tileHeight": height, "collisionBox": box, "selectionBox": [[-0.5, -0.5], [0.5, 0.5], 0],
        ]
    }
    func entity(
        _ type: String, placement: String, count: Int = 1, offGrid: Bool = false, rotates: Bool = false,
        directions: [String: Any]
    ) -> [String: Any] {
        [
            "type": type, "placement": [["name": placement, "count": count]], "tileWidth": 1, "tileHeight": 1,
            "collisionBox": chestBox, "selectionBox": [[-0.5, -0.5], [0.5, 0.5], 0], "offGrid": offGrid,
            "notBlueprintable": false, "supportsDirection": !directions.isEmpty, "orientationAffectsCollision": rotates,
            "directions": directions,
        ]
    }
    func item(_ type: String, _ subgroup: String, _ order: String, places equipment: String? = nil) -> [String: Any] {
        var item: [String: Any] = ["type": type, "subgroup": subgroup, "order": order]
        item["equipment"] = equipment
        return item
    }
    var rail = shape(0, width: 4, height: 4, box: [[-1.5, -2.5], [1.5, 2.5], 0])
    rail["secondaryCollisionBox"] = [[-2, -1], [2, 1], 0.125]
    return [
        "schema": 2, "gameVersion": "2.1.24",
        "mods": Dictionary(uniqueKeysWithValues: FactorioProfile.initial.mods.map { ($0, "2.1.24") }),
        "qualities": ["normal": true, "rare": true],
        "footprintDefinition": "Synthetic test map.",
        "entities": [
            "wooden-chest": entity(
                "container", placement: "wooden-chest",
                directions: Dictionary(uniqueKeysWithValues: (0...15).map { (String($0), shape($0)) })),
            "boiler": entity(
                "boiler", placement: "boiler",
                directions: ["0": shape(0, width: 3, height: 2), "4": shape(4, width: 2, height: 3)]),
            "car": entity("car", placement: "car", offGrid: true, rotates: true, directions: ["0": shape(0)]),
            "legacy-curved-rail": entity(
                "legacy-curved-rail", placement: "rail", count: 4, directions: ["0": rail]),
        ],
        "tiles": ["concrete": ["placement": [["name": "concrete", "count": 1]]]],
        "items": [
            "wooden-chest": item("item", "storage", "a[items]-a[wooden-chest]"),
            "boiler": item("item", "energy", "b[steam-power]-a[boiler]"),
            "car": item("item-with-entity-data", "transport", "b[personal-transport]-a[car]"),
            "rail": item("rail-planner", "train-transport", "a[rail]-a[rail]"),
            "concrete": item("item", "terrain", "b[concrete]-a[plain]"),
            "speed-module": item("module", "module", "a[speed]-a[speed-module-1]"),
            "battery-equipment": item(
                "item", "equipment", "b[battery]-a[battery-equipment]", places: "battery-equipment"),
        ],
        "itemGroups": ["logistics": ["order": "a"], "production": ["order": "b"], "combat": ["order": "e"]],
        "itemSubgroups": [
            "storage": ["group": "logistics", "order": "b"], "train-transport": ["group": "logistics", "order": "e"],
            "transport": ["group": "logistics", "order": "f"], "terrain": ["group": "logistics", "order": "h"],
            "energy": ["group": "production", "order": "b"], "module": ["group": "production", "order": "g"],
            "equipment": ["group": "combat", "order": "d"],
        ],
        "equipmentItems": ["battery-equipment": ["battery-equipment"]],
    ]
}

private let identity = String(repeating: "a", count: 64)
private func parse(_ value: [String: Any]) throws -> PrototypeMap {
    try PrototypeMap.parse(assetJSON(value), assetIdentity: identity)
}

@Suite("Prototype map loading")
struct PrototypeMapTests {
    @Test("A complete map parses with exact geometry, partial direction sets, and resolved references")
    func parsesSyntheticMap() throws {
        let map = try parse(syntheticPrototypeMap())
        #expect(map.assetIdentity == identity && map.gameVersion == "2.1.24")
        #expect(map.qualities == ["normal", "rare"])
        #expect(map.entities.count == 4 && map.tiles["concrete"] == [ItemCount(name: "concrete", count: 1)])
        let chest = try #require(map.entities["wooden-chest"])
        #expect(chest.directions.count == 16 && chest.placement == [ItemCount(name: "wooden-chest", count: 1)])
        #expect(
            chest.directions[0]?.collisionBox
                == CollisionBox(
                    left: -0.34765625, top: -0.34765625, right: 0.34765625, bottom: 0.34765625, orientation: 0))
        let boiler = try #require(map.entities["boiler"])
        #expect(boiler.directions.keys.sorted() == [0, 4])
        #expect(boiler.directions[4]?.tileWidth == 2 && boiler.directions[4]?.tileHeight == 3)
        let car = try #require(map.entities["car"])
        #expect(car.offGrid && car.orientationAffectsCollision)
        let rail = try #require(map.entities["legacy-curved-rail"]?.directions[0])
        #expect(rail.secondaryCollisionBox?.orientation == 0.125)
        #expect(
            map.items["speed-module"] == "module" && map.equipmentItems["battery-equipment"] == ["battery-equipment"])
        #expect(
            map.inventory.positions["speed-module"]
                == InventoryPosition(
                    group: "production", groupOrder: "b", subgroup: "module", subgroupOrder: "g",
                    order: "a[speed]-a[speed-module-1]"))
    }

    @Test("Items sort as in the game's inventory: tab, row, and order; unknown items last")
    func inventoryOrder() throws {
        let inventory = try parse(syntheticPrototypeMap()).inventory
        let names = [
            "unknown-b", "battery-equipment", "speed-module", "unknown-a", "concrete", "car", "boiler", "rail",
            "wooden-chest",
        ]
        #expect(
            names.sorted(by: inventory.precedes) == [
                "wooden-chest", "rail", "car", "concrete", "boiler", "speed-module", "battery-equipment", "unknown-a",
                "unknown-b",
            ])
        // Ties on order strings fall back to names, as the game does.
        let tied = ItemInventory(positions: [
            "b": InventoryPosition(group: "g", groupOrder: "a", subgroup: "s", subgroupOrder: "a", order: ""),
            "a": InventoryPosition(group: "g", groupOrder: "a", subgroup: "s", subgroupOrder: "a", order: ""),
        ])
        #expect(["b", "a"].sorted(by: tied.precedes) == ["a", "b"])
    }

    @Test("Loading from a verified release binds the map to the release identity")
    func loadsFromRelease() throws {
        let release = try TestAssetRelease(prototypeMap: assetJSON(syntheticPrototypeMap()))
        defer { release.cleanup() }
        let map = try PrototypeMap.load(release: release.root)
        #expect(map.assetIdentity == (try AssetRelease.verify(at: release.root).identity))
        #expect(map.entities.count == 4)
    }

    @Test("A release map sufficient for asset verification is refused for statistics")
    func minimalReleaseMap() throws {
        let release = try TestAssetRelease()
        defer { release.cleanup() }
        _ = try AssetRelease.verify(at: release.root)
        #expect(throws: PrototypeMapError.self) { try PrototypeMap.load(release: release.root) }
    }

    @Test("Malformed, unknown, inconsistent, and oversized maps are refused")
    func refusals() throws {
        func entities(_ edit: (inout [String: Any]) -> Void) -> [String: Any] {
            var map = syntheticPrototypeMap()
            var all = map["entities"] as! [String: Any]
            var chest = all["wooden-chest"] as! [String: Any]
            edit(&chest)
            all["wooden-chest"] = chest
            map["entities"] = all
            return map
        }
        func direction(_ edit: (inout [String: Any]) -> Void) -> [String: Any] {
            entities { chest in
                var directions = chest["directions"] as! [String: Any]
                var zero = directions["0"] as! [String: Any]
                edit(&zero)
                directions["0"] = zero
                chest["directions"] = directions
            }
        }
        var cases: [(String, [String: Any])] = []
        func root(_ name: String, _ edit: (inout [String: Any]) -> Void) {
            var map = syntheticPrototypeMap()
            edit(&map)
            cases.append((name, map))
        }
        root("schema 1") { $0["schema"] = 1 }
        func item(_ name: String, _ edit: (inout [String: Any]) -> Void) {
            root(name) { map in
                var items = map["items"] as! [String: Any]
                var chest = items["wooden-chest"] as! [String: Any]
                edit(&chest)
                items["wooden-chest"] = chest
                map["items"] = items
            }
        }
        item("item without subgroup") { $0["subgroup"] = nil }
        item("item without order") { $0["order"] = nil }
        item("item order not text") { $0["order"] = 1 }
        item("item in unknown subgroup") { $0["subgroup"] = "missing" }
        root("missing itemGroups") { $0["itemGroups"] = nil }
        root("subgroup in unknown group") {
            var subgroups = $0["itemSubgroups"] as! [String: Any]
            subgroups["storage"] = ["group": "missing", "order": "b"]
            $0["itemSubgroups"] = subgroups
        }
        root("unknown item group field") { $0["itemGroups"] = ["logistics": ["order": "a", "extra": 1]] }
        root("missing gameVersion") { $0["gameVersion"] = nil }
        root("unknown root field") { $0["extra"] = true }
        root("qualities without normal") { $0["qualities"] = ["rare": true] }
        root("quality not true") { $0["qualities"] = ["normal": false] }
        root("tile places unknown item") {
            $0["tiles"] = ["concrete": ["placement": [["name": "missing", "count": 1]]]]
        }
        root("equipment list mismatch") { $0["equipmentItems"] = ["battery-equipment": ["concrete"]] }
        cases.append(("unknown entity field", entities { $0["extra"] = 1 }))
        cases.append(("placement count 0", entities { $0["placement"] = [["name": "wooden-chest", "count": 0]] }))
        cases.append(("placement unknown item", entities { $0["placement"] = [["name": "missing", "count": 1]] }))
        cases.append(("non-canonical direction key", entities { $0["directions"] = ["04": ["direction": 4]] }))
        cases.append(("unknown direction field", direction { $0["extra"] = 1 }))
        cases.append(("resolved direction out of range", direction { $0["direction"] = 16 }))
        cases.append(("inverted box", direction { $0["collisionBox"] = [[1, 1], [0, 0], 0] }))
        cases.append(("non-numeric box", direction { $0["collisionBox"] = [["x", 0], [1, 1], 0] }))
        cases.append(("orientation 1", direction { $0["orientation"] = 1 }))
        cases.append(("unknown source", direction { $0["source"] = "sprite" }))
        for (name, map) in cases {
            #expect(throws: PrototypeMapError.self, "\(name)") { try parse(map) }
        }
        #expect(throws: PrototypeMapError.self) {
            try PrototypeMap.parse(Data("{\"schema\":".utf8), assetIdentity: identity)
        }
        let oversized = Data(repeating: 32, count: PrototypeMap.maximumBytes + 1)
        #expect(throws: PrototypeMapError.invalid("larger than 16 MiB")) {
            try PrototypeMap.parse(oversized, assetIdentity: identity)
        }
    }

    static let privateMapURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("private-assets/statistics-reference/prototype-map.json")

    @Test(
        "The private 2.1.24 map parses with its documented contents",
        .enabled(if: FileManager.default.fileExists(atPath: privateMapURL.path), "Needs the private prototype map"))
    func privateMap() throws {
        let map = try PrototypeMap.parse(Data(contentsOf: Self.privateMapURL), assetIdentity: identity)
        #expect(map.gameVersion == "2.1.24")
        #expect(
            map.entities.count == 146 && map.items.count == 342 && map.tiles.count == 23 && map.qualities.count == 6)
        #expect(
            map.entities.values.filter { $0.directions.values.contains { $0.secondaryCollisionBox != nil } }.count == 1)
        // The assembled development release, when present, loads through verification and identity binding.
        let release = Self.privateMapURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".cache/renderer-assets")
        if FileManager.default.fileExists(atPath: release.path) {
            let loaded = try PrototypeMap.load(release: release)
            #expect(loaded.assetIdentity == (try AssetRelease.verify(at: release).identity))
            #expect(loaded.entities == map.entities)
        }
    }
}
