// Adapted from fpsr's icon-silhouette.ts (MIT). See tools/vendor/fpsr/LICENSE.
import CoreGraphics
import Foundation

/// CPU alpha dilation and box blur matching the pinned renderer's 12px/16px halo.
func iconSilhouette(_ image: CGImage, frame: SpriteFrame) throws -> CGImage {
    let ratio = frame.packedWidth / frame.w
    let radius = max(1, Int((12 * ratio).rounded()))
    let blur = max(1, Int((16 * ratio).rounded()))
    let pad = max(1, Int((28 * ratio).rounded()))
    let w = image.width + 2 * pad
    let h = image.height + 2 * pad
    guard w * h <= 1_048_576 else { throw PreviewError.imageAllocation }
    let scratch = try makeBitmap(width: w, height: h)
    scratch.draw(image, in: CGRect(x: pad, y: pad, width: image.width, height: image.height))
    guard let rgba = scratch.data?.assumingMemoryBound(to: UInt8.self) else { throw PreviewError.imageAllocation }
    var alpha = (0..<(w * h)).map { rgba[$0 * 4 + 3] }
    func dilate(_ input: [UInt8], horizontal: Bool) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: w * h)
        let length = horizontal ? w : h
        let rows = horizontal ? h : w
        for row in 0..<rows {
            var deque = [Int](repeating: 0, count: length)
            var head = 0
            var tail = 0
            var next = 0
            func at(_ index: Int) -> Int { horizontal ? row * w + index : index * w + row }
            for position in 0..<length {
                while next <= min(length - 1, position + radius) {
                    while tail > head && input[at(deque[tail - 1])] <= input[at(next)] { tail -= 1 }
                    deque[tail] = next
                    tail += 1
                    next += 1
                }
                while tail > head && deque[head] < position - radius { head += 1 }
                output[at(position)] = input[at(deque[head])]
            }
        }
        return output
    }
    alpha = dilate(dilate(alpha, horizontal: true), horizontal: false)
    let stride = w + 1
    var integral = [UInt64](repeating: 0, count: (w + 1) * (h + 1))
    for y in 0..<h {
        var row: UInt64 = 0
        for x in 0..<w {
            row += UInt64(alpha[y * w + x])
            integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
        }
    }
    for y in 0..<h {
        let top = max(0, y - blur)
        let bottom = min(h - 1, y + blur)
        for x in 0..<w {
            let left = max(0, x - blur)
            let right = min(w - 1, x + blur)
            let sum =
                integral[(bottom + 1) * stride + right + 1] + integral[top * stride + left]
                - integral[top * stride + right + 1] - integral[(bottom + 1) * stride + left]
            let i = (y * w + x) * 4
            rgba[i] = 0
            rgba[i + 1] = 0
            rgba[i + 2] = 0
            rgba[i + 3] = UInt8(sum / UInt64((right - left + 1) * (bottom - top + 1)))
        }
    }
    guard let result = scratch.makeImage() else { throw PreviewError.imageAllocation }
    return result
}
