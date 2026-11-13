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

/// Library ownership covers source selection, rendering, validation, and derived publication.
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

    public func render(
        library: NativeLibrary, id: String, entryPath: [Int] = [], assetsURL: URL,
        options: LibraryPreviewOptions = LibraryPreviewOptions(), refresh: Bool = false
    ) throws -> LibraryPreviewResult {
        let token = PreviewCancellation()
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
        return try library.withPreviewContext(id: id, entryPath: entryPath, onCancel: { token.cancel() }) { context in
            try token.check()
            try context.checkAssets(assetsURL)
            let identity = LibraryCacheIdentity(
                itemId: id, sourceSha256: context.sourceSha256, entryPath: entryPath,
                generator: options.generator, assetIdentity: verified.identity)
            let key = try identity.key()
            let request = PreviewRequest(
                source: context.source, entryPath: entryPath, assetsPath: assetsURL.path,
                tier: options.tier, maximumDimension: options.maximumDimension, checkerboard: options.checkerboard)
            let cached = try context.cached(identity)
            if !refresh, let cached, let report = try? JSONDecoder().decode(PreviewReport.self, from: cached.report) {
                let result = PreviewResult(report: report, png: cached.image)
                if (try? PreviewProcess.validate(result, request: request)) != nil,
                    result.report.assetIdentity == verified.identity
                {
                    try token.check()
                    return LibraryPreviewResult(
                        key: key, cacheHit: true, cachePath: "cache/\(id)/\(key).png",
                        durationMs: previewMilliseconds() - started, preview: result)
                }
            }
            try context.willStartWorker()
            try token.check()
            let result = try process.render(request, deadline: 60, cancellation: token, ownership: context.ownership)
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
