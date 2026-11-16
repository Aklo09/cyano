import FactorioData
import Foundation
import LibraryCore

/// Removes a test preferences domain and its file. `removePersistentDomain` only empties the domain, and the
/// preferences daemon later writes the empty `~/Library/Preferences/<suite>.plist` back, so every test run used to
/// leave files there; `defaults delete` removes the domain through the daemon.
func removeTestPreferences(_ suite: String) {
    UserDefaults().removePersistentDomain(forName: suite)
    let delete = Process()
    delete.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    delete.arguments = ["delete", suite]
    delete.standardOutput = FileHandle.nullDevice
    delete.standardError = FileHandle.nullDevice
    if (try? delete.run()) != nil { delete.waitUntilExit() }
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/\(suite).plist")
    try? FileManager.default.removeItem(at: file)
}

/// A minimal asset release that passes `AssetRelease.verify`, loads a one-entity prototype map, and lists one icon
/// whose atlas is deliberately not an image, so the icon catalog loads but cannot decode it
/// (adapted from `FactorioDataTests/AssetReleaseTests.swift` and `PrototypeMapTests.swift`; no private assets).
struct AppTestAssetRelease {
    let root: URL

    init(in parent: URL, name: String = "Release", mapLoads: Bool = true) throws {
        root = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sprites/fonts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("statistics"), withIntermediateDirectories: false)
        let version = FactorioProfile.initial.gameVersion
        let mods = FactorioProfile.initial.mods
        let atlas = Data("Deliberately not an image: inventory verification only".utf8)
        let font = Data("Test font bytes".utf8)
        let db = try Self.json([
            "schema": 2, "gameVersion": version, "mods": mods, "assetDensity": 2,
            "atlases": [["file": "atlas.webp", "width": 100, "height": 100]],
            "frames": [["a": 0, "x": 0, "y": 0, "w": 10, "h": 10, "ox": 0, "oy": 0, "sw": 10, "sh": 10]],
            "icons": ["item/wooden-chest": 0],
        ])
        func descriptor(_ file: String, _ data: Data) -> [String: Any] {
            ["file": file, "bytes": data.count, "sha256": OriginalSource(bytes: data).sha256]
        }
        var atlasDescriptor = descriptor("atlas.webp", atlas)
        atlasDescriptor["w"] = 100
        atlasDescriptor["h"] = 100
        let manifest = try Self.json([
            "schema": 2, "gameVersion": version, "mods": mods,
            "tiers": [
                "2x": ["density": 2, "renderDb": descriptor("render-db.json", db), "atlases": [atlasDescriptor]]
            ],
            "fonts": [descriptor("fonts/font.ttf", font)],
        ])
        // Without `mapLoads`, the map passes release verification but has no prototypes for statistics.
        let map: [String: Any] =
            mapLoads
            ? Self.prototypeMap
            : [
                "schema": 2, "gameVersion": version,
                "mods": Dictionary(uniqueKeysWithValues: mods.map { ($0, version) }),
            ]
        let members: [String: Data] = [
            "sprites/atlas.webp": atlas, "sprites/fonts/font.ttf": font, "sprites/render-db.json": db,
            "sprites/manifest.json": manifest, "statistics/prototype-map.json": try Self.json(map),
        ]
        let files: [[String: Any]] = members.keys.sorted().map { path in
            ["path": path, "bytes": members[path]!.count, "sha256": OriginalSource(bytes: members[path]!).sha256]
        }
        let profile: [String: Any] = ["gameVersion": version, "mods": mods.map { ["name": $0, "version": version] }]
        let provenance = ["assembly": "test-fixture"]
        let identity = OriginalSource(
            bytes: try Self.json(["schema": 1, "profile": profile, "provenance": provenance, "files": files])
        ).sha256
        for (path, data) in members { try data.write(to: root.appendingPathComponent(path)) }
        try Self.json([
            "schema": 1, "id": "test-release", "identity": identity, "profile": profile, "provenance": provenance,
            "files": files,
        ])
        .write(to: root.appendingPathComponent("release.json"))
    }

    /// One wooden chest, enough for statistics of a blueprint holding chests.
    static var prototypeMap: [String: Any] {
        let box: [Any] = [[-0.34765625, -0.34765625], [0.34765625, 0.34765625], 0]
        let shape: [String: Any] = [
            "direction": 0, "orientation": 0.0, "source": "entity", "tileWidth": 1, "tileHeight": 1,
            "collisionBox": box, "selectionBox": [[-0.5, -0.5], [0.5, 0.5], 0],
        ]
        return [
            "schema": 2, "gameVersion": FactorioProfile.initial.gameVersion,
            "mods": Dictionary(
                uniqueKeysWithValues: FactorioProfile.initial.mods.map { ($0, FactorioProfile.initial.gameVersion) }),
            "qualities": ["normal": true], "footprintDefinition": "Test map.",
            "entities": [
                "wooden-chest": [
                    "type": "container", "placement": [["name": "wooden-chest", "count": 1]], "tileWidth": 1,
                    "tileHeight": 1, "collisionBox": box, "selectionBox": [[-0.5, -0.5], [0.5, 0.5], 0],
                    "offGrid": false, "notBlueprintable": false, "supportsDirection": false,
                    "orientationAffectsCollision": false, "directions": ["0": shape],
                ]
            ],
            "tiles": [:] as [String: Any],
            "items": ["wooden-chest": ["type": "item", "subgroup": "storage", "order": "a[items]-a[wooden-chest]"]],
            "itemGroups": ["logistics": ["order": "a"]],
            "itemSubgroups": ["storage": ["group": "logistics", "order": "b"]],
            "equipmentItems": [:] as [String: Any],
        ]
    }

    static func json(_ value: Any) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(10)
        return data
    }
}
