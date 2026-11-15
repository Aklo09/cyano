import CoreGraphics
import Foundation
import Synchronization

/// One Factorio icon in a release's render database, addressed as `<category>/<name>` (for example `item/iron-plate`).
public struct IconReference: Hashable, Sendable, CustomStringConvertible {
    public let category: String
    public let name: String

    /// Render-database categories that entry icons and rich-text tags may name (spec, "Icon tag").
    public static let categories: Set<String> = [
        "item", "fluid", "virtual-signal", "entity", "recipe", "tile", "quality", "asteroid-chunk", "space-location",
    ]

    public var description: String { "\(category)/\(name)" }

    init?(category: String, name: String) {
        guard Self.categories.contains(category), Self.valid(name) else { return nil }
        self.category = category
        self.name = name
    }

    /// A signal from an entry's `icons` field or a filter. Factorio omits the type for items and writes `virtual`
    /// for virtual signals; any other type has no icon category.
    public init?(signalType: String?, name: String) {
        let type = signalType ?? "item"
        self.init(category: type == "virtual" ? "virtual-signal" : type, name: name)
    }

    /// A rich-text tag such as `[item=iron-plate]`: its kind and the name before any `,quality=` part.
    /// `planet` tags name space locations. Other kinds (`color`, `font`, `gps`, `train`, …) have no icon.
    public init?(tagKind: String, name: String) {
        self.init(category: tagKind == "planet" ? "space-location" : tagKind, name: name)
    }

    /// The payload of an `[img=…]` tag: `<category>/<name>` or `<category>.<name>`.
    public init?(imagePath: String) {
        guard let separator = imagePath.firstIndex(where: { $0 == "/" || $0 == "." }) else { return nil }
        self.init(
            category: String(imagePath[..<separator]), name: String(imagePath[imagePath.index(after: separator)...]))
    }

    static func valid(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 200 && !name.unicodeScalars.contains(where: { $0.properties.isWhitespace })
    }
}

/// Factorio icons read at runtime from a verified asset release, never from the app bundle (spec GEN-9, ICN-*).
/// The release is verified once when the catalog loads; atlases decode lazily through Image I/O within a memory
/// bound, and composed icons are kept in memory only, never written to disk.
public final class IconCatalog: Sendable {
    /// The verified release identity this catalog belongs to.
    public let identity: String
    /// Every icon key the release names, for example `item/iron-plate`.
    public let keys: Set<String>
    private let state: Mutex<State>

    private struct State: ~Copyable {
        let assets: RenderAssets
        let icons: [String: Int]
        var images: [String: (image: CGImage, tick: Int)] = [:]
        var tick = 0
        var decodeFailures = 0
    }

    static let atlasCacheLimit = 32 * 1024 * 1024
    static let iconCacheLimit = 2048
    static let maximumIcons = 100_000

    /// Verifies the release and reads the 2x tier's icon table. Atlases are decoded on first use; fonts are not needed.
    public static func load(release url: URL) throws -> IconCatalog {
        try IconCatalog(
            assets: RenderAssets(path: url.path, tier: "2x", cacheLimit: atlasCacheLimit, loadsFont: false))
    }

    init(assets: sending RenderAssets) throws {
        struct Table: Decodable { let icons: [String: Int] }
        let icons = try JSONDecoder().decode(Table.self, from: assets.database).icons
        guard icons.count <= Self.maximumIcons,
            icons.allSatisfy({ key, frame in
                key.utf8.count <= 256 && key.contains("/") && assets.frames.indices.contains(frame)
                    && assets.frames[frame].sw <= 4096 && assets.frames[frame].sh <= 4096
            })
        else { throw PreviewError.assetDecode }
        identity = assets.identity
        keys = Set(icons.keys)
        state = Mutex(State(assets: assets, icons: icons))
    }

    public func contains(_ reference: IconReference) -> Bool { keys.contains(reference.description) }

    /// The icon at its logical size (64 × 64 pixels for game icons), or nil when the release has none for it or its
    /// atlas cannot be decoded; callers fall back to text (ICN-4, ICN-6).
    public func image(for reference: IconReference) -> CGImage? {
        let key = reference.description
        return state.withLock { state -> CGImage? in
            state.tick += 1
            if let cached = state.images[key] {
                state.images[key] = (cached.image, state.tick)
                return cached.image
            }
            guard let frame = state.icons[key] else { return nil }
            guard let image = try? Self.compose(frame, from: state.assets) else {
                state.decodeFailures += 1
                return nil
            }
            if state.images.count >= Self.iconCacheLimit,
                let oldest = state.images.min(by: { $0.value.tick < $1.value.tick })
            {
                state.images.removeValue(forKey: oldest.key)
            }
            state.images[key] = (image, state.tick)
            return image
        }
    }

    /// The badge for a quality other than normal, drawn in the icon's bottom-left corner (screen specs, "Icons").
    public func qualityBadge(_ quality: String?) -> CGImage? {
        guard let quality, quality != "normal", let reference = IconReference(category: "quality", name: quality)
        else { return nil }
        return image(for: reference)
    }

    /// How many lookups found an icon whose atlas could not be decoded; tests and diagnostics read it.
    public var decodeFailures: Int { state.withLock { $0.decodeFailures } }

    /// Atlas decodes so far; each icon atlas is decoded at most once while it stays within the memory bound.
    public var atlasDecodes: Int { state.withLock { $0.assets.atlasDecodes } }

    /// Places the trimmed frame at its offset inside the icon's full source rectangle, so every icon of a size lines up.
    static func compose(_ index: Int, from assets: RenderAssets) throws -> CGImage {
        let frame = assets.frames[index]
        let crop = try assets.crop(index)
        let width = Int(frame.sw.rounded(.up))
        let height = Int(frame.sh.rounded(.up))
        let context = try makeBitmap(width: width, height: height)
        context.draw(crop, in: CGRect(x: frame.ox, y: frame.sh - frame.oy - frame.h, width: frame.w, height: frame.h))
        guard let image = context.makeImage() else { throw PreviewError.imageAllocation }
        return image
    }
}
