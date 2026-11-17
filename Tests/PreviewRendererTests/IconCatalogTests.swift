import CoreGraphics
import FactorioData
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LibraryCore
@testable import PreviewRenderer

/// A verified release whose 2x atlas is a real 40 × 40 PNG with three colored blocks:
/// red 20 × 20 at (0, 0), blue 8 × 8 at (24, 0), and green 16 × 16 at (0, 24).
private struct IconTestRelease {
    static let red = (r: UInt8(220), g: UInt8(30), b: UInt8(30))
    static let blue = (r: UInt8(30), g: UInt8(30), b: UInt8(220))

    let root: URL
    let atlasURL: URL

    /// Frame 0 is the red block trimmed from a 32 × 32 icon at offset (6, 4); frame 1 the blue 8 × 8 quality badge;
    /// frame 2 the green block as a full 16 × 16 icon.
    static var frames: [[String: Any]] {
        [
            ["a": 0, "x": 0, "y": 0, "w": 20, "h": 20, "ox": 6, "oy": 4, "sw": 32, "sh": 32],
            ["a": 0, "x": 24, "y": 0, "w": 8, "h": 8, "ox": 0, "oy": 0, "sw": 8, "sh": 8],
            ["a": 0, "x": 0, "y": 24, "w": 16, "h": 16, "ox": 0, "oy": 0, "sw": 16, "sh": 16],
        ]
    }
    static var icons: [String: Any] {
        ["item/iron-plate": 0, "quality/rare": 1, "space-location/nauvis": 2, "virtual-signal/signal-A": 2]
    }

    init(icons: [String: Any]? = icons, frames: [[String: Any]] = frames) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-icons-\(UUID().uuidString)")
        atlasURL = root.appendingPathComponent("sprites/atlas.png")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sprites"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("statistics"), withIntermediateDirectories: false)
        let png = try Self.atlas()
        let mods = ["base", "elevated-rails", "quality", "recycler", "space-age"]
        var db: [String: Any] = [
            "schema": 2, "gameVersion": "2.1.24", "mods": mods, "assetDensity": 2,
            "atlases": [["file": "atlas.png", "width": 40, "height": 40]], "frames": frames,
            "entities": [:] as [String: Any], "tiles": [:] as [String: Any], "fluidRecipes": [:] as [String: Any],
            "iconScales": [:] as [String: Any],
        ]
        if let icons { db["icons"] = icons }
        let database = try Self.json(db)
        func descriptor(_ file: String, _ data: Data) -> [String: Any] {
            ["file": file, "bytes": data.count, "sha256": OriginalSource(bytes: data).sha256]
        }
        var atlas = descriptor("atlas.png", png)
        atlas["w"] = 40
        atlas["h"] = 40
        let manifest = try Self.json([
            "schema": 2, "gameVersion": "2.1.24", "mods": mods,
            "tiers": ["2x": ["density": 2, "renderDb": descriptor("render-db.json", database), "atlases": [atlas]]],
            "fonts": [] as [Any],
        ])
        let map = try Self.json([
            "schema": 2, "gameVersion": "2.1.24", "mods": Dictionary(uniqueKeysWithValues: mods.map { ($0, "2.1.24") }),
        ])
        let members = [
            "sprites/manifest.json": manifest, "sprites/render-db.json": database, "sprites/atlas.png": png,
            "statistics/prototype-map.json": map,
        ]
        let files = members.keys.sorted().map {
            ["path": $0, "bytes": members[$0]!.count, "sha256": OriginalSource(bytes: members[$0]!).sha256]
                as [String: Any]
        }
        let profile: [String: Any] = ["gameVersion": "2.1.24", "mods": mods.map { ["name": $0, "version": "2.1.24"] }]
        let identity: [String: Any] = [
            "schema": 1, "profile": profile, "provenance": ["source": "icon-catalog-test"], "files": files,
        ]
        var release = identity
        release["id"] = "icons"
        release["identity"] = OriginalSource(bytes: try Self.json(identity)).sha256
        for (path, data) in members { try data.write(to: root.appendingPathComponent(path)) }
        try Self.json(release).write(to: root.appendingPathComponent("release.json"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    static func atlas() throws -> Data {
        let context = try makeBitmap(width: 40, height: 40)
        func fill(_ color: (r: UInt8, g: UInt8, b: UInt8), _ x: Int, _ top: Int, _ size: Int) {
            context.setFillColor(
                CGColor(
                    srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255,
                    alpha: 1))
            // Core Graphics counts from the bottom; atlas frames count from the top.
            context.fill(CGRect(x: x, y: 40 - top - size, width: size, height: size))
        }
        fill(red, 0, 0, 20)
        fill(blue, 24, 0, 8)
        fill((30, 200, 30), 0, 24, 16)
        let png = NSMutableData()
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return png as Data
    }

    static func json(_ value: Any) throws -> Data {
        var bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        bytes.append(10)
        return bytes
    }
}

/// RGBA of the pixel at (x, y) counted from the top-left corner.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let context = try makeBitmap(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let offset = (y * image.width + x) * 4
    return Array(UnsafeBufferPointer(start: data + offset, count: 4))
}

@Suite("Icon catalog")
struct IconCatalogTests {
    @Test("A known icon is composed at its full size with the trimmed frame at its offset")
    func knownIcon() throws {
        let release = try IconTestRelease()
        defer { release.cleanup() }
        let catalog = try IconCatalog.load(release: release.root)
        let plate = try #require(IconReference(signalType: nil, name: "iron-plate"))
        #expect(catalog.contains(plate))
        let image = try #require(catalog.image(for: plate))
        #expect(image.width == 32 && image.height == 32)
        let red = IconTestRelease.red
        #expect(try pixel(image, 6, 4) == [red.r, red.g, red.b, 255])
        #expect(try pixel(image, 25, 23) == [red.r, red.g, red.b, 255])
        #expect(try pixel(image, 5, 4)[3] == 0)
        #expect(try pixel(image, 26, 24)[3] == 0)
        #expect(catalog.keys.count == 4 && catalog.decodeFailures == 0)
    }

    @Test("Icons are kept in memory: repeated and shared-atlas lookups decode the atlas once")
    func cachedIcons() throws {
        let release = try IconTestRelease()
        defer { release.cleanup() }
        let catalog = try IconCatalog.load(release: release.root)
        let plate = try #require(IconReference(signalType: "item", name: "iron-plate"))
        let first = try #require(catalog.image(for: plate))
        #expect(catalog.image(for: plate) === first)
        let nauvis = try #require(IconReference(tagKind: "planet", name: "nauvis"))
        _ = try #require(catalog.image(for: nauvis))
        #expect(catalog.atlasDecodes == 1)
    }

    @Test("ICN-4, ICN-6: names, types, and tag kinds without an icon give nil, not an error")
    func unknownIcons() throws {
        let release = try IconTestRelease()
        defer { release.cleanup() }
        let catalog = try IconCatalog.load(release: release.root)
        for reference in [
            IconReference(signalType: nil, name: "copper-plate"), IconReference(tagKind: "planet", name: "gleba"),
            IconReference(tagKind: "fluid", name: "water"),
        ] {
            let known = try #require(reference)
            #expect(!catalog.contains(known) && catalog.image(for: known) == nil)
        }
        #expect(IconReference(signalType: "technology", name: "automation") == nil)
        #expect(IconReference(tagKind: "color", name: "red") == nil)
        #expect(IconReference(tagKind: "gps", name: "10") == nil)
        #expect(IconReference(tagKind: "item", name: "") == nil)
        #expect(IconReference(tagKind: "item", name: "iron plate") == nil)
        #expect(IconReference(imagePath: "utility/missing-icon") == nil)
        #expect(IconReference(imagePath: "iron-plate") == nil)
        #expect(catalog.decodeFailures == 0)
    }

    @Test("Signal types, tag kinds, and img paths map to render-database categories")
    func references() throws {
        #expect(IconReference(signalType: nil, name: "iron-plate")?.description == "item/iron-plate")
        #expect(IconReference(signalType: "virtual", name: "signal-A")?.description == "virtual-signal/signal-A")
        #expect(IconReference(signalType: "space-location", name: "nauvis")?.description == "space-location/nauvis")
        #expect(IconReference(signalType: "asteroid-chunk", name: "metallic")?.description == "asteroid-chunk/metallic")
        #expect(IconReference(tagKind: "virtual-signal", name: "signal-A")?.description == "virtual-signal/signal-A")
        #expect(IconReference(tagKind: "planet", name: "nauvis")?.description == "space-location/nauvis")
        #expect(IconReference(tagKind: "tile", name: "concrete")?.description == "tile/concrete")
        #expect(IconReference(imagePath: "item/iron-plate")?.description == "item/iron-plate")
        #expect(IconReference(imagePath: "virtual-signal.signal-A")?.description == "virtual-signal/signal-A")
    }

    @Test("Quality badges exist only for qualities other than normal that the release has")
    func qualityBadges() throws {
        let release = try IconTestRelease()
        defer { release.cleanup() }
        let catalog = try IconCatalog.load(release: release.root)
        let badge = try #require(catalog.qualityBadge("rare"))
        let blue = IconTestRelease.blue
        let corner = try pixel(badge, 0, 0)
        #expect(badge.width == 8 && badge.height == 8 && corner == [blue.r, blue.g, blue.b, 255])
        #expect(catalog.qualityBadge("normal") == nil)
        #expect(catalog.qualityBadge(nil) == nil)
        #expect(catalog.qualityBadge("legendary") == nil)
    }

    @Test("Malformed icon tables are refused when the catalog loads")
    func malformedTables() throws {
        for icons: [String: Any]? in [nil, ["item/iron-plate": 3], ["iron-plate": 0], ["item/iron-plate": "0"]] {
            let release = try IconTestRelease(icons: icons)
            defer { release.cleanup() }
            #expect(throws: (any Error).self) { try IconCatalog.load(release: release.root) }
        }
    }

    @Test("An atlas that changes after loading is not decoded; the icon is missing and the failure counted")
    func changedAtlas() throws {
        let release = try IconTestRelease()
        defer { release.cleanup() }
        let catalog = try IconCatalog.load(release: release.root)
        try Data("not the verified atlas".utf8).write(to: release.atlasURL)
        let plate = try #require(IconReference(signalType: nil, name: "iron-plate"))
        #expect(catalog.image(for: plate) == nil)
        #expect(catalog.decodeFailures == 1)
    }

    @Test("A release that fails verification gives no catalog")
    func unverifiedRelease() throws {
        let release = try IconTestRelease()
        defer { release.cleanup() }
        try Data("changed".utf8).write(to: release.atlasURL)
        #expect(throws: (any Error).self) { try IconCatalog.load(release: release.root) }
    }
}

private let iconRepository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
private let iconPrivateRelease = iconRepository.appendingPathComponent(".cache/renderer-assets")

@Suite("Icon catalog with the private release")
struct PrivateIconCatalogTests {
    @Test(
        "Real WebP atlases give 64 × 64 icons for items, signals, planets, and quality badges",
        .enabled(
            if: FileManager.default.fileExists(atPath: iconPrivateRelease.appendingPathComponent("release.json").path),
            "Needs the private release in .cache/renderer-assets"))
    func privateRelease() throws {
        let catalog = try IconCatalog.load(release: iconPrivateRelease)
        let references =
            [
                IconReference(signalType: nil, name: "iron-plate"), IconReference(signalType: "fluid", name: "water"),
                IconReference(signalType: "virtual", name: "signal-A"), IconReference(tagKind: "entity", name: "lab"),
            ] + ["nauvis", "vulcanus", "gleba", "fulgora", "aquilo"].map { IconReference(tagKind: "planet", name: $0) }
        for reference in references {
            let known = try #require(reference)
            let image = try #require(catalog.image(for: known), "\(known)")
            #expect(image.width == 64 && image.height == 64, "\(known)")
        }
        for quality in ["uncommon", "rare", "epic", "legendary"] {
            #expect(catalog.qualityBadge(quality) != nil, "\(quality)")
        }
        #expect(catalog.decodeFailures == 0)
    }
}

@Suite("Statistics icons with the private release")
struct PrivateStatisticsIconTests {
    @Test(
        "ICN-9: every item and quality in the private prototype map has an icon in the same release",
        .enabled(
            if: FileManager.default.fileExists(atPath: iconPrivateRelease.appendingPathComponent("release.json").path),
            "Needs the private release in .cache/renderer-assets"))
    func everyMapItem() throws {
        let catalog = try IconCatalog.load(release: iconPrivateRelease)
        let map = try PrototypeMap.load(release: iconPrivateRelease)
        let missing = map.items.keys.filter { name in
            IconReference(signalType: nil, name: name).map { !catalog.contains($0) } ?? true
        }
        #expect(missing.isEmpty, "\(missing.sorted())")
        #expect(map.items.count == 342)
        for quality in map.qualities where quality != "normal" {
            #expect(IconReference(tagKind: "quality", name: quality).map(catalog.contains) == true, "\(quality)")
        }
    }
}
