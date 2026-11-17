import CoreGraphics
import Foundation
import ImageIO
import LibraryCore
import Observation
import PreviewRenderer

/// What a preview shows: one entry of a saved item ([] is the root) in one library. Windows are keyed by it, so
/// a renamed or replaced item keeps its window (PRV-4, PRV-11).
public struct PreviewSubject: Codable, Hashable, Sendable {
    public let libraryPath: String
    public let itemId: String
    public let entryPath: [Int]

    public init(libraryPath: String, itemId: String, entryPath: [Int]) {
        self.libraryPath = libraryPath
        self.itemId = itemId
        self.entryPath = entryPath
    }
}

/// A decoded preview with its render report's warnings. The renderer paints the 2x tier, so two pixels make one
/// point at Actual Size.
public struct PreviewImage: @unchecked Sendable, Equatable {
    public let image: CGImage
    /// The planner's warnings, as rendered or as stored with a cached preview (WRN-1).
    public let warnings: [String]
    /// The PNG bytes as rendered and cached, which Copy Image and Save Image As hand out unchanged (IMG-1, IMG-2).
    public let png: Data?
    private let id = UUID()

    public init(image: CGImage, warnings: [String] = [], png: Data? = nil) {
        self.image = image
        self.warnings = warnings
        self.png = png
    }

    public var pointSize: CGSize { CGSize(width: Double(image.width) / 2, height: Double(image.height) / 2) }

    public static func == (a: PreviewImage, b: PreviewImage) -> Bool { a.id == b.id }

    /// Decodes PNG bytes the renderer or the cache produced.
    public static func decode(_ png: Data, warnings: [String] = []) throws -> PreviewImage {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw PreviewError.imageEncoding }
        return PreviewImage(image: image, warnings: warnings, png: png)
    }
}

/// A render report's warnings for display: one line per distinct text with its count, most frequent first, at most
/// `limit` lines (WRN-1, WRN-2). Reports may hold up to 100,000 warnings.
public struct RenderWarnings: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let text: String
        public let count: Int
    }

    /// Every warning in the report.
    public let total: Int
    public let lines: [Line]
    /// Distinct texts beyond `lines`.
    public let more: Int

    public init(_ warnings: [String], limit: Int = 100) {
        var counts: [String: Int] = [:]
        for warning in warnings { counts[warning, default: 0] += 1 }
        let sorted = counts.map { Line(text: $0.key, count: $0.value) }.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text
        }
        total = warnings.count
        lines = Array(sorted.prefix(limit))
        more = max(0, sorted.count - limit)
    }

    /// "1 warning", "3 warnings".
    public var summary: String { total == 1 ? "1 warning" : "\(total.formatted()) warnings" }
}

/// What a preview area or window shows (screen specs, "Previews").
public enum PreviewState: Equatable, Sendable {
    /// Nothing to preview: no selection, a folder, or a book.
    case none
    case noAssets
    case assetsUnusable(LibraryMessage)
    /// Checking the cache or the asset release; shows nothing, so cache hits never flash a state (PRV-2).
    case checking
    case waiting
    case rendering
    case ready(PreviewImage)
    case nothingToDraw
    case failed(LibraryMessage)
    /// The item (`entry` false) or the book entry (`entry` true) no longer exists (PRV-11).
    case deleted(entry: Bool)
}

/// One entry to render, for one source and one verified release.
public struct PreviewJob: Hashable, Sendable {
    public let itemId: String
    public let entryPath: [Int]
    public let sourceSha256: String
    public let assetsURL: URL
    public let assetIdentity: String
}

public enum PreviewLookup: Sendable {
    case cached(PreviewImage)
    case nothingToDraw
    case needsRender
}

enum PreviewBackendError: Error {
    /// The app bundle does not carry `preview-worker`.
    case workerMissing
}

/// How previews are looked up and rendered; tests substitute a backend that never starts a worker.
public struct PreviewBackend: Sendable {
    /// Serves the entry from the cache, says there is nothing to draw, or asks for a render. Never starts a worker.
    public var lookup: @Sendable (NativeLibrary, PreviewJob) throws -> PreviewLookup
    /// Renders the entry with at most one worker (or serves it from the cache if it was published meanwhile).
    public var render: @Sendable (NativeLibrary, PreviewJob, PreviewCancellation) throws -> PreviewImage

    public init(
        lookup: @escaping @Sendable (NativeLibrary, PreviewJob) throws -> PreviewLookup,
        render: @escaping @Sendable (NativeLibrary, PreviewJob, PreviewCancellation) throws -> PreviewImage
    ) {
        self.lookup = lookup
        self.render = render
    }

    /// The bundled worker in the app's Contents/MacOS, next to the app executable.
    public static var bundledWorker: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "preview-worker")
    }

    /// The library preview service with the app's worker. Previews use the default options (2x, transparent):
    /// the background is drawn by the view, so changing it never renders again (PRV-8a).
    public static func standard(workerURL: URL?) -> PreviewBackend {
        let service = LibraryPreviewService(workerURL: workerURL ?? URL(fileURLWithPath: "/nonexistent"))
        return PreviewBackend(
            lookup: { library, job in
                if let hit = try service.cached(
                    library: library, id: job.itemId, entryPath: job.entryPath, assetsURL: job.assetsURL,
                    assetIdentity: job.assetIdentity)
                {
                    // An image with no drawing commands may be an empty blueprint saved by the CLI.
                    if hit.preview.report.commandKinds.isEmpty,
                        isEmptyBlueprint(try library.entry(id: job.itemId, entryPath: job.entryPath))
                    {
                        return .nothingToDraw
                    }
                    return .cached(try PreviewImage.decode(hit.preview.png, warnings: hit.preview.report.warnings))
                }
                let entry = try library.entry(id: job.itemId, entryPath: job.entryPath)
                return isEmptyBlueprint(entry) ? .nothingToDraw : .needsRender
            },
            render: { library, job, token in
                guard let workerURL, FileManager.default.isExecutableFile(atPath: workerURL.path) else {
                    throw PreviewBackendError.workerMissing
                }
                let result = try service.render(
                    library: library, id: job.itemId, entryPath: job.entryPath, assetsURL: job.assetsURL,
                    cancellation: token)
                return try PreviewImage.decode(result.preview.png, warnings: result.preview.report.warnings)
            })
    }

    /// A blueprint with no entities and no tiles: the renderer would paint a blank image (PRV-12).
    static func isEmptyBlueprint(_ entry: BlueprintEntry) -> Bool {
        entry.kind == .blueprint && (entry.body["entities"]?.array ?? []).isEmpty
            && (entry.body["tiles"]?.array ?? []).isEmpty
    }
}

/// One preview area or window. Its owner calls `PreviewCenter.show(_:in:)` whenever the subject, the item's
/// source, or the asset release changes, and `release(_:)` when it goes away.
@MainActor @Observable
public final class PreviewViewer {
    public fileprivate(set) var state: PreviewState = .none
    @ObservationIgnored fileprivate var subject: PreviewSubject?
    /// The job this viewer waits for or watches render.
    @ObservationIgnored fileprivate var job: PreviewJob?
    /// Changes with every `show`, so a late lookup for an earlier subject is dropped.
    @ObservationIgnored fileprivate var request = 0

    public init() {}
}

/// Schedules previews for the open library (PRV-1 to PRV-12): cache hits and empty blueprints are answered without a
/// worker; renders run one at a time in request order on their own queue, so library calls never wait for them.
/// Viewers asking for the same entry share one render (PRV-7), and a render is cancelled only when no viewer
/// wants it any more (PRV-6).
@MainActor @Observable
public final class PreviewCenter {
    private final class Job {
        let key: PreviewJob
        let token = PreviewCancellation()
        var viewers: [ObjectIdentifier: PreviewViewer] = [:]
        init(key: PreviewJob) { self.key = key }
    }

    /// Renders handed to the backend so far; tests check that hits and empty blueprints start none.
    public private(set) var renderCount = 0
    /// The most renders ever running at once; never above one (PRV-5).
    public private(set) var peakConcurrentRenders = 0

    private let session: LibrarySession
    private let assets: AssetSettings
    private let backend: PreviewBackend
    private let lookupWorker = LibraryWorker(label: "cyano.app.preview-lookup")
    private let renderWorker = LibraryWorker(label: "cyano.app.preview-render")
    @ObservationIgnored private var pending: [Job] = []
    @ObservationIgnored private var active: Job?
    @ObservationIgnored private var running = 0

    public init(session: LibrarySession, assets: AssetSettings, backend: PreviewBackend) {
        self.session = session
        self.assets = assets
        self.backend = backend
    }

    /// Whether a render is running (tests and the lifecycle checks use it).
    public var isRendering: Bool { active != nil }

    /// Shows `subject` in `viewer`, dropping whatever the viewer waited for before.
    public func show(_ subject: PreviewSubject?, in viewer: PreviewViewer) {
        detach(viewer)
        viewer.request += 1
        viewer.subject = subject
        guard let subject else {
            viewer.state = .none
            return
        }
        guard let library = session.libraryURL, library.path == subject.libraryPath, let listing = session.listing
        else {
            viewer.state = .checking
            return
        }
        guard let item = listing.items.first(where: { $0.id == subject.itemId }) else {
            viewer.state = .deleted(entry: false)
            return
        }
        let release: (url: URL, identity: String)
        switch assets.state {
        case .none:
            viewer.state = .noAssets
            return
        case .checking:
            // The owner calls `show` again when the release's revision changes.
            viewer.state = .checking
            return
        case .problem(_, let message):
            viewer.state = .assetsUnusable(message)
            return
        case .verified(let url, _, _, let identity):
            if case .failure(let message) = assets.availability(for: library) {
                viewer.state = .assetsUnusable(message)
                return
            }
            release = (url, identity)
        }
        let job = PreviewJob(
            itemId: subject.itemId, entryPath: subject.entryPath, sourceSha256: item.metadata.sourceSha256,
            assetsURL: release.url, assetIdentity: release.identity)
        if let existing = queued(job) {
            attach(viewer, to: existing)
            return
        }
        viewer.state = .checking
        let request = viewer.request
        let backend = backend
        Task {
            let outcome = await session.previewCall(on: lookupWorker) { try backend.lookup($0, job) }
            guard viewer.request == request else { return }
            switch outcome {
            case nil: break
            case .success(.cached(let image)): viewer.state = .ready(image)
            case .success(.nothingToDraw): viewer.state = .nothingToDraw
            case .success(.needsRender): enqueue(job, for: viewer)
            case .failure(let error): handle(error, in: viewer)
            }
        }
    }

    /// Stops showing anything in `viewer`: a waiting request is dropped, and a render no one else watches is
    /// cancelled (PRV-6).
    public func release(_ viewer: PreviewViewer) {
        detach(viewer)
        viewer.request += 1
        viewer.subject = nil
        viewer.state = .none
    }

    /// Tries a failed preview again (PRV-10).
    public func retry(_ viewer: PreviewViewer) {
        guard case .failed = viewer.state else { return }
        show(viewer.subject, in: viewer)
    }

    private func queued(_ job: PreviewJob) -> Job? {
        if let active, active.key == job, !active.token.isCancelled { return active }
        return pending.first { $0.key == job }
    }

    private func attach(_ viewer: PreviewViewer, to job: Job) {
        job.viewers[ObjectIdentifier(viewer)] = viewer
        viewer.job = job.key
        viewer.state = job === active ? .rendering : .waiting
    }

    private func detach(_ viewer: PreviewViewer) {
        guard let key = viewer.job else { return }
        viewer.job = nil
        let id = ObjectIdentifier(viewer)
        if let active, active.key == key, active.viewers[id] != nil {
            active.viewers[id] = nil
            if active.viewers.isEmpty { active.token.cancel() }
        } else if let index = pending.firstIndex(where: { $0.key == key }) {
            pending[index].viewers[id] = nil
            if pending[index].viewers.isEmpty { pending.remove(at: index) }
        }
    }

    private func enqueue(_ key: PreviewJob, for viewer: PreviewViewer) {
        let job: Job
        if let existing = queued(key) {
            job = existing
        } else {
            job = Job(key: key)
            pending.append(job)
        }
        attach(viewer, to: job)
        startNext()
    }

    /// Starts the oldest waiting render once the previous one has returned (PRV-5).
    private func startNext() {
        guard active == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        active = job
        for viewer in job.viewers.values { viewer.state = .rendering }
        renderCount += 1
        running += 1
        peakConcurrentRenders = max(peakConcurrentRenders, running)
        let backend = backend
        let key = job.key
        let token = job.token
        Task {
            let outcome = await session.previewCall(on: renderWorker) { try backend.render($0, key, token) }
            running -= 1
            active = nil
            finish(job, outcome)
            startNext()
        }
    }

    private func finish(_ job: Job, _ outcome: Result<PreviewImage, Error>?) {
        let viewers = Array(job.viewers.values)
        for viewer in viewers { viewer.job = nil }
        switch outcome {
        case nil: break
        case .success(let image): for viewer in viewers { viewer.state = .ready(image) }
        case .failure(let error): for viewer in viewers { handle(error, in: viewer) }
        }
    }

    private func handle(_ error: Error, in viewer: PreviewViewer) {
        switch error {
        case NativeLibraryError.notFound:
            viewer.state = .deleted(entry: false)
        case BlueprintCodecError.invalidEntryPath:
            viewer.state = .deleted(entry: true)
        case NativeLibraryError.sourceChanged, PreviewError.cancelled:
            // The source was replaced while rendering, or the render was cancelled for a viewer that still wants
            // it (a release change): ask again for the current source (PRV-11, SET-5a).
            show(viewer.subject, in: viewer)
        case NativeLibraryError.closed:
            break
        case PreviewBackendError.workerMissing:
            viewer.state = .failed(
                LibraryMessage(
                    title: "The preview couldn't be rendered",
                    guidance: "The app's preview renderer is missing. Reinstall the app.",
                    technical: "preview-worker is not in the app bundle."))
        default:
            viewer.state = .failed(
                LibraryMessage.describing(error, activity: .rendering)
                    ?? LibraryMessage(title: "The preview couldn't be rendered", guidance: "Try again."))
        }
    }
}
