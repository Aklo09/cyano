import CoreGraphics

/// Zoom and pan for one preview (PRV-8). Sizes are in points; `center` is the image point shown at the middle of
/// the view. While `fitting`, resizing the view fits the image again; zooming or panning ends it.
public struct PreviewViewport: Equatable, Sendable {
    public static let minimumScale: CGFloat = 0.05
    public static let maximumScale: CGFloat = 16
    /// Fit never enlarges a small image beyond this, so a tiny planner icon stays legible but not blurred.
    public static let maximumFitScale: CGFloat = 4
    public static let step: CGFloat = 1.25

    public private(set) var imageSize: CGSize
    public private(set) var viewSize: CGSize
    public private(set) var scale: CGFloat = 1
    public private(set) var center: CGPoint
    public private(set) var fitting = true

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        fit()
    }

    /// The image's frame in view coordinates (origin top left).
    public var imageFrame: CGRect {
        CGRect(
            x: viewSize.width / 2 - center.x * scale, y: viewSize.height / 2 - center.y * scale,
            width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Zoom as a whole percentage of Actual Size.
    public var percentage: Int { Int((scale * 100).rounded()) }

    public mutating func fit() {
        fitting = true
        center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            scale = 1
            return
        }
        let fitted = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        scale = Self.clamped(min(fitted, Self.maximumFitScale))
    }

    public mutating func actualSize() {
        zoom(to: 1, around: nil)
    }

    /// Fit and Actual Size alternate on double-click.
    public mutating func toggleFit() {
        if fitting && scale != 1 { actualSize() } else { fit() }
    }

    public mutating func zoomIn(around point: CGPoint? = nil) { zoom(to: scale * Self.step, around: point) }
    public mutating func zoomOut(around point: CGPoint? = nil) { zoom(to: scale / Self.step, around: point) }

    /// Zooms so the image point under `point` (view coordinates; nil for the middle) stays under it.
    public mutating func zoom(to newScale: CGFloat, around point: CGPoint?) {
        let target = Self.clamped(newScale)
        fitting = false
        guard target != scale else { return }
        let anchor = point ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let offset = CGPoint(x: anchor.x - viewSize.width / 2, y: anchor.y - viewSize.height / 2)
        let imagePoint = CGPoint(x: center.x + offset.x / scale, y: center.y + offset.y / scale)
        scale = target
        center = CGPoint(x: imagePoint.x - offset.x / scale, y: imagePoint.y - offset.y / scale)
        clampCenter()
    }

    /// Moves the image by `delta` view points (a drag to the right moves the image right).
    public mutating func pan(by delta: CGSize) {
        fitting = false
        center = CGPoint(x: center.x - delta.width / scale, y: center.y - delta.height / scale)
        clampCenter()
    }

    /// Arrow keys pan by 10% of the view, or by one screen with Option.
    public mutating func pan(direction: (x: CGFloat, y: CGFloat), page: Bool) {
        let fraction: CGFloat = page ? 1 : 0.1
        pan(
            by: CGSize(
                width: -direction.x * viewSize.width * fraction, height: -direction.y * viewSize.height * fraction))
    }

    /// Keeps the fit while fitting (PRV-8); otherwise keeps the zoom and the image point at the middle.
    public mutating func resize(to size: CGSize) {
        guard size != viewSize else { return }
        viewSize = size
        if fitting { fit() } else { clampCenter() }
    }

    /// A new image of the same entry (a re-render) keeps the zoom unless fitting.
    public mutating func replaceImage(size: CGSize) {
        guard size != imageSize else { return }
        imageSize = size
        if fitting { fit() } else { clampCenter() }
    }

    /// Keeps some of the image on screen: the middle of the view stays over the image.
    private mutating func clampCenter() {
        center = CGPoint(
            x: min(max(center.x, 0), imageSize.width), y: min(max(center.y, 0), imageSize.height))
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumScale), maximumScale)
    }
}
