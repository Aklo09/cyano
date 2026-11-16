import Darwin
import Foundation
import LibraryCore

public enum AssetReleaseError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

public struct AssetReleaseReport: Encodable, Sendable {
    public let id: String
    public let identity: String
    public let profile: FactorioProfile
    public let files: Int
    public let totalBytes: Int
    public let tiers: [String]
    public let imageDecodingPerformed = false
    package let spriteManifestSha256: String
    package let prototypeMapSha256: String

    private enum CodingKeys: String, CodingKey {
        case id, identity, profile, files, totalBytes, tiers, imageDecodingPerformed
    }
}

/// Offline inventory/schema verification; does not invoke Factorio or decode atlas pixels.
public enum AssetRelease {
    public static func verify(at url: URL) throws -> AssetReleaseReport {
        let root = try LibraryDirectory(url: url)
        let maximum = 2 * 1024 * 1024 * 1024
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw AssetReleaseError.invalid(message) }
        }
        func safe(_ path: String) throws -> [String] {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            try require(
                path.utf8.count <= 4096 && parts.count <= 32
                    && parts.allSatisfy { part in
                        !part.isEmpty && part.utf8.count <= 255 && part.first != "."
                            && part.utf8.allSatisfy {
                                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                                    || [45, 46, 95].contains($0)
                            }
                    }, "Unsafe asset member path.")
            return parts
        }
        func member(_ path: String) throws -> (LibraryDirectory, String) {
            var parts = try safe(path)
            let name = parts.removeLast()
            var parent = root
            for part in parts { parent = try parent.child(part) }
            return (parent, name)
        }
        func read(_ path: String, maximum: Int = 16 * 1024 * 1024) throws -> JSONValue {
            let (parent, name) = try member(path)
            var limits = BlueprintCodecLimits()
            limits.decodedBytes = maximum
            var parser = try BoundedJSONParser(data: parent.read(name, maximum: maximum), limits: limits)
            return try parser.parse()
        }
        func object(_ value: JSONValue?) -> [JSONMember]? {
            if case .object(let members) = value { return members }
            return nil
        }
        func hash(_ value: String?) -> Bool {
            value?.utf8.count == 64 && value!.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        func canonical(_ value: JSONValue) throws -> JSONValue {
            switch value {
            case .object(let members):
                return .object(
                    try members.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }.map {
                        JSONMember(key: $0.key, value: try canonical($0.value))
                    })
            case .array(let values): return .array(try values.map(canonical))
            case .number:
                guard let number = value.safeInteger else {
                    throw AssetReleaseError.invalid("Descriptor identity requires bounded integer numbers.")
                }
                return .number(JSONNumber(String(number)))
            default: return value
            }
        }
        let descriptorBytes = try root.read("release.json", maximum: 4 * 1024 * 1024)
        var descriptorParser = try BoundedJSONParser(data: descriptorBytes, limits: .standard)
        let descriptor = try descriptorParser.parse()
        guard let id = descriptor["id"]?.string, let identity = descriptor["identity"]?.string,
            let files = descriptor["files"]?.array, let profile = descriptor["profile"],
            let provenance = descriptor["provenance"]
        else { throw AssetReleaseError.invalid("Invalid asset release descriptor.") }
        try require(
            descriptor["schema"]?.safeInteger == 1 && !id.isEmpty && id.utf8.count <= 100
                && id.utf8.first.map { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }
                    == true
                && id.utf8.allSatisfy {
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                        || [45, 46, 95].contains($0)
                }, "Unsupported asset release descriptor.")
        try require(!files.isEmpty && files.count <= 10_000 && hash(identity), "Invalid asset inventory.")
        let identityValue = JSONValue.object([
            JSONMember(key: "schema", value: .number(JSONNumber("1"))), JSONMember(key: "profile", value: profile),
            JSONMember(key: "provenance", value: provenance), JSONMember(key: "files", value: .array(files)),
        ])
        var identityBytes = try canonical(identityValue).encoded(maximum: 4 * 1024 * 1024)
        identityBytes.append(10)
        try require(OriginalSource(bytes: identityBytes).sha256 == identity, "Asset descriptor identity differs.")
        var inventory: [String: (bytes: Int, sha256: String)] = [:]
        var total = 0
        var ordered: [String] = []
        for file in files {
            guard let path = file["path"]?.string, let bytes = file["bytes"]?.safeInteger,
                let sha = file["sha256"]?.string
            else { throw AssetReleaseError.invalid("Invalid asset inventory entry.") }
            _ = try safe(path)
            try require(
                path.hasPrefix("sprites/") || path == "statistics/prototype-map.json", "Unsupported asset member.")
            try require(hash(sha) && bytes <= maximum - total, "Asset release exceeds its bounds.")
            total += bytes
            ordered.append(path)
            inventory[path] = (bytes, sha)
        }
        try require(
            ordered == ordered.sorted() && Set(ordered.map { $0.lowercased() }).count == ordered.count,
            "Asset inventory must be sorted and unique.")
        // Capture identity and timestamps so changes across separate JSON/hash reads are rejected.
        var snapshot: [String: [Int64]] = [:]
        func scan(_ directory: LibraryDirectory, prefix: String, depth: Int) throws {
            try require(depth <= 32 && snapshot.count <= 20_000, "Asset directory limits exceeded.")
            for name in try directory.entries(maximum: 20_000, includingFinderMetadata: true) {
                let path = prefix.isEmpty ? name : prefix + "/" + name
                _ = try safe(path)
                guard let info = try directory.info(name) else {
                    throw AssetReleaseError.invalid("Asset member disappeared.")
                }
                try require(info.st_dev == root.device, "Cross-device asset members are refused.")
                let mode = info.st_mode & S_IFMT
                try require(
                    mode == S_IFDIR || (mode == S_IFREG && info.st_nlink == 1),
                    "Asset members must be private regular files or directories.")
                snapshot[path] = [
                    Int64(info.st_ino), Int64(info.st_size), Int64(info.st_mtimespec.tv_sec),
                    Int64(info.st_mtimespec.tv_nsec), Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec),
                    Int64(mode),
                ]
                try require(snapshot.count <= 20_000, "Asset directory limits exceeded.")
                if mode == S_IFDIR { try scan(directory.child(name), prefix: path, depth: depth + 1) }
            }
        }
        try scan(root, prefix: "", depth: 0)
        let firstSnapshot = snapshot
        try require(
            try root.read("release.json", maximum: 4 * 1024 * 1024) == descriptorBytes,
            "Asset descriptor changed during verification.")
        let actualFiles = snapshot.filter { $0.value.last == Int64(S_IFREG) }.keys.filter { $0 != "release.json" }
            .sorted()
        try require(actualFiles == ordered, "Asset inventory is incomplete or contains unknown files.")
        for path in ordered {
            let (parent, name) = try member(path)
            let actual = try parent.fingerprint(name, maximum: maximum)
            try require(
                actual.bytes == inventory[path]!.bytes && actual.sha256 == inventory[path]!.sha256,
                "Asset member size or checksum differs: " + path)
        }
        let manifest = try read("sprites/manifest.json", maximum: 4 * 1024 * 1024)
        let map = try read("statistics/prototype-map.json")
        let initial = FactorioProfile.initial
        let expectedMods = initial.mods.sorted()
        guard let modValues = manifest["mods"]?.array, let mapMods = object(map["mods"]),
            let profileMods = profile["mods"]?.array
        else { throw AssetReleaseError.invalid("Invalid asset mod profile.") }
        let mods = modValues.compactMap(\.string)
        try require(
            manifest["schema"]?.safeInteger == 2 && map["schema"]?.safeInteger == initial.prototypeMapSchema
                && manifest["gameVersion"]?.string == initial.gameVersion
                && map["gameVersion"]?.string == initial.gameVersion
                && profile["gameVersion"]?.string == initial.gameVersion && modValues.count == mods.count
                && mods.sorted() == expectedMods && mapMods.map(\.key).sorted() == expectedMods
                && mapMods.allSatisfy { $0.value.string == initial.gameVersion }
                && profileMods.compactMap { $0["name"]?.string } == mods
                && profileMods.allSatisfy { $0["version"]?.string == initial.gameVersion },
            "Unsupported or inconsistent asset profile.")
        guard let tiers = object(manifest["tiers"]), tiers.contains(where: { $0.key == "2x" }),
            let fonts = manifest["fonts"]?.array
        else { throw AssetReleaseError.invalid("The 2x tier and font inventory are required.") }
        func check(_ member: JSONValue) throws {
            guard let file = member["file"]?.string, let bytes = member["bytes"]?.safeInteger,
                let sha = member["sha256"]?.string
            else { throw AssetReleaseError.invalid("Invalid sprite member descriptor.") }
            _ = try safe(file)
            let actual = inventory["sprites/" + file]
            try require(actual?.bytes == bytes && actual?.sha256 == sha, "Sprite manifest inventory differs.")
        }
        for tier in tiers {
            guard ["1x", "2x"].contains(tier.key), let atlases = tier.value["atlases"]?.array,
                let renderDB = tier.value["renderDb"]
            else { throw AssetReleaseError.invalid("Unsupported sprite tier.") }
            try require(tier.value["density"]?.safeInteger == (tier.key == "1x" ? 1 : 2), "Invalid sprite density.")
            try check(renderDB)
            for atlas in atlases {
                try check(atlas)
                try require(
                    (1...16_384).contains(atlas["w"]?.safeInteger ?? 0)
                        && (1...16_384).contains(atlas["h"]?.safeInteger ?? 0), "Invalid atlas dimensions.")
            }
            let db = try read("sprites/" + renderDB["file"]!.string!)
            guard let dbAtlases = db["atlases"]?.array, let frames = db["frames"]?.array else {
                throw AssetReleaseError.invalid("Invalid render database.")
            }
            try require(
                db["schema"]?.safeInteger == 2 && db["gameVersion"]?.string == initial.gameVersion
                    && db["mods"] == manifest["mods"]
                    && db["assetDensity"]?.safeInteger == tier.value["density"]?.safeInteger
                    && dbAtlases.count == atlases.count, "Render database profile differs.")
            for (index, atlas) in dbAtlases.enumerated() {
                try require(
                    atlas["file"] == atlases[index]["file"] && atlas["width"] == atlases[index]["w"]
                        && atlas["height"] == atlases[index]["h"], "Render database atlas dimensions differ.")
            }
            for frame in frames {
                guard let a = frame["a"]?.safeInteger, a < atlases.count, let x = frame["x"]?.safeInteger,
                    let y = frame["y"]?.safeInteger, let w = frame["w"]?.safeInteger, let h = frame["h"]?.safeInteger
                else { throw AssetReleaseError.invalid("Invalid atlas frame.") }
                // Frame geometry stays in canonical 2x pixels. pw/ph describe packed atlas pixels.
                guard let packedWidth = (frame["pw"] ?? frame["w"])?.safeInteger,
                    let packedHeight = (frame["ph"] ?? frame["h"])?.safeInteger
                else { throw AssetReleaseError.invalid("Invalid packed frame dimensions.") }
                try require(
                    w > 0 && h > 0 && packedWidth > 0 && packedHeight > 0
                        && x <= atlases[a]["w"]!.safeInteger! - packedWidth
                        && y <= atlases[a]["h"]!.safeInteger! - packedHeight,
                    "Atlas frame is outside its declared bounds.")
            }
        }
        for font in fonts { try check(font) }
        snapshot = [:]
        try scan(root, prefix: "", depth: 0)
        try require(snapshot == firstSnapshot, "Assets changed during verification.")
        try root.check()
        return AssetReleaseReport(
            id: id, identity: identity, profile: initial, files: files.count, totalBytes: total,
            tiers: tiers.map(\.key).sorted(), spriteManifestSha256: inventory["sprites/manifest.json"]!.sha256,
            prototypeMapSha256: inventory["statistics/prototype-map.json"]!.sha256)
    }
}
