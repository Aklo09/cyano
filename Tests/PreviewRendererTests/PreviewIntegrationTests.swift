import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LibraryCore
@testable import PreviewRenderer

private func previewJSON(_ value: Any) throws -> Data {
    var bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    bytes.append(10)
    return bytes
}
struct SyntheticPreviewAssets {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-render-assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sprites"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("statistics"), withIntermediateDirectories: false)
        let mods = ["base", "elevated-rails", "quality", "recycler", "space-age"]
        let bitmap = try makeBitmap(width: 32, height: 32)
        bitmap.setFillColor(CGColor(srgbRed: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let png = NSMutableData()
        let image = try #require(bitmap.makeImage())
        let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let frame: [String: Any] = ["a": 0, "x": 0, "y": 0, "w": 32, "h": 32, "ox": 0, "oy": 0, "sw": 32, "sh": 32]
        let entity: [String: Any] = [
            "kind": "simple", "protoType": "container", "collisionBox": [[-0.5, -0.5], [0.5, 0.5]],
            "selectionBox": [[-0.5, -0.5], [0.5, 0.5]],
            "graphics": [
                [
                    "layer": "object", "indexing": "single",
                    "variants": ["default": [["frame": 0, "scale": 1, "shift": [0, 0]]]],
                ]
            ],
        ]
        let database = try previewJSON([
            "schema": 2, "gameVersion": "2.1.23", "mods": mods, "assetDensity": 2,
            "atlases": [["file": "atlas.png", "width": 32, "height": 32]], "frames": [frame],
            "entities": ["wooden-chest": entity],
            "tiles": [:], "icons": [:], "fluidRecipes": [:], "iconScales": [:],
        ])
        func descriptor(_ file: String, _ data: Data) -> [String: Any] {
            ["file": file, "bytes": data.count, "sha256": OriginalSource(bytes: data).sha256]
        }
        var atlas = descriptor("atlas.png", png as Data)
        atlas["w"] = 32
        atlas["h"] = 32
        let manifest = try previewJSON([
            "schema": 2, "gameVersion": "2.1.23", "mods": mods,
            "tiers": ["2x": ["density": 2, "renderDb": descriptor("render-db.json", database), "atlases": [atlas]]],
            "fonts": [],
        ])
        let map = try previewJSON([
            "schema": 1, "gameVersion": "2.1.23", "mods": Dictionary(uniqueKeysWithValues: mods.map { ($0, "2.1.23") }),
        ])
        let members = [
            "sprites/manifest.json": manifest, "sprites/render-db.json": database, "sprites/atlas.png": png as Data,
            "statistics/prototype-map.json": map,
        ]
        let files = members.keys.sorted().map {
            ["path": $0, "bytes": members[$0]!.count, "sha256": OriginalSource(bytes: members[$0]!).sha256]
                as [String: Any]
        }
        let profile: [String: Any] = ["gameVersion": "2.1.23", "mods": mods.map { ["name": $0, "version": "2.1.23"] }]
        let identity: [String: Any] = [
            "schema": 1, "profile": profile, "provenance": ["source": "synthetic-native-test"], "files": files,
        ]
        var release = identity
        release["id"] = "synthetic"
        release["identity"] = OriginalSource(bytes: try previewJSON(identity)).sha256
        for (path, data) in members { try data.write(to: root.appendingPathComponent(path)) }
        try previewJSON(release).write(to: root.appendingPathComponent("release.json"))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
func renderSource(name: String = "wooden-chest") throws -> Data {
    let json = Data(
        "{\"blueprint\":{\"version\":562954249895936,\"entities\":[{\"entity_number\":1,\"name\":\"\(name)\",\"position\":{\"x\":0,\"y\":0}}]}}"
            .utf8)
    return Data(("0" + (try ZlibCodec.compress(json, maximum: 1_000_000)).base64EncodedString()).utf8)
}
private func integrationWorker() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/debug/preview-worker")
}

@Suite("Complete native preview jobs", .serialized)
struct PreviewIntegrationTests {
    @Test("Asset changes between release verification and renderer loading are refused")
    func assetSnapshot() throws {
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let manifest = assets.root.appendingPathComponent("sprites/manifest.json")
        #expect(throws: PreviewError.assetDecode) {
            try RenderAssets(path: assets.root.path, tier: "2x") {
                var bytes = try Data(contentsOf: manifest)
                bytes.append(32)  // Still valid JSON; exact release identity must nevertheless match.
                try bytes.write(to: manifest)
            }
        }
    }
    @Test("A real worker loads generated assets, plans, paints, encodes, and returns a validated nonempty PNG")
    func completeJob() throws {
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let before = try Data(contentsOf: assets.root.appendingPathComponent("release.json"))
        let request = PreviewRequest(source: try renderSource(), assetsPath: assets.root.path, maximumDimension: 128)
        let owner = PreviewProcess(workerURL: integrationWorker())
        let result = try owner.render(request)
        #expect(result.report.commandKinds["sprite"] == 1)
        #expect(result.report.warnings.isEmpty)
        #expect(result.report.atlasDecodes == 1)
        #expect(result.report.peakResidentBytes > 0 && result.report.peakResidentBytes < 1_073_741_824)
        #expect(result.report.timingsMs["supervisorWall"]! < 60_000)
        let imageSource = try #require(CGImageSourceCreateWithData(result.png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let bitmap = try makeBitmap(width: image.width, height: image.height)
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(bitmap.data?.assumingMemoryBound(to: UInt8.self))
        #expect((0..<(image.width * image.height)).contains { data[$0 * 4 + 3] > 0 })
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-preview-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        try PreviewProcess.writeNew(result, to: output, protecting: assets.root)
        #expect(try Data(contentsOf: output) == result.png)
        #expect(throws: NativeLibraryError.self) {
            try PreviewProcess.writeNew(result, to: output, protecting: assets.root)
        }
        #expect(throws: PreviewError.invalidInput) {
            try PreviewProcess.writeNew(
                result, to: assets.root.appendingPathComponent("refused.png"), protecting: assets.root)
        }
        #expect(try Data(contentsOf: assets.root.appendingPathComponent("release.json")) == before)
        let invalid = PreviewResult(report: result.report, png: Data([1, 2, 3]))
        #expect(throws: PreviewError.workerProtocol) { try PreviewProcess.validate(invalid, request: request) }
    }

    @Test("Unsupported content is explicit; missing assets and book roots fail without publishing an image")
    func failures() throws {
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let owner = PreviewProcess(workerURL: integrationWorker())
        let unknown = try owner.render(
            PreviewRequest(source: renderSource(name: "unknown-entity"), assetsPath: assets.root.path))
        #expect(unknown.report.warnings == ["Unsupported entity: unknown-entity (1)"])
        #expect(throws: PreviewError.workerFailed) {
            try owner.render(
                PreviewRequest(source: renderSource(), assetsPath: assets.root.appendingPathComponent("missing").path))
        }
        let json = Data("{\"blueprint_book\":{\"version\":1}}".utf8)
        let book = Data(("0" + (try ZlibCodec.compress(json, maximum: 1_000_000)).base64EncodedString()).utf8)
        #expect(throws: PreviewError.workerFailed) {
            try owner.render(PreviewRequest(source: book, assetsPath: assets.root.path))
        }
    }
}
