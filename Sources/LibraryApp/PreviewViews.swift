import AppKit
import LibraryCore
import SwiftUI

/// The selected blueprint, planner, or book entry a preview can show.
public struct PreviewTarget: Equatable, Sendable {
    public let subject: PreviewSubject
    public let kind: ItemKind
    public let name: String
}

extension LibraryBrowserModel {
    /// The single selected blueprint or planner, or the selected entry inside an open book; nil for folders, books,
    /// and several rows (PRV-1: books show no rendered preview).
    public var previewTarget: PreviewTarget? {
        guard let library = session.libraryURL?.path else { return nil }
        if let book, !isFiltering {
            guard selection.count == 1, let row = selectedRows.first, let path = row.entryPath, row.kind != .book
            else { return nil }
            return PreviewTarget(
                subject: PreviewSubject(libraryPath: library, itemId: book.itemId, entryPath: path), kind: row.kind,
                name: row.name)
        }
        guard let item = selectedItem, ItemKind(stored: item.kind) != .book else { return nil }
        return PreviewTarget(
            subject: PreviewSubject(libraryPath: library, itemId: item.id, entryPath: []),
            kind: ItemKind(stored: item.kind), name: item.name)
    }
}

/// What a preview draws behind the image (PRV-8a). The choice belongs to one view and is not saved.
public enum PreviewBackground: Equatable {
    case checkerboard
    case transparent
    case solid(NSColor)
}

/// One preview area or window: its viewer, zoom and pan, and background. The View menu acts on the focused one.
@MainActor @Observable
public final class PreviewDisplay {
    public let viewer = PreviewViewer()
    public private(set) var viewport: PreviewViewport?
    public var background: PreviewBackground = .checkerboard
    @ObservationIgnored private var viewSize: CGSize = .zero
    @ObservationIgnored private var image: PreviewImage?
    @ObservationIgnored weak var center: PreviewCenter?

    public init() {}

    /// Follows the viewer's state: a new image fits, a re-render of the same entry keeps zoom and pan.
    func stateChanged() {
        guard case .ready(let image) = viewer.state else { return }
        guard image != self.image else { return }
        self.image = image
        if var viewport {
            viewport.replaceImage(size: image.pointSize)
            self.viewport = viewport
        } else {
            viewport = PreviewViewport(imageSize: image.pointSize, viewSize: viewSize)
        }
    }

    /// A different entry starts fitted again.
    func subjectChanged() {
        image = nil
        viewport = nil
    }

    func resize(to size: CGSize) {
        viewSize = size
        guard var viewport, viewport.viewSize != size else { return }
        viewport.resize(to: size)
        self.viewport = viewport
    }

    func update(_ viewport: PreviewViewport) { self.viewport = viewport }

    var canZoom: Bool {
        if case .ready = viewer.state { return viewport != nil }
        return false
    }

    var canRetry: Bool {
        if case .failed = viewer.state { return true }
        return false
    }

    func change(_ body: (inout PreviewViewport) -> Void) {
        guard canZoom, var viewport else { return }
        body(&viewport)
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .default) {
            self.viewport = viewport
        }
    }

    func zoomIn() { change { $0.zoomIn() } }
    func zoomOut() { change { $0.zoomOut() } }
    func actualSize() { change { $0.actualSize() } }
    func fit() { change { $0.fit() } }
    func retry() { center?.retry(viewer) }

    func chooseSolidColor() {
        SolidColorPicker.shared.choose(for: self)
    }
}

/// The shared color panel, pointed at the preview that asked for it.
@MainActor
private final class SolidColorPicker: NSObject {
    static let shared = SolidColorPicker()
    private weak var display: PreviewDisplay?

    func choose(for display: PreviewDisplay) {
        self.display = display
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        if case .solid(let color) = display.background { panel.color = color }
        panel.showsAlpha = false
        panel.orderFront(nil)
        display.background = .solid(panel.color)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        display?.background = .solid(panel.color)
    }
}

extension FocusedValues {
    /// The preview the View menu's zoom, background, and retry commands act on.
    @Entry var previewDisplay: PreviewDisplay?
}

/// The image over its background, with the state panel when there is no image (screen specs, "Previews").
struct PreviewArea: View {
    let display: PreviewDisplay
    let name: String
    /// Close Window, for a preview window whose item or entry is gone.
    var closeWindow: (() -> Void)?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            PreviewCanvas(
                image: readyImage, viewport: display.viewport, background: display.background, name: name,
                onViewport: { display.update($0) }, onResize: { display.resize(to: $0) })
            if let panel {
                panel
                    .padding(14)
                    .frame(maxWidth: 360)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(12)
                    .accessibilityElement(children: .contain)
            }
        }
        .onChange(of: display.viewer.state, initial: true) { _, state in
            display.stateChanged()
            if let announcement = Self.announcement(for: state) {
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
    }

    private var readyImage: CGImage? {
        if case .ready(let image) = display.viewer.state { return image.image }
        return nil
    }

    private var panel: AnyView? {
        switch display.viewer.state {
        case .none, .checking, .ready:
            return nil
        case .noAssets:
            return AnyView(
                VStack(spacing: 8) {
                    Text("No asset release is configured. Previews need one.").multilineTextAlignment(.center)
                    Button("Open Settings…") { openSettings() }
                })
        case .assetsUnusable(let message):
            return AnyView(
                VStack(spacing: 8) {
                    Text("The asset release can't be used: \(Self.reason(message)).").multilineTextAlignment(.center)
                    Button("Open Settings…") { openSettings() }
                })
        case .waiting:
            return AnyView(Text("Waiting to render…"))
        case .rendering:
            return AnyView(
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Rendering…")
                })
        case .nothingToDraw:
            return AnyView(Text("This blueprint has no entities or tiles.").multilineTextAlignment(.center))
        case .failed(let message):
            return AnyView(
                VStack(spacing: 8) {
                    Text("The preview couldn't be rendered").font(.headline)
                    Text(
                        message.title == "The preview couldn't be rendered"
                            ? message.guidance : "\(message.title). \(message.guidance)"
                    )
                    .multilineTextAlignment(.center)
                    Button("Retry") { display.retry() }
                })
        case .deleted(let entry):
            return AnyView(
                VStack(spacing: 8) {
                    Text(entry ? "This entry is no longer in the book." : "This item was deleted.")
                    if let closeWindow { Button("Close Window", action: closeWindow) }
                })
        }
    }

    /// The release problem as a clause: its title without a trailing period, starting lowercase.
    private static func reason(_ message: LibraryMessage) -> String {
        var text = message.title
        if text.hasSuffix(".") { text.removeLast() }
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func announcement(for state: PreviewState) -> String? {
        switch state {
        case .waiting: "Waiting to render"
        case .rendering: "Rendering preview"
        case .ready: "Preview ready"
        case .failed: "The preview couldn't be rendered"
        case .nothingToDraw: "This blueprint has no entities or tiles"
        default: nil
        }
    }
}

/// The inspector's fixed-height preview region (screen specs, "Inspector").
struct InspectorPreview: View {
    let browser: LibraryBrowserModel
    let center: PreviewCenter
    let assetsRevision: Int
    /// The image area's height; the inspector shrinks it in short windows.
    var height: CGFloat = 200
    @State private var display = PreviewDisplay()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let target = browser.previewTarget
        VStack(alignment: .leading, spacing: 6) {
            PreviewArea(display: display, name: target?.name ?? "")
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            if let target {
                Button("Open in Window") {
                    openWindow(id: LibraryAppIdentity.previewWindow, value: target.subject)
                }
                .controlSize(.small)
                .help("Open this preview in its own window (⌘Y)")
            }
        }
        .focusedSceneValue(\.previewDisplay, display)
        .onChange(
            of: PreviewRequestKey(target: target?.subject, browser: browser, revision: assetsRevision), initial: true
        ) {
            old, new in
            if old.subject != new.subject { display.subjectChanged() }
            display.center = center
            center.show(target?.subject, in: display.viewer)
        }
        .onDisappear { center.release(display.viewer) }
    }
}

/// Everything that makes a preview ask again: the entry, its source, the release, and whether the library is
/// listed (PRV-11, SET-5a).
struct PreviewRequestKey: Equatable {
    let subject: PreviewSubject?
    let sourceSha256: String?
    let revision: Int
    let listed: Bool

    @MainActor init(target subject: PreviewSubject?, browser: LibraryBrowserModel, revision: Int) {
        self.subject = subject
        sourceSha256 = subject.flatMap { subject in
            browser.listing?.items.first(where: { $0.id == subject.itemId })?.metadata.sourceSha256
        }
        self.revision = revision
        listed = browser.listing != nil
    }
}

/// A separate window showing one entry, for side-by-side comparison (PRV-3, PRV-4, PRV-11, PRV-13).
struct PreviewWindowView: View {
    let model: LibrarySelectionModel
    let subject: PreviewSubject?
    @State private var display = PreviewDisplay()
    @State private var lastName = ""
    @Environment(\.dismiss) private var dismiss

    private var item: LibraryCore.LibraryItem? {
        guard let subject else { return nil }
        return model.session.listing?.items.first { $0.id == subject.itemId }
    }

    private var title: String {
        let name = item?.name ?? lastName
        guard let subject, !subject.entryPath.isEmpty else { return name }
        return "\(name) — Entry \(BlueprintEntryReader.pathText(subject.entryPath))"
    }

    var body: some View {
        PreviewArea(display: display, name: title, closeWindow: { dismiss() })
            .frame(minWidth: 360, minHeight: 280)
            .navigationTitle(title)
            .toolbar { PreviewToolbar(display: display) }
            .focusedSceneValue(\.previewDisplay, display)
            .onChange(
                of: PreviewRequestKey(target: subject, browser: model.browser, revision: model.assets.revision),
                initial: true
            ) {
                display.center = model.previews
                model.previews.show(subject, in: display.viewer)
            }
            .onChange(of: item?.name, initial: true) { _, name in
                if let name { lastName = name }
            }
            .onChange(of: model.session.libraryURL, initial: true) { _, url in
                // Preview windows belong to one library and close with it.
                if url?.path != subject?.libraryPath { dismiss() }
            }
            .onDisappear { model.previews.release(display.viewer) }
    }
}

/// Zoom out, zoom percentage, zoom in, Fit, Actual Size, and Background (screen specs, "Preview window").
struct PreviewToolbar: ToolbarContent {
    let display: PreviewDisplay

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { display.zoomOut() }
                .help("Zoom Out (⌘−)")
                .disabled(!display.canZoom)
            Text(display.canZoom ? "\(display.viewport?.percentage ?? 100)%" : "–")
                .monospacedDigit()
                .frame(minWidth: 48)
                .accessibilityLabel("Zoom \(display.viewport?.percentage ?? 100) percent")
            Button("Zoom In", systemImage: "plus.magnifyingglass") { display.zoomIn() }
                .help("Zoom In (⌘+)")
                .disabled(!display.canZoom)
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { display.fit() }
                .help("Zoom to Fit (⌘9)")
                .disabled(!display.canZoom)
            Button("Actual Size", systemImage: "1.magnifyingglass") { display.actualSize() }
                .help("Actual Size (⌘0)")
                .disabled(!display.canZoom)
            BackgroundMenu(display: display)
        }
    }
}

/// Checkerboard (the default), Transparent, or a solid color (PRV-8a).
struct BackgroundMenu: View {
    let display: PreviewDisplay

    var body: some View {
        Menu {
            Toggle("Checkerboard", isOn: binding(.checkerboard))
            Toggle("Transparent", isOn: binding(.transparent))
            Button("Solid Color…") { display.chooseSolidColor() }
        } label: {
            Label("Background", systemImage: "square.fill.on.square.fill")
        }
        .help("Background")
    }

    private func binding(_ choice: PreviewBackground) -> Binding<Bool> {
        Binding(get: { display.background == choice }, set: { if $0 { display.background = choice } })
    }
}

/// View menu items for the focused preview (screen specs, "Menus and shortcuts").
struct PreviewCommands: Commands {
    @FocusedValue(\.previewDisplay) private var display

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { display?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(display?.canZoom != true)
            Button("Zoom Out") { display?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(display?.canZoom != true)
            Button("Actual Size") { display?.actualSize() }
                .keyboardShortcut("0")
                .disabled(display?.canZoom != true)
            Button("Zoom to Fit") { display?.fit() }
                .keyboardShortcut("9")
                .disabled(display?.canZoom != true)
            Menu("Background") {
                Button("Checkerboard") { display?.background = .checkerboard }
                Button("Transparent") { display?.background = .transparent }
                Button("Solid Color…") { display?.chooseSolidColor() }
            }
            .disabled(display == nil)
            Divider()
            Button("Retry Preview") { display?.retry() }
                .keyboardShortcut("r")
                .disabled(display?.canRetry != true)
        }
    }
}

/// Draws the background and the image, and turns scroll, pinch, drag, double-click, and arrow keys into zoom and
/// pan (screen specs, "Preview window").
struct PreviewCanvas: NSViewRepresentable {
    let image: CGImage?
    let viewport: PreviewViewport?
    let background: PreviewBackground
    let name: String
    let onViewport: (PreviewViewport) -> Void
    let onResize: (CGSize) -> Void

    func makeNSView(context: Context) -> PreviewCanvasView { PreviewCanvasView() }

    func updateNSView(_ view: PreviewCanvasView, context: Context) {
        view.onViewport = onViewport
        view.onResize = onResize
        view.configure(image: image, viewport: viewport, background: background, name: name)
    }
}

final class PreviewCanvasView: NSView {
    var onViewport: ((PreviewViewport) -> Void)?
    var onResize: ((CGSize) -> Void)?
    private var image: CGImage?
    private var viewport: PreviewViewport?
    private var background: PreviewBackground = .checkerboard
    private var dragStart: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }

    func configure(image: CGImage?, viewport: PreviewViewport?, background: PreviewBackground, name: String) {
        let changed = image !== self.image || viewport != self.viewport || background != self.background
        self.image = image
        self.viewport = viewport
        self.background = background
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(image == nil ? "Preview" : "Preview of \(name)")
        if changed { needsDisplay = true }
        if viewport != nil, viewport?.viewSize != bounds.size { onResize?(bounds.size) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?(newSize)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        switch background {
        case .checkerboard:
            NSColor.checkerboardTiles.0.setFill()
            bounds.fill()
            NSColor.checkerboardTiles.1.setFill()
            let tile: CGFloat = 8
            var path = [NSRect]()
            let rows = Int((dirtyRect.maxY / tile).rounded(.up))
            let columns = Int((dirtyRect.maxX / tile).rounded(.up))
            for row in max(0, Int(dirtyRect.minY / tile))..<max(rows, 0) {
                for column in max(0, Int(dirtyRect.minX / tile))..<max(columns, 0) where (row + column) % 2 == 1 {
                    path.append(NSRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
                }
            }
            NSGraphicsContext.current?.cgContext.fill(path)
        case .transparent:
            NSColor.contentBackground.setFill()
            bounds.fill()
        case .solid(let color):
            color.setFill()
            bounds.fill()
        }
        guard let image, let viewport, let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = viewport.imageFrame
        context.saveGState()
        // Device pixels per image pixel: above one, keep the pixels sharp instead of smoothing them.
        let backing = window?.backingScaleFactor ?? 2
        context.interpolationQuality = viewport.scale * backing / 2 > 1.5 ? .none : .high
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: frame.size))
        context.restoreGState()
    }

    private func change(_ body: (inout PreviewViewport) -> Void) {
        guard var viewport else { return }
        body(&viewport)
        self.viewport = viewport
        needsDisplay = true
        onViewport?(viewport)
    }

    override func scrollWheel(with event: NSEvent) {
        guard viewport != nil else { return super.scrollWheel(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard delta != 0 else { return }
        change { $0.zoom(to: $0.scale * exp(delta * 0.01), around: point) }
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        change { $0.zoom(to: $0.scale * (1 + event.magnification), around: point) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            change { $0.toggleFit() }
            dragStart = nil
        } else {
            dragStart = convert(event.locationInWindow, from: nil)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        change { $0.pan(by: CGSize(width: point.x - start.x, height: point.y - start.y)) }
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }

    override func keyDown(with event: NSEvent) {
        let page = event.modifierFlags.contains(.option)
        let direction: (x: CGFloat, y: CGFloat)? =
            switch event.keyCode {
            case 123: (-1, 0)
            case 124: (1, 0)
            case 125: (0, 1)
            case 126: (0, -1)
            default: nil
            }
        guard let direction, viewport != nil else { return super.keyDown(with: event) }
        change { $0.pan(direction: direction, page: page) }
    }
}
