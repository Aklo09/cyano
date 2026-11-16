import FactorioData
import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func encoded(_ json: String) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private let chest = #"{"entity_number":1,"name":"wooden-chest","position":{"x":0.5,"y":0.5}}"#

private func blueprint(_ label: String, entities: [String] = [], tiles: String = "") -> String {
    let list = entities.isEmpty ? "" : #","entities":["# + entities.joined(separator: ",") + "]"
    let tileList = tiles.isEmpty ? "" : #","tiles":"# + tiles
    return #"{"blueprint":{"item":"blueprint","label":"\#(label)""# + list + tileList + #","version":1}}"#
}

@MainActor
private final class StatisticsFixture {
    let parent: URL
    let url: URL
    let suite: String
    let session = LibrarySession()
    let assets: AssetSettings
    let model: StatisticsModel
    let browser: LibraryBrowserModel
    var ids: [String: String] = [:]

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-statistics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        let sources: [(String, String)] = [
            ("Chest", blueprint("Chest", entities: [chest])),
            ("Empty", blueprint("Empty")),
            (
                "Unknown",
                blueprint(
                    "Unknown",
                    entities: [
                        chest,
                        #"{"entity_number":2,"name":"ee-infinity-loader","position":{"x":4.5,"y":0.5}}"#,
                        #"{"entity_number":3,"name":"ee-infinity-loader","position":{"x":6.5,"y":0.5}}"#,
                        #"{"entity_number":4,"name":"wooden-chest","position":{"x":2.5,"y":0.5},"quality":"mythic"}"#,
                    ])
            ),
            (
                "OnlyUnknown",
                blueprint("OnlyUnknown", entities: [#"{"entity_number":1,"name":"x","position":{"x":0,"y":0}}"#])
            ),
            (
                "Invalid",
                blueprint(
                    "Invalid",
                    entities: [
                        #"{"entity_number":1,"name":"wooden-chest","position":{"x":0.5,"y":0.5},"direction":99}"#
                    ])
            ),
            (
                "Book",
                #"{"blueprint_book":{"item":"blueprint-book","label":"Book","version":1,"blueprints":[{"index":2,"blueprint":"#
                    + String(blueprint("Inner", entities: [chest, chest]).dropFirst(13).dropLast()) + "}]}}"
            ),
            (
                "Planner",
                #"{"upgrade_planner":{"item":"upgrade-planner","label":"Planner","settings":{},"version":1}}"#
            ),
        ]
        for (name, json) in sources { ids[name] = try library.importSource(encoded(json)).id }
        suite = "local.fb.library.tests-\(UUID().uuidString)"
        assets = AssetSettings(defaults: try #require(UserDefaults(suiteName: suite)))
        model = StatisticsModel(session: session, assets: assets)
        browser = LibraryBrowserModel(session: session)
    }

    func target(_ name: String, _ entryPath: [Int] = [], kind: ItemKind = .blueprint) -> StatisticsTarget {
        StatisticsTarget(itemId: ids[name]!, entryPath: entryPath, kind: kind, sourceSha256: "")
    }

    func ready(_ name: String) async -> StatisticsPresentation? {
        await model.show(target(name))
        guard case .ready(let statistics, let inventory) = model.state else {
            Issue.record("\(name): \(model.state)")
            return nil
        }
        return StatisticsPresentation(statistics, inventory: inventory)
    }

    func cleanup() {
        removeTestPreferences(suite)
        try? FileManager.default.removeItem(at: parent)
    }
}

@MainActor
@Suite("Statistics", .serialized)
struct StatisticsModelTests {
    @Test("STA-4, STA-5: no release asks for one; books and planners are not applicable")
    func gating() async throws {
        let fixture = try StatisticsFixture()
        defer { fixture.cleanup() }
        await fixture.session.open(fixture.url)
        await fixture.model.show(fixture.target("Chest"))
        #expect(fixture.model.state == .noAssets)
        await fixture.model.show(fixture.target("Book", kind: .book))
        #expect(fixture.model.state == .notApplicable(.book))
        await fixture.model.show(fixture.target("Planner", kind: .upgradePlanner))
        #expect(fixture.model.state == .notApplicable(.upgradePlanner))
        await fixture.model.show(nil)
        #expect(fixture.model.state == .none)
        await fixture.session.close()
    }

    @Test("STA-1, SET-5: counts, groups, and footprint; the prototype map loads once for several entries")
    func results() async throws {
        let fixture = try StatisticsFixture()
        defer { fixture.cleanup() }
        await fixture.assets.choose(try AppTestAssetRelease(in: fixture.parent).root, library: fixture.url)
        await fixture.session.open(fixture.url)
        let chest = try #require(await fixture.ready("Chest"))
        #expect(chest.entities == 1 && chest.tiles == 0 && chest.requirementsComplete)
        #expect(chest.footprint == .complete(width: 1, height: 1))
        #expect(chest.groups.map(\.title) == ["Logistics"])
        #expect(
            chest.groups[0].rows.map { [$0.name, $0.quality ?? "", String($0.count)] } == [["wooden-chest", "", "1"]])
        #expect(chest.warnings.isEmpty && !chest.isEmpty)

        let empty = try #require(await fixture.ready("Empty"))
        #expect(empty.isEmpty && empty.footprint == .complete(width: 0, height: 0) && empty.groups.isEmpty)

        // A book entry, reached through the browser by its stored index.
        fixture.browser.listingChanged()
        fixture.browser.selection = ["item:" + fixture.ids["Book"]!]
        #expect(fixture.browser.statisticsTarget?.kind == .book)
        await fixture.browser.openSelection()
        #expect(fixture.browser.statisticsTarget?.kind == .book)
        fixture.browser.selection = ["entry:2"]
        let target = try #require(fixture.browser.statisticsTarget)
        #expect(target.entryPath == [2] && target.kind == .blueprint)
        await fixture.model.show(target)
        guard case .ready(let inner, let inventory) = fixture.model.state else {
            Issue.record("\(fixture.model.state)")
            return
        }
        #expect(StatisticsPresentation(inner, inventory: inventory).groups.first?.rows.first?.count == 2)
        #expect(fixture.assets.mapLoads == 1)
        await fixture.session.close()
    }

    @Test("STA-3: warnings are worded once with their count; incomplete parts are marked with known bounds")
    func warnings() async throws {
        let fixture = try StatisticsFixture()
        defer { fixture.cleanup() }
        await fixture.assets.choose(try AppTestAssetRelease(in: fixture.parent).root, library: fixture.url)
        await fixture.session.open(fixture.url)
        let unknown = try #require(await fixture.ready("Unknown"))
        #expect(!unknown.requirementsComplete)
        #expect(unknown.footprint == .incomplete(atLeastWidth: 3, height: 1))
        #expect(
            unknown.warnings.map { "\($0.count) × \($0.text)" } == [
                "2 × ee-infinity-loader: not in the game data; requirements and footprint are incomplete.",
                "1 × quality mythic: not in the game data; requirements are incomplete.",
            ])
        let only = try #require(await fixture.ready("OnlyUnknown"))
        #expect(only.footprint == .unknown)
        for warning in unknown.warnings + only.warnings { #expect(!warning.text.contains("UNKNOWN")) }

        await fixture.model.show(fixture.target("Invalid"))
        guard case .failed(let message) = fixture.model.state else {
            Issue.record("\(fixture.model.state)")
            return
        }
        #expect(message.title == "Statistics can't be calculated for this blueprint")
        #expect(message.code == "STATISTICS_INVALID_INPUT")
        await fixture.session.close()
    }

    @Test("STA-6: a release whose prototype map is unsuitable says it can't provide statistics")
    func unsuitableMap() async throws {
        let fixture = try StatisticsFixture()
        defer { fixture.cleanup() }
        await fixture.assets.choose(
            try AppTestAssetRelease(in: fixture.parent, mapLoads: false).root, library: fixture.url)
        await fixture.session.open(fixture.url)
        await fixture.model.show(fixture.target("Chest"))
        guard case .mapUnsuitable(let message) = fixture.model.state else {
            Issue.record("\(fixture.model.state)")
            return
        }
        #expect(message.title == "The selected asset release can't provide statistics")
        await fixture.session.close()
    }

    @Test("STA-1: construction items appear once, by inventory tab in the game's order")
    func inventoryTabs() throws {
        var map = AppTestAssetRelease.prototypeMap
        map["qualities"] = ["normal": true, "rare": true]
        var items = map["items"] as! [String: Any]
        items["speed-module"] = ["type": "module", "subgroup": "module", "order": "a[speed]-a[speed-module-1]"]
        items["coal"] = ["type": "item", "subgroup": "raw-resource", "order": "b[coal]"]
        map["items"] = items
        map["itemGroups"] = [
            "logistics": ["order": "a"], "production": ["order": "b"], "intermediate-products": ["order": "c"],
        ]
        map["itemSubgroups"] = [
            "storage": ["group": "logistics", "order": "b"], "module": ["group": "production", "order": "g"],
            "raw-resource": ["group": "intermediate-products", "order": "b"],
        ]
        let prototypes = try PrototypeMap.parse(
            AppTestAssetRelease.json(map), assetIdentity: String(repeating: "0", count: 64))
        let coal = #"{"id":{"name":"coal"},"items":{"in_inventory":[{"inventory":1,"stack":0,"count":5}]}}"#
        let module = #"{"id":{"name":"speed-module"},"items":{"in_inventory":[{"inventory":1,"stack":0,"count":2}]}}"#
        let statistics = try BlueprintStatisticsCalculator.calculate(
            BlueprintCodec.decode(
                encoded(
                    blueprint(
                        "Tabs",
                        entities: [
                            #"{"entity_number":1,"name":"wooden-chest","position":{"x":0.5,"y":0.5},"items":[\#(coal)]}"#,
                            #"{"entity_number":2,"name":"wooden-chest","position":{"x":2.5,"y":0.5},"quality":"rare","#
                                + #""items":[\#(module)]}"#,
                        ]))
            ).root, map: prototypes)
        guard case .applicable(let result) = statistics else {
            Issue.record("not applicable")
            return
        }
        let presentation = StatisticsPresentation(result, inventory: prototypes.inventory)
        #expect(presentation.groups.map(\.title) == ["Logistics", "Production", "Intermediate products"])
        #expect(
            presentation.groups.map { $0.rows.map { "\($0.name)|\($0.quality ?? "")|\($0.count)" } } == [
                ["wooden-chest||1", "wooden-chest|rare|1"], ["speed-module||2"], ["coal||5"],
            ])
        #expect(StatisticsPresentation.title(tab: "some-new-tab") == "Some new tab")
    }

    @Test("Statistics rows copy as text: name, quality when not normal, and count")
    func copying() throws {
        let statistics = try BlueprintStatisticsCalculator.calculate(
            BlueprintCodec.decode(
                encoded(
                    blueprint(
                        "Copy",
                        entities: [
                            chest,
                            #"{"entity_number":2,"name":"wooden-chest","position":{"x":2.5,"y":0.5},"quality":"rare"}"#,
                        ]))
            ).root,
            map: PrototypeMap.parse(
                AppTestAssetRelease.json(
                    AppTestAssetRelease.prototypeMap.merging(["qualities": ["normal": true, "rare": true]]) { $1 }),
                assetIdentity: String(repeating: "0", count: 64)))
        guard case .applicable(let result) = statistics else {
            Issue.record("not applicable")
            return
        }
        let presentation = StatisticsPresentation(
            result,
            inventory: ItemInventory(positions: [
                "wooden-chest": InventoryPosition(
                    group: "logistics", groupOrder: "a", subgroup: "storage", subgroupOrder: "b", order: "a")
            ]))
        let placement = try #require(presentation.groups.first { $0.id == "tab:logistics" })
        #expect(placement.rows.map(\.quality) == [nil, "rare"])
        #expect(presentation.copyText(rows: Set(placement.rows.map(\.id))) == "wooden-chest\t1\nwooden-chest\trare\t1")
        #expect(presentation.copyText(rows: []) == "")
    }
}

// MARK: - Parity with the CLI for the seven approved blueprints (STA-2)

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
private let privateRelease = repository.appendingPathComponent(".cache/renderer-assets")
private let cli = repository.appendingPathComponent(".build/debug/fb-native")

/// Runs the CLI and returns its standard output.
private func runCLI(_ arguments: [String]) throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = cli
    process.arguments = arguments
    process.standardOutput = output
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return bytes
}

private func cliResult(_ bytes: Data) throws -> [String: Any] {
    let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    return try #require(json["result"] as? [String: Any])
}

@MainActor
@Suite("Statistics parity with the CLI")
struct StatisticsParityAppTests {
    @Test(
        "STA-2: the tab shows every count, footprint, completeness flag, and warning that fb-native statistics reports",
        .enabled(
            if: FileManager.default.fileExists(atPath: privateRelease.appendingPathComponent("release.json").path),
            "Needs the private release in .cache/renderer-assets"))
    func sevenBlueprints() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-statistics-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appendingPathComponent("Library")
        let fixtures = repository.appendingPathComponent("Tests/LibraryCoreTests/Fixtures/Blueprints")
        let cases: [(URL, [Int])] = [
            (fixtures.appendingPathComponent("RS.txt"), []),
            (fixtures.appendingPathComponent("4x_Rocket_Silo.txt"), []),
            (fixtures.appendingPathComponent("Hazard_Patterns.txt"), []),
            (fixtures.appendingPathComponent("bp.txt"), [0, 0]),
            (fixtures.appendingPathComponent("bp.txt"), [1, 1]),
            (fixtures.appendingPathComponent("v0.59.0.txt"), [1, 1]),
            (
                repository.appendingPathComponent(
                    "tools/vendor/fpsr/fixtures/visual-tests/official-mods/elevated-rails.bp.txt"), [0]
            ),
        ]
        var ids: [URL: String] = [:]
        do {
            let library = try NativeLibrary.initialize(at: url)
            defer { library.close() }
            for (file, _) in cases where ids[file] == nil {
                ids[file] = try library.importSource(Data(contentsOf: file)).id
            }
        }
        // The CLI needs the lease, so it runs before the app session opens the library.
        let runs: [[String]] = cases.map { file, path in
            ["statistics", url.path, ids[file]!, "--assets", privateRelease.path]
                + (path.isEmpty ? [] : ["--entry", path.map(String.init).joined(separator: ".")])
        }
        // Off the main actor, so the other @MainActor suites are not blocked while the CLI loads the map.
        let outputs = try await Task.detached { try runs.map { try runCLI($0) } }.value
        let expected = try outputs.map(cliResult)

        let suite = "local.fb.library.tests-\(UUID().uuidString)"
        defer { removeTestPreferences(suite) }
        let assets = AssetSettings(defaults: try #require(UserDefaults(suiteName: suite)))
        await assets.choose(privateRelease, library: url)
        let session = LibrarySession()
        await session.open(url)
        let model = StatisticsModel(session: session, assets: assets)
        for ((file, path), cliResult) in zip(cases, expected) {
            let label = "\(file.lastPathComponent) \(path)"
            await model.show(StatisticsTarget(itemId: ids[file]!, entryPath: path, kind: .blueprint, sourceSha256: ""))
            guard case .ready(let statistics, let inventory) = model.state else {
                Issue.record("\(label): \(model.state)")
                continue
            }
            let shown = StatisticsPresentation(statistics, inventory: inventory)
            #expect(shown.entities == cliResult["entities"] as? Int, "\(label) entities")
            #expect(shown.tiles == cliResult["tiles"] as? Int, "\(label) tiles")
            #expect(shown.requirementsComplete == cliResult["requirementsComplete"] as? Bool, "\(label) requirements")
            let footprint = try #require(cliResult["footprint"] as? [String: Any])
            if footprint["complete"] as? Bool == true {
                #expect(
                    shown.footprint
                        == .complete(
                            width: (footprint["width"] as? NSNumber)?.doubleValue ?? -1,
                            height: (footprint["height"] as? NSNumber)?.doubleValue ?? -1), "\(label) footprint")
            } else if let known = footprint["knownBounds"] as? [String: NSNumber] {
                #expect(
                    shown.footprint
                        == .incomplete(
                            atLeastWidth: known["maxX"]!.doubleValue - known["minX"]!.doubleValue,
                            height: known["maxY"]!.doubleValue - known["minY"]!.doubleValue), "\(label) known bounds")
            } else {
                #expect(shown.footprint == .unknown, "\(label) footprint")
            }
            func items(_ key: String) -> [String] {
                (cliResult[key] as? [[String: Any]] ?? []).map {
                    "\($0["name"]!)|\(($0["quality"] as? String) == "normal" ? "" : $0["quality"]!)|\($0["count"]!)"
                }
            }
            func rows(_ groups: [StatisticsPresentation.Group]) -> [String] {
                groups.flatMap(\.rows).map { "\($0.name)|\($0.quality ?? "")|\($0.count)" }
            }
            // The tabs together list exactly the construction items, each once, every item under its own tab.
            let tabs = shown.groups.filter { $0.id.hasPrefix("tab:") }
            #expect(rows(tabs).sorted() == items("constructionItems").sorted(), "\(label) constructionItems")
            #expect(Set(tabs.map(\.id)).count == tabs.count, "\(label) tabs")
            for tab in tabs {
                #expect(
                    tab.rows.allSatisfy { "tab:" + (inventory.positions[$0.name]?.group ?? "") == tab.id },
                    "\(label) \(tab.id)")
            }
            #expect(
                rows(shown.groups.filter { $0.id == "requests" }) == items("equipmentRequests"), "\(label) requests")
            #expect(shown.groups.count == tabs.count + (items("equipmentRequests").isEmpty ? 0 : 1), "\(label) groups")
            let warnings = (cliResult["warnings"] as? [[String: Any]] ?? []).map { $0["count"] as? Int ?? -1 }
            #expect(shown.warnings.map(\.count) == warnings, "\(label) warnings")
        }
        await session.close()
    }
}
