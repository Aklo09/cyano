import Darwin
import FactorioData
import Foundation
import LibraryCore
import PreviewRenderer

private let usage = """
    Usage: fb-native <command> [arguments]

      release
      init <library>
      owner <library>
      list <library>
      recover <library> [--quarantine <operation-id>]
      operations <library>
      staging-cleanup <library> [--apply]
      import <library> <file.txt> [--name <name>] [--folder <relative folder>]
      import-unpacked <library> <file.txt> [--folder <relative folder>]
      export <library> <item-id> [--entry <stored.indices>] [--output <new-file.txt>]
      update <library> <item-id> <file.txt>
      rename <library> <item-id> <display-name>
      move <library> <item-id> <relative folder>
      delete <library> <item-id>
      folder-create <library> <parent folder> <name>
      folder-move <library> <folder> <parent folder> [new-name]
      folder-delete <library> <empty folder>
      comment <library> <item-id> <text> [--entry <stored.indices>]
      comment-add <library> <item-id> <text> [--entry <stored.indices>]
      comment-delete <library> <item-id> <comment-id>
      cache-cleanup <library> [abandoned|obsolete|all] [--apply] [--assets <release>] [--generator <identity>]
      usage <library> [--assets <release>]
      assets-verify <release-directory>
      preview <library> <item-id> --assets <release> [--entry <stored.indices>]
        [--tier 1x|2x] [--max-dimension 64...4096] [--checkerboard] [--refresh]

    Export writes source bytes to stdout or exclusively creates --output. Other results use versioned JSON.
    Use an empty string for the root folder. Folder deletion requires an empty folder.
    Cache and staging cleanup default to a dry run. Obsolete cleanup requires --assets.
    If recovery refuses an operation, list it with operations and move it aside with recover --quarantine.
    Preview reuses validated derived images; --refresh regenerates a known cache entry.
    Close the library in the application before using store commands or Finder edits.
    """

private struct Success<Value: Encodable>: Encodable {
    let schema = 1
    let ok = true
    let command: String
    let result: Value
}

private struct Failure: Encodable {
    struct Detail: Encodable {
        let category: String
        let code: String
        let message: String
        let exitCode: Int32
    }
    let schema = 1
    let ok = false
    let command: String?
    let error: Detail
}

private struct ReleaseReport: Encodable {
    let product = "fb-native"
    let stage = "owned-library-previews"
    let nativeFormatVersion = 1
    let profile = FactorioProfile.initial
    let capabilities = commands.sorted()
    let libraryOperationsAvailable = true
    let previewPaintingAvailable = true
    let previewLibraryIntegrationAvailable = true
}

private struct OwnerReport: Encodable { let state: LibraryOwnershipStatus }
private struct RecoveryReport: Encodable { let recovered = true }
private struct FolderReport: Encodable { let folder: String }
private struct DeletedReport: Encodable { let deleted = true }
private struct ExportReport: Encodable {
    let path: String
    let bytes: Int
}
private struct PreviewCommandReport: Encodable {
    let key: String
    let generator: String
    let cacheHit: Bool
    let cachePath: String
    let durationMs: Double
    let report: PreviewReport
}
private enum ArgumentsError: Error { case invalid }

private func emit<T: Encodable>(_ value: T, to output: FileHandle = .standardOutput) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(10)
    try output.write(contentsOf: data)
}

private func options(_ args: ArraySlice<String>, allowed: Set<String>) throws -> [String: String] {
    let args = Array(args)
    guard args.count.isMultiple(of: 2) else { throw ArgumentsError.invalid }
    var result: [String: String] = [:]
    for offset in stride(from: 0, to: args.count, by: 2) {
        let flag = args[offset]
        guard allowed.contains(flag), result[flag] == nil else { throw ArgumentsError.invalid }
        result[flag] = args[offset + 1]
    }
    return result
}

private func entryPath(_ text: String?) throws -> [Int] {
    guard let text else { return [] }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty, parts.count <= 32 else { throw ArgumentsError.invalid }
    return try parts.map { part in
        guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
            let value = Int(part), value <= 9_007_199_254_740_991
        else { throw ArgumentsError.invalid }
        return value
    }
}

private func run(_ args: [String]) throws {
    guard let command = args.first else {
        print(usage)
        return
    }
    if command == "--help" || command == "-h" {
        guard args.count == 1 else { throw ArgumentsError.invalid }
        print(usage)
        return
    }
    if command == "release" {
        guard args.count == 1 else { throw ArgumentsError.invalid }
        try emit(Success(command: command, result: ReleaseReport()))
        return
    }
    if command == "assets-verify" {
        guard args.count == 2 else { throw ArgumentsError.invalid }
        try emit(Success(command: command, result: AssetRelease.verify(at: URL(fileURLWithPath: args[1]))))
        return
    }
    guard args.count >= 2 else { throw ArgumentsError.invalid }
    let url = URL(fileURLWithPath: args[1])
    switch command {
    case "init":
        guard args.count == 2 else { throw ArgumentsError.invalid }
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        try emit(Success(command: command, result: library.list()))
    case "owner":
        guard args.count == 2 else { throw ArgumentsError.invalid }
        try emit(Success(command: command, result: OwnerReport(state: NativeLibrary.inspectOwnership(at: url))))
    case "operations":
        guard args.count == 2 else { throw ArgumentsError.invalid }
        try emit(Success(command: command, result: NativeLibrary.inspectOperations(at: url)))
    case "recover" where args.count == 4:
        guard args[2] == "--quarantine" else { throw ArgumentsError.invalid }
        try emit(Success(command: command, result: NativeLibrary.quarantineOperation(at: url, id: args[3])))
    case "staging-cleanup":
        guard args.count == 2 || (args.count == 3 && args[2] == "--apply") else { throw ArgumentsError.invalid }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        try emit(Success(command: command, result: library.cleanupStaging(apply: args.count == 3)))
    case "list", "recover":
        guard args.count == 2 else { throw ArgumentsError.invalid }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        if command == "list" {
            try emit(Success(command: command, result: library.list()))
        } else {
            try library.recover()
            try emit(Success(command: command, result: RecoveryReport()))
        }
    case "import", "import-unpacked":
        guard args.count >= 3 else { throw ArgumentsError.invalid }
        let opts = try options(args.dropFirst(3), allowed: command == "import" ? ["--name", "--folder"] : ["--folder"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let bytes = try NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[2]))
        if command == "import" {
            try emit(
                Success(
                    command: command,
                    result: library.importSource(bytes, name: opts["--name"], folder: opts["--folder"] ?? "")))
        } else {
            try emit(Success(command: command, result: library.importUnpacked(bytes, folder: opts["--folder"] ?? "")))
        }
    case "export":
        guard args.count >= 3 else { throw ArgumentsError.invalid }
        let opts = try options(args.dropFirst(3), allowed: ["--entry", "--output"])
        let path = try entryPath(opts["--entry"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        if let output = opts["--output"] {
            let bytes = try library.export(id: args[2], entryPath: path, to: URL(fileURLWithPath: output))
            try emit(Success(command: command, result: ExportReport(path: output, bytes: bytes)))
        } else {
            try FileHandle.standardOutput.write(contentsOf: library.export(id: args[2], entryPath: path))
        }
    case "comment", "comment-add":
        guard args.count >= 4 else { throw ArgumentsError.invalid }
        let opts = try options(args.dropFirst(4), allowed: ["--entry"])
        let path = try entryPath(opts["--entry"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let result = try library.addComment(id: args[2], entryPath: path, text: args[3])
        try emit(Success(command: command, result: result))
    case "update", "rename", "move", "comment-delete":
        guard args.count == 4 else { throw ArgumentsError.invalid }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let result: LibraryItem
        switch command {
        case "update":
            result = try library.updateSource(
                id: args[2], bytes: NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[3])))
        case "rename": result = try library.renameItem(id: args[2], name: args[3])
        case "move": result = try library.moveItem(id: args[2], folder: args[3])
        default: result = try library.deleteComment(id: args[2], commentId: args[3])
        }
        try emit(Success(command: command, result: result))
    case "delete", "folder-delete":
        guard args.count == 3 else { throw ArgumentsError.invalid }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        if command == "delete" { try library.deleteItem(id: args[2]) } else { try library.deleteFolder(args[2]) }
        try emit(Success(command: command, result: DeletedReport()))
    case "folder-create", "folder-move":
        guard args.count == 4 || (command == "folder-move" && args.count == 5) else { throw ArgumentsError.invalid }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let folder =
            try command == "folder-create"
            ? library.createFolder(parent: args[2], name: args[3])
            : library.moveFolder(args[2], parent: args[3], name: args.count == 5 ? args[4] : nil)
        try emit(Success(command: command, result: FolderReport(folder: folder)))
    case "usage":
        let opts = try options(args.dropFirst(2), allowed: ["--assets"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        try emit(
            Success(
                command: command, result: library.diskUsage(assets: opts["--assets"].map { URL(fileURLWithPath: $0) })))
    case "preview":
        guard args.count >= 3 else { throw ArgumentsError.invalid }
        let rest = Array(args.dropFirst(3))
        for flag in ["--refresh", "--checkerboard"] {
            guard rest.filter({ $0 == flag }).count <= 1 else { throw ArgumentsError.invalid }
        }
        let opts = try options(
            rest.filter { !["--refresh", "--checkerboard"].contains($0) }[...],
            allowed: ["--assets", "--entry", "--tier", "--max-dimension"])
        guard let assets = opts["--assets"], let maximum = Int(opts["--max-dimension"] ?? "2048") else {
            throw ArgumentsError.invalid
        }
        let path = try entryPath(opts["--entry"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let service = LibraryPreviewService(
            workerURL: executable.deletingLastPathComponent().appendingPathComponent("preview-worker"))
        let rendering = LibraryPreviewOptions(
            tier: opts["--tier"] ?? "2x", maximumDimension: maximum, checkerboard: rest.contains("--checkerboard"))
        let result = try service.render(
            library: library, id: args[2], entryPath: path, assetsURL: URL(fileURLWithPath: assets),
            options: rendering,
            refresh: rest.contains("--refresh"))
        try emit(
            Success(
                command: command,
                result: PreviewCommandReport(
                    key: result.key, generator: rendering.generator, cacheHit: result.cacheHit,
                    cachePath: result.cachePath, durationMs: result.durationMs, report: result.preview.report)))
    case "cache-cleanup":
        var rest = Array(args.dropFirst(2))
        var scope = CacheCleanupScope.abandoned
        if let first = rest.first, !first.hasPrefix("--") {
            guard let parsed = CacheCleanupScope(rawValue: first) else { throw ArgumentsError.invalid }
            scope = parsed
            rest.removeFirst()
        }
        let apply = rest.contains("--apply")
        guard rest.filter({ $0 == "--apply" }).count <= 1 else { throw ArgumentsError.invalid }
        rest.removeAll { $0 == "--apply" }
        let opts = try options(rest[...], allowed: ["--assets", "--generator"])
        guard scope != .obsolete || opts["--assets"] != nil,
            opts["--generator"] == nil || scope == .obsolete
        else { throw ArgumentsError.invalid }
        let assets = opts["--assets"].map { URL(fileURLWithPath: $0) }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let identity = try assets.map { try AssetRelease.verify(at: $0).identity }
        try emit(
            Success(
                command: command,
                result: library.cleanupCache(
                    scope: scope, apply: apply, assetIdentity: identity,
                    generator: opts["--generator"] ?? "native-preview-v1", protectedAssets: assets)))
    default: throw ArgumentsError.invalid
    }
}

private let args = Array(CommandLine.arguments.dropFirst())
private let commands = Set([
    "release", "init", "owner", "list", "recover", "import", "import-unpacked", "export", "comment", "comment-add",
    "comment-delete", "update", "rename", "move", "delete", "folder-create", "folder-move", "folder-delete",
    "cache-cleanup", "usage", "assets-verify", "preview", "operations", "staging-cleanup",
])
do {
    try run(args)
} catch {
    let detail: Failure.Detail
    if let error = error as? NativeLibraryError {
        detail = .init(category: error.category, code: error.code, message: error.description, exitCode: error.exitCode)
    } else if let error = error as? PreviewError {
        detail = .init(
            category: "rendering", code: error.code, message: error.description,
            exitCode: error == .invalidInput ? 7 : 8)
    } else if let error = error as? AssetReleaseError {
        detail = .init(category: "validation", code: "INVALID_ASSET_RELEASE", message: error.description, exitCode: 7)
    } else if let error = error as? BlueprintCodecError {
        let internalFailure = error == .compressionFailure || error == .invalidLimits
        detail = .init(
            category: internalFailure ? "internal" : "validation", code: "BLUEPRINT_CODEC_ERROR",
            message: error.description, exitCode: internalFailure ? 1 : 7)
    } else if error is ArgumentsError {
        detail = .init(
            category: "arguments", code: "INVALID_ARGUMENTS", message: "Invalid arguments. Run fb-native --help.",
            exitCode: 2)
    } else {
        detail = .init(
            category: "io", code: "IO_ERROR", message: "The filesystem or output operation failed.", exitCode: 6)
    }
    try? emit(
        Failure(command: args.first.flatMap { commands.contains($0) ? $0 : nil }, error: detail), to: .standardError)
    exit(detail.exitCode)
}
