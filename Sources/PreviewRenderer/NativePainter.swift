// Adapted from fpsr's Canvas2D backend (MIT). See tools/vendor/fpsr/LICENSE.
import CoreGraphics
import CoreText
import Foundation

/// Executes the pinned planner's ordered IR in a bounded sRGB bitmap.
final class NativePainter {
    let source: any FrameSource
    let context: CGContext
    let width: Int, height: Int
    let pixelsPerTile: Double
    let originX: Double, originY: Double
    private var images: [String: (CGImage, Int, Int)] = [:]
    private var imageBytes = 0, tick = 0
    private let imageLimit = 64 * 1024 * 1024

    init(source: any FrameSource, list: DrawList, maximumDimension: Int, checkerboard: Bool) throws {
        try list.bounds.validate()
        guard (64...4096).contains(maximumDimension), list.commands.count <= 250_000 else {
            throw PreviewError.invalidInput
        }
        for command in list.commands { try command.validate(frames: source.frames.count) }
        self.source = source
        originX = 1 - floor(list.bounds.minX)
        originY = 1 - floor(list.bounds.minY)
        let tilesWide = max(1, ceil(list.bounds.maxX) + 1 + originX)
        let tilesHigh = max(1, ceil(list.bounds.maxY) + 1 + originY)
        pixelsPerTile = min(32, Double(maximumDimension) / max(tilesWide, tilesHigh))
        width = max(1, Int(ceil(tilesWide * pixelsPerTile - 1e-9)))
        height = max(1, Int(ceil(tilesHigh * pixelsPerTile - 1e-9)))
        context = try makeBitmap(width: width, height: height)
        context.translateBy(x: 0, y: Double(height))
        context.scaleBy(x: 1, y: -1)
        if checkerboard {
            for y in stride(from: 0, to: height, by: 16) {
                for x in stride(from: 0, to: width, by: 16) {
                    let grey = (x / 16 + y / 16).isMultiple(of: 2) ? 0.19 : 0.23
                    context.setFillColor(CGColor(srgbRed: grey, green: grey, blue: grey, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 16, height: 16))
                }
            }
        }
    }

    func paint(_ list: DrawList) throws -> CGImage {
        var index = 0
        while index < list.commands.count {
            let command = list.commands[index]
            if command.kind == "sprite", command.shadow == true {
                context.saveGState()
                context.setAlpha(0.5)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                while index < list.commands.count, list.commands[index].kind == "sprite",
                    list.commands[index].shadow == true
                {
                    try sprite(list.commands[index])
                    index += 1
                }
                context.endTransparencyLayer()
                context.restoreGState()
            } else {
                try draw(command)
                index += 1
            }
        }
        guard let image = context.makeImage() else { throw PreviewError.imageAllocation }
        return image
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(
            x: (x + originX) * pixelsPerTile, y: (y + originY) * pixelsPerTile, width: w * pixelsPerTile,
            height: h * pixelsPerTile)
    }

    private func color(_ rgba: [Double]) -> CGColor {
        CGColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    }

    private func image(_ key: String, create: () throws -> CGImage) throws -> CGImage {
        tick += 1
        if let cached = images[key] {
            images[key] = (cached.0, tick, cached.2)
            return cached.0
        }
        let value = try create()
        let bytes = value.width * value.height * 4
        guard bytes <= imageLimit else { throw PreviewError.imageAllocation }
        while imageBytes + bytes > imageLimit, let victim = images.min(by: { $0.value.1 < $1.value.1 }) {
            imageBytes -= victim.value.2
            images.removeValue(forKey: victim.key)
        }
        images[key] = (value, tick, bytes)
        imageBytes += bytes
        return value
    }

    private func crop(_ index: Int) throws -> CGImage { try image("frame-\(index)") { try source.crop(index) } }

    private func blit(_ image: CGImage, to destination: CGRect) {
        guard destination.width > 0, destination.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: destination.minX, y: destination.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: destination.width, height: destination.height))
        context.restoreGState()
    }

    private func draw(_ command: DrawCommand) throws {
        context.saveGState()
        defer { context.restoreGState() }
        switch command.kind {
        case "sprite": try sprite(command)
        case "rect":
            context.setFillColor(color(command.color!))
            context.fill(rect(command.x!, command.y!, command.w!, command.h!))
        case "icon": try icon(command)
        case "wire":
            let colors: [String: [Double]] = [
                "copper": [207 / 255, 124 / 255, 0, 0.72], "red": [200 / 255, 55 / 255, 24 / 255, 0.72],
                "green": [88 / 255, 140 / 255, 56 / 255, 0.72],
            ]
            context.setStrokeColor(color(colors[command.wire!]!))
            context.setLineWidth(pixelsPerTile / 32)
            context.setLineCap(.round)
            let p1 = rect(command.x1!, command.y1!, 0, 0).origin
            let p2 = rect(command.x2!, command.y2!, 0, 0).origin
            context.move(to: p1)
            context.addQuadCurve(
                to: p2,
                control: CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 + 0.15 * hypot(p2.x - p1.x, p2.y - p1.y)))
            context.strokePath()
        case "train-chain":
            context.setStrokeColor(color([101 / 255, 128 / 255, 36 / 255, 0.95]))
            context.setLineWidth(3 * pixelsPerTile / 32)
            context.setLineCap(.round)
            for s in command.segments! {
                context.move(to: rect(s.x1, s.y1, 0, 0).origin)
                context.addLine(to: rect(s.x2, s.y2, 0, 0).origin)
                context.strokePath()
            }
            for p in command.joints! {
                let point = rect(p.x, p.y, 0, 0).origin
                let radius = 0.3 * pixelsPerTile
                context.strokeEllipse(
                    in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
            }
        case "snap-grid":
            let box = rect(command.x!, command.y!, command.w!, command.h!).insetBy(dx: 0.5, dy: 0.5)
            context.setLineDash(phase: 0, lengths: [10, 6].map { $0 * pixelsPerTile / 32 })
            let strokes: [([Double], Double)] = [([10 / 255.0, 61 / 255.0, 0, 1], 2.0), ([60 / 255.0, 1, 0, 1], 0.0)]
            for (rgba, extra) in strokes {
                context.setStrokeColor(color(rgba))
                context.setLineWidth(max(2, 3 * pixelsPerTile / 32) + extra)
                context.stroke(box)
            }
        case "text": try text(command)
        default: throw PreviewError.invalidDrawList
        }
    }

    private func sprite(_ command: DrawCommand) throws {
        context.saveGState()
        defer { context.restoreGState() }
        let frame = source.frames[command.frame!]
        var box = rect(command.x!, command.y!, command.w!, command.h!)
        let railLayers: Set<Double> = [15, 16, 17, 23, 24, 48, 49, 50, 51, 52]
        let rotation = command.rotation ?? 0
        if railLayers.contains(command.layer), rotation == 0 {
            box = CGRect(
                x: box.minX.rounded(), y: box.minY.rounded(), width: box.maxX.rounded() - box.minX.rounded(),
                height: box.maxY.rounded() - box.minY.rounded())
        }
        if let clip = command.clip { context.clip(to: rect(clip.x, clip.y, clip.w, clip.h)) }
        let src = command.src ?? DrawRect(x: 0, y: 0, w: frame.sw, h: frame.sh)
        guard src.w > 0, src.h > 0 else { return }
        let sx = box.width / src.w
        let sy = box.height / src.h
        var trimmed = CGRect(
            x: box.minX + (frame.ox - src.x) * sx, y: box.minY + (frame.oy - src.y) * sy, width: frame.w * sx,
            height: frame.h * sy)
        if command.src != nil { context.clip(to: box) }
        if rotation == 0, command.flipX != true, command.flipY != true, command.src == nil {
            trimmed = CGRect(
                x: trimmed.minX.rounded(), y: trimmed.minY.rounded(),
                width: trimmed.maxX.rounded() - trimmed.minX.rounded(),
                height: trimmed.maxY.rounded() - trimmed.minY.rounded())
        }
        var bitmap = try crop(command.frame!)
        if let tint = command.tint {
            bitmap = try image("tint-\(command.frame!)-\(tint)") {
                let scratch = try makeBitmap(width: bitmap.width, height: bitmap.height)
                scratch.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
                guard let data = scratch.data?.assumingMemoryBound(to: UInt8.self) else {
                    throw PreviewError.imageAllocation
                }
                for pixel in 0..<(bitmap.width * bitmap.height) {
                    for channel in 0..<3 {
                        data[pixel * 4 + channel] = UInt8(
                            (Double(data[pixel * 4 + channel]) * (1 - tint[3] + tint[3] * tint[channel])).rounded())
                    }
                }
                guard let result = scratch.makeImage() else { throw PreviewError.imageAllocation }
                return result
            }
        }
        if rotation != 0 || command.flipX == true || command.flipY == true {
            context.translateBy(x: box.midX, y: box.midY)
            context.rotate(by: rotation * .pi / 180)
            context.scaleBy(x: command.flipX == true ? -1 : 1, y: command.flipY == true ? -1 : 1)
            blit(bitmap, to: trimmed.offsetBy(dx: -box.midX, dy: -box.midY))
        } else {
            blit(bitmap, to: trimmed)
            if let seam = command.seamBleed, command.clip == nil, command.src == nil, command.tint == nil {
                let bands: [(Bool?, CGRect, Double, Double)] = [
                    (seam.top, CGRect(x: box.minX, y: box.minY - 2, width: box.width, height: 2), 0, -2),
                    (seam.right, CGRect(x: box.maxX, y: box.minY, width: 2, height: box.height), 2, 0),
                    (seam.bottom, CGRect(x: box.minX, y: box.maxY, width: box.width, height: 2), 0, 2),
                    (seam.left, CGRect(x: box.minX - 2, y: box.minY, width: 2, height: box.height), -2, 0),
                ]
                for (enabled, clip, dx, dy) in bands where enabled == true {
                    context.saveGState()
                    context.clip(to: clip)
                    blit(bitmap, to: trimmed.offsetBy(dx: dx, dy: dy))
                    context.restoreGState()
                }
            }
        }
    }

    private func icon(_ command: DrawCommand) throws {
        let frame = source.frames[command.frame!]
        let size = command.size! * pixelsPerTile
        let point = rect(command.x!, command.y!, 0, 0).origin
        let pin = command.backingStyle == "request-pin"
        if let backing = command.backingFrame {
            let f = source.frames[backing]
            let scale = size / (pin ? max(1, f.w * 44 / 48) : 32)
            context.saveGState()
            context.setAlpha(pin ? 1 : 0.16)
            blit(
                try crop(backing),
                to: CGRect(
                    x: point.x - f.sw * scale / 2 + f.ox * scale, y: point.y - f.sh * scale / 2 + f.oy * scale,
                    width: f.w * scale, height: f.h * scale))
            context.restoreGState()
        } else if command.backing == true {
            context.setFillColor(color([0, 0, 0, 0.6]))
            context.addPath(
                CGPath(
                    roundedRect: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                    cornerWidth: size * 0.15, cornerHeight: size * 0.15, transform: nil))
            context.fillPath()
        }
        let drawSize = pin ? size * 0.7 : size
        let center = CGPoint(x: point.x, y: point.y - (pin ? size * 0.1 : 0))
        let sx = drawSize / frame.sw
        let sy = drawSize / frame.sh
        var destination = CGRect(
            x: center.x - drawSize / 2 + frame.ox * sx, y: center.y - drawSize / 2 + frame.oy * sy, width: frame.w * sx,
            height: frame.h * sy)
        context.saveGState()
        defer { context.restoreGState() }
        if let rotation = command.rotation, rotation != 0 {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: rotation * .pi / 180)
            destination = destination.offsetBy(dx: -center.x, dy: -center.y)
        }
        if !pin && (command.backingFrame != nil || command.backing == true || command.silhouette == true) {
            let halo = try image("halo-\(command.frame!)") { try iconSilhouette(crop(command.frame!), frame: frame) }
            let padx = 28 * sx
            let pady = 28 * sy
            blit(halo, to: destination.insetBy(dx: -padx, dy: -pady))
        }
        blit(try crop(command.frame!), to: destination)
    }

    private func text(_ command: DrawCommand) throws {
        guard let graphicsFont = source.font else { throw PreviewError.assetDecode }
        let font = CTFontCreateWithGraphicsFont(graphicsFont, max(1, command.size! * pixelsPerTile), nil, nil)
        let attributed = NSAttributedString(
            string: command.text!,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(command.color!),
            ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let length = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let point = rect(command.x!, command.y!, 0, 0).origin
        let offset = command.align == "center" ? length / 2 : command.align == "right" ? length : 0
        let baseline = command.baseline ?? "top"
        let y = point.y + (baseline == "top" ? ascent : baseline == "middle" ? (ascent - descent) / 2 : 0)
        context.saveGState()
        context.translateBy(x: point.x - offset, y: y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
