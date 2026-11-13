import CoreGraphics
import CoreText
import FactorioData
import Foundation
import ImageIO
import LibraryCore

struct AtlasDescriptor: Decodable { let file: String, w: Int, h: Int, sha256: String, bytes: Int }
struct AssetDescriptor: Decodable { let file: String, sha256: String, bytes: Int }
struct SpriteTier: Decodable { let renderDb: AssetDescriptor, atlases: [AtlasDescriptor] }
struct SpriteManifest: Decodable { let tiers: [String: SpriteTier], fonts: [AssetDescriptor] }
struct SpriteFrame: Decodable {
    let a: Int
    let x: Double, y: Double, w: Double, h: Double, ox: Double, oy: Double, sw: Double, sh: Double
    let pw: Double?, ph: Double?
    var packedWidth: Double { pw ?? w }
    var packedHeight: Double { ph ?? h }
}
struct FrameDatabase: Decodable { let frames: [SpriteFrame] }

protocol FrameSource {
    var frames: [SpriteFrame] { get }
    var font: CGFont? { get }
    func crop(_ index: Int) throws -> CGImage
}

final class RenderAssets: FrameSource {
    let identity: String
    let frames: [SpriteFrame]
    let database: Data
    let font: CGFont?
    let descriptors: [AtlasDescriptor]
    let root: LibraryDirectory
    var atlasDecodes = 0
    private var images: [Int: (image: CGImage, tick: Int, bytes: Int)] = [:]
    private var tick = 0
    private var decodedBytes = 0
    private let cacheLimit = 128 * 1024 * 1024

    init(path: String, tier: String, afterVerification: (() throws -> Void)? = nil) throws {
        let url = URL(fileURLWithPath: path)
        let verified = try AssetRelease.verify(at: url)
        try afterVerification?()
        identity = verified.identity
        let spriteRoot = try LibraryDirectory(url: url).child("sprites")
        root = spriteRoot
        let manifestBytes = try spriteRoot.read("manifest.json", maximum: 4 * 1024 * 1024)
        guard OriginalSource(bytes: manifestBytes).sha256 == verified.spriteManifestSha256 else {
            throw PreviewError.assetDecode
        }
        let manifest = try JSONDecoder().decode(SpriteManifest.self, from: manifestBytes)
        guard let selection = manifest.tiers[tier] else { throw PreviewError.invalidInput }
        descriptors = selection.atlases
        func read(_ descriptor: AssetDescriptor) throws -> Data {
            let parts = descriptor.file.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.count <= 32 else { throw PreviewError.assetDecode }
            var parent = spriteRoot
            for part in parts.dropLast() { parent = try parent.child(part) }
            let data = try parent.read(parts.last!, maximum: 16 * 1024 * 1024)
            guard data.count == descriptor.bytes, OriginalSource(bytes: data).sha256 == descriptor.sha256 else {
                throw PreviewError.assetDecode
            }
            return data
        }
        database = try read(selection.renderDb)
        frames = try JSONDecoder().decode(FrameDatabase.self, from: database).frames
        guard frames.count <= 100_000 else { throw PreviewError.assetDecode }
        for frame in frames {
            guard descriptors.indices.contains(frame.a),
                [
                    frame.x, frame.y, frame.w, frame.h, frame.ox, frame.oy, frame.sw, frame.sh, frame.packedWidth,
                    frame.packedHeight,
                ].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 32768 }),
                frame.w > 0, frame.h > 0, frame.sw > 0, frame.sh > 0,
                frame.x + frame.packedWidth <= Double(descriptors[frame.a].w),
                frame.y + frame.packedHeight <= Double(descriptors[frame.a].h)
            else { throw PreviewError.assetDecode }
        }
        if let descriptor = manifest.fonts.first {
            let bytes = try read(descriptor)
            guard let provider = CGDataProvider(data: bytes as CFData), let loaded = CGFont(provider) else {
                throw PreviewError.assetDecode
            }
            font = loaded
        } else {
            font = nil
        }
    }

    func atlas(_ index: Int) throws -> CGImage {
        guard descriptors.indices.contains(index) else { throw PreviewError.assetDecode }
        tick += 1
        if let cached = images[index] {
            images[index] = (cached.image, tick, cached.bytes)
            return cached.image
        }
        let descriptor = descriptors[index]
        guard descriptor.w > 0, descriptor.h > 0, descriptor.w <= 16384, descriptor.h <= 16384,
            descriptor.w * descriptor.h <= 16_777_216
        else { throw PreviewError.assetDecode }
        let bytes = descriptor.w * descriptor.h * 4
        while decodedBytes + bytes > cacheLimit, let victim = images.min(by: { $0.value.tick < $1.value.tick }) {
            decodedBytes -= victim.value.bytes
            images.removeValue(forKey: victim.key)
        }
        // The prepared profile has flat atlas filenames. Refuse any unexpected traversal.
        guard !descriptor.file.contains("/"), !descriptor.file.hasPrefix(".") else { throw PreviewError.assetDecode }
        let data = try root.read(descriptor.file, maximum: 64 * 1024 * 1024)
        guard data.count == descriptor.bytes, OriginalSource(bytes: data).sha256 == descriptor.sha256,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            properties[kCGImagePropertyPixelWidth] as? Int == descriptor.w,
            properties[kCGImagePropertyPixelHeight] as? Int == descriptor.h,
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
            image.width == descriptor.w, image.height == descriptor.h
        else { throw PreviewError.assetDecode }
        images[index] = (image, tick, bytes)
        decodedBytes += bytes
        atlasDecodes += 1
        return image
    }

    func crop(_ index: Int) throws -> CGImage {
        guard frames.indices.contains(index) else { throw PreviewError.assetDecode }
        let frame = frames[index]
        guard
            let cropped = try atlas(frame.a).cropping(
                to: CGRect(x: frame.x, y: frame.y, width: frame.packedWidth, height: frame.packedHeight)),
            let copy = try makeBitmap(width: cropped.width, height: cropped.height).mapImage(cropped)
        else { throw PreviewError.assetDecode }
        return copy
    }
}

func makeBitmap(width: Int, height: Int) throws -> CGContext {
    guard width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 16_777_216,
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    else { throw PreviewError.imageAllocation }
    context.interpolationQuality = .none
    return context
}

extension CGContext {
    func mapImage(_ image: CGImage) -> CGImage? {
        draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return makeImage()
    }
}
