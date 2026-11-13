import CoreGraphics
import Foundation
import Testing

@testable import PreviewRenderer

private struct TestFrames: FrameSource {
    let frames: [SpriteFrame]
    let font = CGFont("Helvetica" as CFString)
    let bitmap: CGImage
    init() throws {
        frames = try JSONDecoder().decode(
            [SpriteFrame].self,
            from: Data("[{\"a\":0,\"x\":0,\"y\":0,\"w\":2,\"h\":2,\"ox\":0,\"oy\":0,\"sw\":2,\"sh\":2}]".utf8))
        let rgba = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])
        bitmap = try #require(
            CGImage(
                width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: CGDataProvider(data: rgba as CFData)!, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent))
    }
    func crop(_ index: Int) throws -> CGImage { bitmap }
}
private func command(_ kind: String, _ fields: [String: Any] = [:]) throws -> DrawCommand {
    var value: [String: Any] = ["kind": kind, "layer": 39, "sortX": 0, "sortY": 0, "entity": 0, "sub": 0]
    value.merge(fields) { _, new in new }
    return try JSONDecoder().decode(DrawCommand.self, from: JSONSerialization.data(withJSONObject: value))
}
private func paint(_ commands: [DrawCommand], maximum: Int = 256) throws -> CGImage {
    let list = DrawList(schema: 1, bounds: DrawBounds(minX: 0, minY: 0, maxX: 2, maxY: 2), commands: commands)
    return try NativePainter(source: TestFrames(), list: list, maximumDimension: maximum, checkerboard: false).paint(
        list)
}
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let bytes = try #require(image.dataProvider?.data) as Data
    let index = y * image.bytesPerRow + x * 4
    return Array(bytes[index..<index + 4])
}

@Suite("Native image composition")
struct NativePainterTests {
    @Test("Top-left geometry and sprite pixels survive flips and clockwise rotation")
    func orientation() throws {
        let base: [String: Any] = ["frame": 0, "x": 0, "y": 0, "w": 2, "h": 2]
        let original = try paint([command("sprite", base)])
        #expect(try pixel(original, 40, 40) == [255, 0, 0, 255])
        #expect(try pixel(original, 80, 40) == [0, 255, 0, 255])
        #expect(try pixel(original, 40, 80) == [0, 0, 255, 255])
        var flipped = base
        flipped["flipX"] = true
        #expect(try pixel(paint([command("sprite", flipped)]), 40, 40) == [0, 255, 0, 255])
        var rotated = base
        rotated["rotation"] = 90
        #expect(try pixel(paint([command("sprite", rotated)]), 40, 40) == [0, 0, 255, 255])
    }

    @Test("Ordered rectangles retain transparent gutters")
    func ordering() throws {
        let image = try paint([
            command("rect", ["x": 0, "y": 0, "w": 2, "h": 2, "color": [1, 0, 0, 1]]),
            command("rect", ["x": 1, "y": 0, "w": 1, "h": 1, "color": [0, 1, 0, 1]]),
        ])
        #expect(try pixel(image, 40, 40) == [255, 0, 0, 255])
        #expect(try pixel(image, 80, 40) == [0, 255, 0, 255])
        #expect(try pixel(image, 5, 5) == [0, 0, 0, 0])
    }

    @Test("Shadow overlap flattens once before applying fifty percent alpha")
    func shadows() throws {
        let shadow = try command("sprite", ["frame": 0, "x": 0, "y": 0, "w": 2, "h": 2, "shadow": true])
        let image = try paint([shadow, shadow])
        #expect(try (126...129).contains(Int(pixel(image, 40, 40)[3])))
    }

    @Test("Destination clipping, canonical source slices, and multiply tint preserve alpha")
    func clippingAndTint() throws {
        let clipped = try paint([
            command("sprite", ["frame": 0, "x": 0, "y": 0, "w": 2, "h": 2, "clip": ["x": 0, "y": 0, "w": 1, "h": 2]])
        ])
        #expect(try pixel(clipped, 40, 40)[3] == 255)
        #expect(try pixel(clipped, 80, 40)[3] == 0)
        let slice = try paint([
            command("sprite", ["frame": 0, "x": 0, "y": 0, "w": 1, "h": 2, "src": ["x": 0, "y": 0, "w": 1, "h": 2]])
        ])
        #expect(try pixel(slice, 40, 40) == [255, 0, 0, 255])
        #expect(try pixel(slice, 80, 40)[3] == 0)
        let tint = try paint([command("sprite", ["frame": 0, "x": 0, "y": 0, "w": 2, "h": 2, "tint": [0.5, 1, 0, 1]])])
        #expect(try (126...129).contains(Int(pixel(tint, 40, 40)[0])))
        #expect(try pixel(tint, 40, 40)[3] == 255)
    }

    @Test("Wires, chain joints, dashed grid, icons, and Core Text produce visible pixels")
    func overlays() throws {
        let images = try [
            paint([command("wire", ["wire": "red", "x1": 0, "y1": 0, "x2": 2, "y2": 2])]),
            paint([
                command(
                    "train-chain", ["segments": [["x1": 0, "y1": 0, "x2": 2, "y2": 2]], "joints": [["x": 1, "y": 1]]])
            ]),
            paint([command("snap-grid", ["x": 0, "y": 0, "w": 2, "h": 2])]),
            paint([command("icon", ["frame": 0, "x": 1, "y": 1, "size": 1, "backing": true])]),
            paint([command("text", ["text": "Native", "x": 0, "y": 0, "size": 0.5, "color": [1, 1, 1, 1]])]),
        ]
        for image in images {
            let data = try #require(image.dataProvider?.data) as Data
            #expect(stride(from: 3, to: data.count, by: 4).contains { data[$0] > 0 })
        }
    }

    @Test("Unknown commands, invalid frames, nonfinite geometry, and excessive output are refused")
    func admission() throws {
        #expect(throws: PreviewError.self) { try paint([command("future-kind")]) }
        #expect(throws: PreviewError.self) {
            try paint([command("sprite", ["frame": 99, "x": 0, "y": 0, "w": 1, "h": 1])])
        }
        let list = DrawList(schema: 1, bounds: DrawBounds(minX: 0, minY: 0, maxX: .infinity, maxY: 2), commands: [])
        #expect(throws: PreviewError.self) {
            try NativePainter(source: TestFrames(), list: list, maximumDimension: 256, checkerboard: false)
        }
        #expect(throws: PreviewError.self) { try paint([], maximum: 8192) }
        #expect(try paint([], maximum: 64).width == 64)
    }
}
