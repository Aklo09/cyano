import CLibraryPlatform
import Darwin
import Foundation
import ImageIO
import LibraryCore
import UniformTypeIdentifiers

private final class PreviewPipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var invalid = false
    private var finished = false
    func receive(_ handle: FileHandle, maximum: Int) {
        do {
            while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                lock.lock()
                if data.count <= maximum - chunk.count { data.append(chunk) } else { invalid = true }
                lock.unlock()
            }
        } catch {
            lock.lock()
            invalid = true
            lock.unlock()
        }
        lock.lock()
        finished = true
        lock.unlock()
    }
    func snapshot() -> (Data, Bool, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, invalid, finished)
    }
}

/// One active, supervised, read-only helper per owner. No library mutation interface is sent.
public final class PreviewProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false, cancellation = false
    private var lastPID: Int32?
    package var lastWorkerPID: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return lastPID
    }
    private let workerURL: URL
    private let residentLimit: UInt64
    public init(workerURL: URL) {
        self.workerURL = workerURL
        residentLimit = 1_073_741_824
    }
    package init(workerURL: URL, residentLimit: UInt64) {
        self.workerURL = workerURL
        self.residentLimit = residentLimit
    }
    public func cancel() {
        lock.lock()
        if active { cancellation = true }
        lock.unlock()
    }

    public func render(
        _ request: PreviewRequest, deadline: TimeInterval = 60, cancellation token: PreviewCancellation? = nil
    ) throws -> PreviewResult {
        try render(request, deadline: deadline, cancellation: token, ownership: nil)
    }

    package func render(
        _ request: PreviewRequest, deadline: TimeInterval, cancellation token: PreviewCancellation?,
        ownership: LibraryOwnershipLoan?
    ) throws -> PreviewResult {
        try request.validate()
        try token?.check()
        guard deadline.isFinite, deadline > 0, deadline <= 60 else { throw PreviewError.invalidInput }
        lock.lock()
        guard !active else {
            lock.unlock()
            throw PreviewError.workerBusy
        }
        active = true
        cancellation = false
        lock.unlock()
        defer {
            lock.lock()
            active = false
            cancellation = false
            lock.unlock()
        }
        let started = previewMilliseconds()
        let bytes = try JSONEncoder().encode(request)
        guard bytes.count <= 24 * 1024 * 1024 else { throw PreviewError.invalidInput }
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        defer {
            for handle in [
                input.fileHandleForReading, input.fileHandleForWriting, output.fileHandleForReading,
                output.fileHandleForWriting, errors.fileHandleForReading, errors.fileHandleForWriting,
            ] { try? handle.close() }
        }
        // Avoid a process-wide SIGPIPE change when a crashed worker closes stdin early.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let resultBuffer = PreviewPipeBuffer()
        let errorBuffer = PreviewPipeBuffer()
        let launchStarted = previewMilliseconds()
        let process = try PreviewChild(
            url: workerURL, input: input.fileHandleForReading.fileDescriptor,
            output: output.fileHandleForWriting.fileDescriptor, errors: errors.fileHandleForWriting.fileDescriptor,
            ownership: ownership)
        defer { process.cleanup() }
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        try errors.fileHandleForWriting.close()
        lock.lock()
        lastPID = process.pid
        lock.unlock()
        let launchMs = previewMilliseconds() - launchStarted
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            resultBuffer.receive(output.fileHandleForReading, maximum: 96 * 1024 * 1024)
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errorBuffer.receive(errors.fileHandleForReading, maximum: 64 * 1024)
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                var length = UInt64(bytes.count).bigEndian
                try withUnsafeBytes(of: &length) { try input.fileHandleForWriting.write(contentsOf: Data($0)) }
                try input.fileHandleForWriting.write(contentsOf: bytes)
            } catch { /* Exit/status and framed-result validation handle a closed worker pipe. */  }
        }
        var failure: PreviewError?
        while try process.running() {
            lock.lock()
            let cancelled = cancellation
            lock.unlock()
            if cancelled || token?.isCancelled == true {
                failure = .cancelled
            } else if previewMilliseconds() - started >= deadline * 1000 {
                failure = .timedOut
            } else if fb_process_resident_bytes(process.pid) > residentLimit {
                failure = .memoryLimit
            } else if resultBuffer.snapshot().1 || errorBuffer.snapshot().1 {
                failure = .workerProtocol
            }
            if failure != nil {
                process.killGroup()
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        try process.wait()
        try? input.fileHandleForWriting.close()
        guard group.wait(timeout: .now() + 2) == .success else {
            _ = group.wait(timeout: .now() + 2)
            throw PreviewError.workerProtocol
        }
        if let failure { throw failure }
        let (data, invalid, finished) = resultBuffer.snapshot()
        guard !invalid, finished, !errorBuffer.snapshot().1 else { throw PreviewError.workerProtocol }
        guard process.succeeded else {
            throw PreviewError.workerFailed
        }
        guard var result = try? JSONDecoder().decode(PreviewResult.self, from: data) else {
            throw PreviewError.workerProtocol
        }
        let validationStarted = previewMilliseconds()
        try Self.validate(result, request: request)
        lock.lock()
        let wasCancelled = cancellation
        lock.unlock()
        if wasCancelled || token?.isCancelled == true { throw PreviewError.cancelled }
        guard previewMilliseconds() - started < deadline * 1000 else { throw PreviewError.timedOut }
        result.report.timingsMs["parentValidation"] = previewMilliseconds() - validationStarted
        result.report.timingsMs["processLaunch"] = launchMs
        result.report.timingsMs["supervisorWall"] = previewMilliseconds() - started
        return result
    }

    public static func validate(_ result: PreviewResult, request: PreviewRequest) throws {
        let report = result.report
        guard report.schema == 1, (1...request.maximumDimension).contains(report.width),
            (1...request.maximumDimension).contains(report.height),
            report.entryPath == request.entryPath, report.sourceSha256 == OriginalSource(bytes: request.source).sha256,
            report.plannerRevision == "2f7dc70f2681de530402556f757006e904e692d5",
            ["blueprint", "upgrade_planner", "deconstruction_planner"].contains(report.entryKind),
            report.assetIdentity.utf8.count == 64,
            report.assetIdentity.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            report.pixelsPerTile.isFinite, report.pixelsPerTile > 0, report.pixelsPerTile <= 32,
            report.commandKinds.count <= 8, report.commandKinds.values.allSatisfy({ $0 >= 0 && $0 <= 250_000 }),
            report.warnings.count <= 100_000, report.warnings.allSatisfy({ $0.utf8.count <= 65536 }),
            report.timingsMs.count <= 32,
            report.timingsMs.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 60_000 }),
            !result.png.isEmpty, result.png.count <= 64 * 1024 * 1024,
            let source = CGImageSourceCreateWithData(result.png as CFData, nil),
            CGImageSourceGetType(source) == UTType.png.identifier as CFString,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            properties[kCGImagePropertyPixelWidth] as? Int == report.width,
            properties[kCGImagePropertyPixelHeight] as? Int == report.height,
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
            image.width == report.width, image.height == report.height
        else { throw PreviewError.workerProtocol }
        // Force raster access independently of the worker's PNG encoder.
        let bitmap = try makeBitmap(width: image.width, height: image.height)
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    public static func writeNew(_ result: PreviewResult, to url: URL, protecting assetsURL: URL) throws {
        try LibraryDirectory.validateURL(url)
        let parent = try LibraryDirectory(url: url.deletingLastPathComponent())
        let assets = try LibraryDirectory(url: assetsURL)
        guard parent.url.path != assets.url.path, !parent.url.path.hasPrefix(assets.url.path + "/") else {
            throw PreviewError.invalidInput
        }
        try parent.writeNew(url.lastPathComponent, data: result.png)
    }
}
