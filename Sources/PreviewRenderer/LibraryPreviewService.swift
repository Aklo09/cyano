import FactorioData
import Foundation
import LibraryCore

public struct LibraryPreviewOptions: Sendable {
    public let tier: String
    public let maximumDimension: Int
    public let checkerboard: Bool
    public init(tier: String = "2x", maximumDimension: Int = 2048, checkerboard: Bool = false) {
        self.tier = tier
        self.maximumDimension = maximumDimension
        self.checkerboard = checkerboard
    }
    public var generator: String {
        if tier == "2x" && maximumDimension == 2048 && !checkerboard { return "native-preview-v1" }
        return "native-preview-v1;tier=\(tier);max=\(maximumDimension);checkerboard=\(checkerboard ? 1 : 0)"
    }
}

public struct LibraryPreviewResult: Sendable {
    public let key: String
    public let cacheHit: Bool
    public let cachePath: String
    public let durationMs: Double
    public let preview: PreviewResult
}

/// Snapshots the source under ownership, renders off the library queue, then revalidates and publishes.
public final class LibraryPreviewService: @unchecked Sendable {
    private let process: PreviewProcess
    private let lock = NSLock()
    private var active: PreviewCancellation?
    public init(workerURL: URL) { process = PreviewProcess(workerURL: workerURL) }
    package var lastWorkerPID: Int32? { process.lastWorkerPID }

    public func cancel() {
        lock.lock()
        let token = active
        lock.unlock()
        token?.cancel()
        process.cancel()
    }

    /// Looks up a published preview for a release the caller verified earlier (its `assetIdentity`), without
    /// verifying the release again or starting a worker. It does not take the render slot, so it can run while
    /// another entry renders; nil means the entry needs a render.
    public func cached(
        library: NativeLibrary, id: String, entryPath: [Int] = [], assetsURL: URL, assetIdentity: String,
        options: LibraryPreviewOptions = LibraryPreviewOptions()
    ) throws -> LibraryPreviewResult? {
        let started = previewMilliseconds()
        guard !library.isClosing else { throw NativeLibraryError.closed }
        try LibraryDirectory.validateURL(assetsURL)
        let ignoreCancel: @Sendable () -> Void = {}
        return try library.withPreviewContext(id: id, entryPath: entryPath, onCancel: ignoreCancel) { context in
            try context.checkAssets(assetsURL)
            let identity = LibraryCacheIdentity(
                itemId: id, sourceSha256: context.sourceSha256, entryPath: entryPath,
                generator: options.generator, assetIdentity: assetIdentity)
            let key = try identity.key()
            guard
                let result = try Self.cachedResult(
                    context, identity: identity, assetsURL: assetsURL, assetIdentity: assetIdentity,
                    options: options)
            else { return nil }
            return LibraryPreviewResult(
                key: key, cacheHit: true, cachePath: "cache/\(id)/\(key).png",
                durationMs: previewMilliseconds() - started, preview: result)
        }
    }

    /// A cached image and report that still validate for `identity`, or nil.
    private static func cachedResult(
        _ context: LibraryPreviewContext, identity: LibraryCacheIdentity, assetsURL: URL, assetIdentity: String,
        options: LibraryPreviewOptions
    ) throws -> PreviewResult? {
        guard let cached = try context.cached(identity),
            let report = try? JSONDecoder().decode(PreviewReport.self, from: cached.report)
        else { return nil }
        let request = PreviewRequest(
            source: context.source, entryPath: context.entryPath, assetsPath: assetsURL.path, tier: options.tier,
            maximumDimension: options.maximumDimension, checkerboard: options.checkerboard)
        let result = PreviewResult(report: report, png: cached.image)
        guard (try? PreviewProcess.validate(result, request: request)) != nil, report.assetIdentity == assetIdentity
        else { return nil }
        return result
    }

    /// Renders one entry, or serves it from the cache. `cancellation` lets the caller cancel this job alone;
    /// `cancel()` cancels whichever job is active.
    public func render(
        library: NativeLibrary, id: String, entryPath: [Int] = [], assetsURL: URL,
        options: LibraryPreviewOptions = LibraryPreviewOptions(), refresh: Bool = false,
        cancellation: PreviewCancellation? = nil
    ) throws -> LibraryPreviewResult {
        let token = cancellation ?? PreviewCancellation()
        lock.lock()
        guard active == nil else {
            lock.unlock()
            throw PreviewError.workerBusy
        }
        active = token
        lock.unlock()
        defer {
            lock.lock()
            active = nil
            lock.unlock()
        }
        let started = previewMilliseconds()
        guard !library.isClosing else { throw NativeLibraryError.closed }
        let probe = PreviewRequest(
            source: Data([1]), assetsPath: assetsURL.path, tier: options.tier,
            maximumDimension: options.maximumDimension, checkerboard: options.checkerboard)
        try probe.validate()
        try LibraryDirectory.validateURL(assetsURL)
        let verified = try AssetRelease.verify(at: assetsURL)
        try token.check()
        let cancel: @Sendable () -> Void = { token.cancel() }
        return try library.withPreviewContext(id: id, entryPath: entryPath, onCancel: cancel) { context in
            try token.check()
            try context.checkAssets(assetsURL)
            let identity = LibraryCacheIdentity(
                itemId: id, sourceSha256: context.sourceSha256, entryPath: entryPath,
                generator: options.generator, assetIdentity: verified.identity)
            let key = try identity.key()
            let request = PreviewRequest(
                source: context.source, entryPath: entryPath, assetsPath: assetsURL.path,
                tier: options.tier, maximumDimension: options.maximumDimension, checkerboard: options.checkerboard)
            if !refresh,
                let result = try Self.cachedResult(
                    context, identity: identity, assetsURL: assetsURL, assetIdentity: verified.identity,
                    options: options)
            {
                try token.check()
                return LibraryPreviewResult(
                    key: key, cacheHit: true, cachePath: "cache/\(id)/\(key).png",
                    durationMs: previewMilliseconds() - started, preview: result)
            }
            try context.willStartWorker()
            try token.check()
            let result = try process.render(request, deadline: 60, cancellation: token)
            guard result.report.assetIdentity == verified.identity else { throw PreviewError.assetDecode }
            try token.check()
            try context.publish(identity, image: result.png, report: JSONEncoder().encode(result.report))
            try token.check()
            return LibraryPreviewResult(
                key: key, cacheHit: false, cachePath: "cache/\(id)/\(key).png",
                durationMs: previewMilliseconds() - started, preview: result)
        }
    }
}
