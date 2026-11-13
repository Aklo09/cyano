import Darwin
import Foundation
import LibraryCore
import PreviewRenderer

let usage = """
    Usage:
      preview-probe --self-test
      preview-probe render <source.txt> --assets <release-directory> --output <new.png>
        [--entry <stored.indices>] [--tier 1x|2x] [--max-dimension 64...4096] [--checkerboard]

    Render uses one supervised native worker with a 60-second deadline and a 1 GiB RSS ceiling.
    Select a leaf when the source is a book. Output creation is exclusive; existing files are refused.
    Assets must be an assembled, verifiable release. No library is opened or mutated.
    """

func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var bytes = try encoder.encode(value)
    bytes.append(10)
    try FileHandle.standardOutput.write(contentsOf: bytes)
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args == ["--help"] || args == ["-h"] {
        print(usage)
    } else if args == ["--self-test"] {
        try emit(PlannerRuntime().selfTest())
    } else {
        guard args.count >= 2, args[0] == "render" else { throw PreviewError.invalidInput }
        var options: [String: String] = [:]
        var checkerboard = false
        var index = 2
        while index < args.count {
            let flag = args[index]
            if flag == "--checkerboard" {
                guard !checkerboard else { throw PreviewError.invalidInput }
                checkerboard = true
                index += 1
            } else {
                guard ["--entry", "--tier", "--max-dimension", "--assets", "--output"].contains(flag),
                    options[flag] == nil, index + 1 < args.count
                else { throw PreviewError.invalidInput }
                options[flag] = args[index + 1]
                index += 2
            }
        }
        guard let assets = options["--assets"], let output = options["--output"],
            let maximum = Int(options["--max-dimension"] ?? "2048")
        else { throw PreviewError.invalidInput }
        let path: [Int]
        if let selection = options["--entry"] {
            let parts = selection.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.count <= 32 else { throw PreviewError.invalidInput }
            path = try parts.map {
                guard !$0.isEmpty, $0.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int($0),
                    value <= 9_007_199_254_740_991
                else { throw PreviewError.invalidInput }
                return value
            }
        } else {
            path = []
        }
        let source = try NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[1]))
        let request = PreviewRequest(
            source: source, entryPath: path, assetsPath: URL(fileURLWithPath: assets).path,
            tier: options["--tier"] ?? "2x", maximumDimension: maximum, checkerboard: checkerboard)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let owner = PreviewProcess(
            workerURL: executable.deletingLastPathComponent().appendingPathComponent("preview-worker"))
        let result = try owner.render(request)
        try PreviewProcess.writeNew(result, to: URL(fileURLWithPath: output), protecting: URL(fileURLWithPath: assets))
        try emit(result.report)
    }
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Preview failed: \(error)\n".utf8))
    exit(1)
}
