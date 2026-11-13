import Foundation

public enum PreviewError: Error, CustomStringConvertible {
    case invalidInput, invalidDrawList, assetDecode, imageAllocation, imageEncoding
    case timedOut, cancelled, workerFailed, workerProtocol, workerBusy, memoryLimit
    public var description: String {
        switch self {
        case .invalidInput: "Invalid preview input, selection, tier, or output limits."
        case .invalidDrawList: "The planner returned unsupported or invalid drawing commands."
        case .assetDecode: "An atlas or font failed native decoding or exceeded its bounds."
        case .imageAllocation: "The bounded image allocation failed."
        case .imageEncoding: "PNG encoding or independent decoding failed."
        case .timedOut: "The preview worker exceeded its execution deadline."
        case .cancelled: "The preview job was cancelled."
        case .workerFailed: "The preview worker exited unsuccessfully."
        case .workerProtocol: "The preview worker returned an invalid or oversized result."
        case .workerBusy: "This preview owner already has an active job."
        case .memoryLimit: "The preview worker exceeded its resident-memory limit."
        }
    }
}

public struct PreviewRequest: Codable, Sendable {
    public let source: Data
    public let entryPath: [Int]
    public let assetsPath: String
    public let tier: String
    public let maximumDimension: Int
    public let checkerboard: Bool
    public init(
        source: Data, entryPath: [Int] = [], assetsPath: String, tier: String = "2x", maximumDimension: Int = 2048,
        checkerboard: Bool = false
    ) {
        self.source = source
        self.entryPath = entryPath
        self.assetsPath = assetsPath
        self.tier = tier
        self.maximumDimension = maximumDimension
        self.checkerboard = checkerboard
    }
    func validate() throws {
        guard !source.isEmpty, source.count <= 16 * 1024 * 1024, entryPath.count <= 32,
            entryPath.allSatisfy({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }),
            assetsPath.utf8.count <= 4096, !assetsPath.contains("\0"), ["1x", "2x"].contains(tier),
            (64...4096).contains(maximumDimension)
        else { throw PreviewError.invalidInput }
    }
}

public struct PreviewReport: Codable, Sendable {
    public let schema: Int
    public let width: Int
    public let height: Int
    public let entryKind: String
    public let sourceSha256: String
    public let entryPath: [Int]
    public let assetIdentity: String
    public let plannerRevision: String
    public let pixelsPerTile: Double
    public let commandKinds: [String: Int]
    public let warnings: [String]
    public var timingsMs: [String: Double]
    public let peakResidentBytes: UInt64
    public let atlasDecodes: Int
}

public struct PreviewResult: Codable, Sendable {
    public var report: PreviewReport
    public let png: Data
}

struct DrawBounds: Codable {
    let minX: Double, minY: Double, maxX: Double, maxY: Double
    func validate() throws {
        guard [minX, minY, maxX, maxY].allSatisfy({ $0.isFinite && abs($0) <= 1e8 }), minX <= maxX, minY <= maxY else {
            throw PreviewError.invalidDrawList
        }
    }
}
struct DrawRect: Codable { let x: Double, y: Double, w: Double, h: Double }
struct DrawPoint: Codable { let x: Double, y: Double }
struct DrawSegment: Codable { let x1: Double, y1: Double, x2: Double, y2: Double }
struct SeamBleed: Codable { let top: Bool?, right: Bool?, bottom: Bool?, left: Bool? }
struct DrawCommand: Codable {
    let kind: String
    let layer: Double
    let sortY: Double, sortX: Double, entity: Double, sub: Double
    var x: Double?, y: Double?, w: Double?, h: Double?, size: Double?
    var color: [Double]?, tint: [Double]?
    var frame: Int?, backingFrame: Int?
    var shadow: Bool?, flipX: Bool?, flipY: Bool?, rotation: Double?
    var src: DrawRect?, clip: DrawRect?, seamBleed: SeamBleed?
    var backing: Bool?, silhouette: Bool?, backingStyle: String?
    var text: String?, align: String?, baseline: String?, wire: String?
    var x1: Double?, y1: Double?, x2: Double?, y2: Double?
    var segments: [DrawSegment]?, joints: [DrawPoint]?

    func validate(frames: Int) throws {
        func number(_ value: Double?) throws {
            guard let value, value.isFinite, abs(value) <= 1e8 else { throw PreviewError.invalidDrawList }
        }
        func rectangle(_ rect: DrawRect) throws {
            for v in [rect.x, rect.y, rect.w, rect.h] { try number(v) }
            guard rect.w >= 0, rect.h >= 0 else { throw PreviewError.invalidDrawList }
        }
        for value in [layer, sortY, sortX, entity, sub] { try number(value) }
        if let rotation { try number(rotation) }
        for rgba in [color, tint].compactMap({ $0 }) {
            guard rgba.count == 4, rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw PreviewError.invalidDrawList
            }
        }
        for rect in [src, clip].compactMap({ $0 }) { try rectangle(rect) }
        for index in [frame, backingFrame].compactMap({ $0 }) {
            guard (0..<frames).contains(index) else { throw PreviewError.invalidDrawList }
        }
        switch kind {
        case "rect", "sprite", "snap-grid":
            for v in [x, y, w, h] { try number(v) }
            guard w! >= 0, h! >= 0 else { throw PreviewError.invalidDrawList }
            if kind == "sprite", frame == nil { throw PreviewError.invalidDrawList }
            if kind == "rect", color == nil { throw PreviewError.invalidDrawList }
        case "icon":
            for v in [x, y, size] { try number(v) }
            guard size! >= 0, frame != nil,
                backingStyle == nil || ["entity-info", "request-pin"].contains(backingStyle!)
            else { throw PreviewError.invalidDrawList }
        case "text":
            for v in [x, y, size] { try number(v) }
            guard let text, text.utf8.count <= 64 * 1024, size! > 0, color != nil,
                align == nil || ["left", "center", "right"].contains(align!),
                baseline == nil || ["top", "middle", "alphabetic"].contains(baseline!)
            else { throw PreviewError.invalidDrawList }
        case "wire":
            for v in [x1, y1, x2, y2] { try number(v) }
            guard let wire, ["copper", "red", "green"].contains(wire) else { throw PreviewError.invalidDrawList }
        case "train-chain":
            guard let segments, let joints, segments.count + joints.count <= 100_000 else {
                throw PreviewError.invalidDrawList
            }
            for s in segments { for v in [s.x1, s.y1, s.x2, s.y2] { try number(v) } }
            for p in joints {
                try number(p.x)
                try number(p.y)
            }
        default: throw PreviewError.invalidDrawList
        }
    }
}
struct DrawList: Codable { let schema: Int, bounds: DrawBounds, commands: [DrawCommand] }
struct PlannedPreview: Codable {
    let schema: Int
    let drawList: DrawList
    let warnings: [String]
    let commandKinds: [String: Int]
    let parseMs: Double
    let planningMs: Double
}

func previewMilliseconds() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
