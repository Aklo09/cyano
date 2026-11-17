import Darwin
import FactorioData
import Foundation
import LibraryCore
import Testing

func assetJSON(_ value: Any) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    data.append(10)
    return data
}

struct TestAssetRelease {
    let root: URL
    /// `prototypeMap` replaces the minimal map that asset verification alone needs.
    init(
        frameOutside: Bool = false, density: Int = 2, gameVersion: String = "2.1.24", packedFrame: Bool = false,
        prototypeMap: Data? = nil
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sprites/fonts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("statistics"), withIntermediateDirectories: false)
        let mods = FactorioProfile.initial.mods
        let modMap = Dictionary(uniqueKeysWithValues: mods.map { ($0, gameVersion) })
        let atlas = Data("Deliberately not an image: inventory verification only".utf8)
        let font = Data("Test font bytes".utf8)
        var frame = ["a": 0, "x": frameOutside ? 101 : 0, "y": 0, "w": 10, "h": 10]
        if packedFrame {
            frame["w"] = 200
            frame["h"] = 200
            frame["pw"] = 100
            frame["ph"] = 100
        }
        let db = try assetJSON([
            "schema": 2, "gameVersion": gameVersion, "mods": mods, "assetDensity": density,
            "atlases": [["file": "atlas.webp", "width": 100, "height": 100]],
            "frames": [frame],
        ])
        func descriptor(_ file: String, _ data: Data) -> [String: Any] {
            ["file": file, "bytes": data.count, "sha256": OriginalSource(bytes: data).sha256]
        }
        var atlasDescriptor = descriptor("atlas.webp", atlas)
        atlasDescriptor["w"] = 100
        atlasDescriptor["h"] = 100
        let manifest = try assetJSON([
            "schema": 2, "gameVersion": gameVersion, "mods": mods,
            "tiers": [
                "2x": ["density": density, "renderDb": descriptor("render-db.json", db), "atlases": [atlasDescriptor]]
            ],
            "fonts": [descriptor("fonts/font.ttf", font)],
        ])
        let members = [
            "sprites/atlas.webp": atlas, "sprites/fonts/font.ttf": font, "sprites/render-db.json": db,
            "sprites/manifest.json": manifest,
            "statistics/prototype-map.json": try prototypeMap
                ?? assetJSON(["schema": 2, "gameVersion": gameVersion, "mods": modMap]),
        ]
        let files: [[String: Any]] = members.keys.sorted().map { path in
            ["path": path, "bytes": members[path]!.count, "sha256": OriginalSource(bytes: members[path]!).sha256]
        }
        let profile: [String: Any] = [
            "gameVersion": gameVersion, "mods": mods.map { ["name": $0, "version": gameVersion] },
        ]
        let provenance = ["assembly": "test-fixture"]
        let identity = OriginalSource(
            bytes: try assetJSON(["schema": 1, "profile": profile, "provenance": provenance, "files": files])
        ).sha256
        for (path, data) in members { try data.write(to: root.appendingPathComponent(path)) }
        try assetJSON([
            "schema": 1, "id": "fixture", "identity": identity, "profile": profile, "provenance": provenance,
            "files": files,
        ])
        .write(to: root.appendingPathComponent("release.json"))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Native asset release verification", .serialized)
struct AssetReleaseTests {
    @Test("Inventory, hashes, profile, dimensions, and canonical identity pass without image decoding or a library")
    func valid() throws {
        let assets = try TestAssetRelease()
        defer { assets.cleanup() }
        let report = try AssetRelease.verify(at: assets.root)
        #expect(report.id == "fixture" && report.files == 5 && report.tiers == ["2x"])
        #expect(report.profile == .initial && report.totalBytes > 0 && !report.imageDecodingPerformed)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/debug/cyano")
        process.arguments = ["assets-verify", assets.root.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let response = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(response["ok"] as? Bool == true)
        #expect(!FileManager.default.fileExists(atPath: assets.root.appendingPathComponent(".owner.lock").path))
    }

    @Test("Tampering with a member or release identity and unknown inventory members are refused")
    func corrupt() throws {
        for mode in ["member", "identity", "unknown"] {
            let assets = try TestAssetRelease()
            defer { assets.cleanup() }
            if mode == "member" {
                try Data("tampered".utf8).write(to: assets.root.appendingPathComponent("sprites/atlas.webp"))
            } else if mode == "unknown" {
                try Data([1]).write(to: assets.root.appendingPathComponent("unknown.bin"))
            } else {
                let url = assets.root.appendingPathComponent("release.json")
                var descriptor = try #require(
                    JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                descriptor["identity"] = String(repeating: "a", count: 64)
                try assetJSON(descriptor).write(to: url)
            }
            #expect(throws: AssetReleaseError.self) { try AssetRelease.verify(at: assets.root) }
        }
    }

    @Test("Symlinks and shared file inodes cannot escape asset verification")
    func unsafe() throws {
        for mode in ["symlink", "hardlink"] {
            let assets = try TestAssetRelease()
            defer { assets.cleanup() }
            let url = assets.root.appendingPathComponent("sprites/alias.webp")
            if mode == "symlink" {
                try FileManager.default.createSymbolicLink(
                    at: url, withDestinationURL: assets.root.appendingPathComponent("sprites/atlas.webp"))
            } else {
                try FileManager.default.linkItem(at: assets.root.appendingPathComponent("sprites/atlas.webp"), to: url)
            }
            #expect(throws: AssetReleaseError.self) { try AssetRelease.verify(at: assets.root) }
        }
    }

    @Test("Even correctly hashed assets must have the supported profile, density, and bounded frame rectangles")
    func incompatible() throws {
        let frame = try TestAssetRelease(frameOutside: true)
        defer { frame.cleanup() }
        #expect(throws: AssetReleaseError.self) { try AssetRelease.verify(at: frame.root) }
        let density = try TestAssetRelease(density: 1)
        defer { density.cleanup() }
        #expect(throws: AssetReleaseError.self) { try AssetRelease.verify(at: density.root) }
        let profile = try TestAssetRelease(gameVersion: "2.0.0")
        defer { profile.cleanup() }
        #expect(throws: AssetReleaseError.self) { try AssetRelease.verify(at: profile.root) }
    }

    @Test("Packed pixel sizes govern atlas bounds while canonical frame geometry can be larger")
    func packedDimensions() throws {
        let assets = try TestAssetRelease(packedFrame: true)
        defer { assets.cleanup() }
        #expect(try AssetRelease.verify(at: assets.root).files == 5)
    }
}
