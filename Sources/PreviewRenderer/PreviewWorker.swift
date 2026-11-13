import CoreGraphics
import Darwin
import Foundation
import ImageIO
import LibraryCore
import UniformTypeIdentifiers

public enum PreviewWorker {
    package static func render(_ request: PreviewRequest) throws -> PreviewResult {
        try request.validate()
        var timings: [String: Double] = [:]
        var start = previewMilliseconds()
        let document = try BlueprintCodec.decode(request.source)
        let entry = try document.entry(at: request.entryPath)
        guard entry.kind != .book else { throw PreviewError.invalidInput }
        let entryData = try entry.value.encoded(maximum: 64 * 1024 * 1024)
        timings["sourceDecode"] = previewMilliseconds() - start
        start = previewMilliseconds()
        let assets = try RenderAssets(path: request.assetsPath, tier: request.tier)
        timings["assetsVerifyAndLoad"] = previewMilliseconds() - start
        start = previewMilliseconds()
        let runtime = try PlannerRuntime()
        timings["runtimeStartup"] = previewMilliseconds() - start
        start = previewMilliseconds()
        let planned = try runtime.plan(entry: entryData, database: assets.database)
        let transferTime = previewMilliseconds() - start
        timings["javascriptParse"] = planned.parseMs
        timings["planning"] = planned.planningMs
        timings["bridgeAndResultDecode"] = max(0, transferTime - planned.parseMs - planned.planningMs)
        start = previewMilliseconds()
        let painter = try NativePainter(
            source: assets, list: planned.drawList, maximumDimension: request.maximumDimension,
            checkerboard: request.checkerboard)
        let image = try painter.paint(planned.drawList)
        timings["paintingAndAtlasDecode"] = previewMilliseconds() - start
        start = previewMilliseconds()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw PreviewError.imageEncoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 64 * 1024 * 1024 else {
            throw PreviewError.imageEncoding
        }
        timings["pngEncoding"] = previewMilliseconds() - start
        var usage = rusage()
        _ = getrusage(RUSAGE_SELF, &usage)
        let report = PreviewReport(
            schema: 1, width: painter.width, height: painter.height, entryKind: entry.kind.rawValue,
            sourceSha256: document.original.sha256, entryPath: request.entryPath, assetIdentity: assets.identity,
            plannerRevision: "2f7dc70f2681de530402556f757006e904e692d5", pixelsPerTile: painter.pixelsPerTile,
            commandKinds: planned.commandKinds, warnings: planned.warnings, timingsMs: timings,
            peakResidentBytes: UInt64(max(0, usage.ru_maxrss)), atlasDecodes: assets.atlasDecodes)
        return PreviewResult(report: report, png: output as Data)
    }

    /// Framed stdin request, followed by a pipe lifeline. The worker only writes stdout/stderr.
    public static func serve() throws {
        try serve(renderJob: render)
    }

    package static func serve(renderJob: (PreviewRequest) throws -> PreviewResult) throws {
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput
        func read(_ count: Int) throws -> Data {
            var result = Data()
            while result.count < count {
                guard let chunk = try input.read(upToCount: min(65536, count - result.count)), !chunk.isEmpty else {
                    throw PreviewError.workerProtocol
                }
                result.append(chunk)
            }
            return result
        }
        let header = try read(8)
        let length = header.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length > 0, length <= 24 * 1024 * 1024 else { throw PreviewError.workerProtocol }
        let request = try JSONDecoder().decode(PreviewRequest.self, from: read(Int(length)))
        try request.validate()
        // The caller keeps its write end open until the worker exits. Death closes it in the kernel.
        DispatchQueue.global().async {
            _ = try? input.read(upToCount: 1)
            _exit(125)
        }
        let result = try renderJob(request)
        let bytes = try JSONEncoder().encode(result)
        guard bytes.count <= 96 * 1024 * 1024 else { throw PreviewError.workerProtocol }
        try FileHandle.standardOutput.write(contentsOf: bytes)
    }
}
