import Foundation
import Testing

@testable import FactorioData
@testable import LibraryCore

private struct StatisticsLibrary {
    let parent: URL
    let library: URL
    let release: TestAssetRelease
    let blueprintId: String
    let bookId: String

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("fb-native-stats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        library = parent.appendingPathComponent("Library")
        release = try TestAssetRelease(prototypeMap: assetJSON(statisticsMapJSON()))
        func source(_ value: [String: Any]) throws -> Data {
            let compressed = try ZlibCodec.compress(JSONSerialization.data(withJSONObject: value), maximum: 1_000_000)
            return Data(("0" + compressed.base64EncodedString()).utf8)
        }
        func entity(_ name: String, _ number: Int) -> [String: Any] {
            ["entity_number": number, "name": name, "position": ["x": 0.5 + Double(number) * 2, "y": 0.5]]
        }
        let blueprint: [String: Any] = [
            "version": 1, "entities": [entity("wooden-chest", 1), entity("fb-unknown", 2), entity("fb-unknown", 3)],
        ]
        let book: [String: Any] = [
            "blueprint_book": [
                "version": 1,
                "blueprints": [
                    ["index": 5, "blueprint": ["version": 1, "entities": [entity("wooden-chest", 1)]]],
                    ["index": 9, "upgrade_planner": ["version": 1]],
                ],
            ]
        ]
        let owner = try NativeLibrary.initialize(at: library)
        defer { owner.close() }
        blueprintId = try owner.importSource(source(["blueprint": blueprint]), name: "Plain").id
        bookId = try owner.importSource(source(book), name: "Book").id
    }

    func cleanup() {
        release.cleanup()
        try? FileManager.default.removeItem(at: parent)
    }
}

private func cli(_ args: [String]) throws -> (status: Int32, json: [String: Any]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/fb-native")
    process.arguments = args
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let body = process.terminationStatus == 0 ? stdout : stderr
    let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    return (process.terminationStatus, json)
}

@Suite("Library statistics", .serialized)
struct LibraryStatisticsTests {
    @Test("The CLI reports a blueprint's statistics bound to the release identity, with grouped warnings")
    func blueprint() throws {
        let target = try StatisticsLibrary()
        defer { target.cleanup() }
        let response = try cli([
            "statistics", target.library.path, target.blueprintId, "--assets", target.release.root.path,
        ])
        #expect(response.status == 0)
        let result = try #require(response.json["result"] as? [String: Any])
        #expect(result["applicable"] as? Bool == true && result["complete"] as? Bool == false)
        #expect(result["assetIdentity"] as? String == (try AssetRelease.verify(at: target.release.root).identity))
        let warnings = try #require(result["warnings"] as? [[String: Any]])
        #expect(warnings.count == 1 && warnings[0]["code"] as? String == "UNKNOWN_ENTITY")
        #expect(warnings[0]["name"] as? String == "fb-unknown" && warnings[0]["count"] as? Int == 2)
        let items = try #require(result["constructionItems"] as? [[String: Any]])
        #expect(items.count == 1 && items[0]["name"] as? String == "wooden-chest")
    }

    @Test("Book leaves use stored indices; book roots and planners report not applicable")
    func bookEntries() throws {
        let target = try StatisticsLibrary()
        defer { target.cleanup() }
        let base = ["statistics", target.library.path, target.bookId, "--assets", target.release.root.path]
        let leaf = try #require(try cli(base + ["--entry", "5"]).json["result"] as? [String: Any])
        #expect(leaf["applicable"] as? Bool == true && leaf["complete"] as? Bool == true)
        #expect(leaf["entryPath"] as? [Int] == [5])
        for (extra, kind) in [([String](), "blueprint_book"), (["--entry", "9"], "upgrade_planner")] {
            let result = try #require(try cli(base + extra).json["result"] as? [String: Any])
            #expect(result["applicable"] as? Bool == false && result["entryKind"] as? String == kind)
            #expect(Set(result.keys) == ["schemaVersion", "applicable", "entryPath", "entryKind"])
        }
        #expect(try cli(base + ["--entry", "7"]).status == 7)
    }

    @Test("Missing or unsuitable assets give clear errors; source operations still need none")
    func assets() throws {
        let target = try StatisticsLibrary()
        defer { target.cleanup() }
        let missing = try cli(["statistics", target.library.path, target.blueprintId])
        #expect(missing.status == 2)
        #expect((missing.json["error"] as? [String: Any])?["code"] as? String == "ASSETS_REQUIRED")
        let thin = try TestAssetRelease()
        defer { thin.cleanup() }
        let unsuitable = try cli(["statistics", target.library.path, target.blueprintId, "--assets", thin.root.path])
        #expect(unsuitable.status == 7)
        #expect((unsuitable.json["error"] as? [String: Any])?["code"] as? String == "INVALID_PROTOTYPE_MAP")
        #expect(try cli(["list", target.library.path]).status == 0)
        #expect(
            try cli([
                "export", target.library.path, target.bookId, "--entry", "5", "--output",
                target.parent.appendingPathComponent("leaf.txt").path,
            ]).status == 0)
    }

    @Test("The library API reuses one loaded map and matches the CLI")
    func libraryAPI() throws {
        let target = try StatisticsLibrary()
        defer { target.cleanup() }
        let map = try PrototypeMap.load(release: target.release.root)
        let library = try NativeLibrary(at: target.library)
        defer { library.close() }
        guard case .applicable(let plain) = try library.statistics(id: target.blueprintId, map: map) else {
            Issue.record("expected an applicable result")
            return
        }
        #expect(plain.warnings.map(\.count) == [2] && plain.constructionItems.map(\.name) == ["wooden-chest"])
        #expect(
            try library.statistics(id: target.bookId, map: map)
                == .notApplicable(NotApplicableStatistics(entryPath: [], entryKind: "blueprint_book")))
        // The entry is a snapshot: deleting the item afterwards does not affect calculating from it.
        let entry = try library.entry(id: target.bookId, entryPath: [5])
        try library.deleteItem(id: target.bookId)
        guard case .applicable(let leaf) = try BlueprintStatisticsCalculator.calculate(entry, map: map) else {
            Issue.record("expected an applicable result for the snapshot leaf")
            return
        }
        #expect(leaf.entryPath == [5] && leaf.complete && leaf.constructionItems.map(\.name) == ["wooden-chest"])
    }
}
