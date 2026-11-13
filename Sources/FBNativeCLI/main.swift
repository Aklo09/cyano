import Darwin
import FactorioData
import Foundation
import LibraryCore

private let usage = """
Usage: fb-native <command> [arguments]

  release
  init <library>
  owner <library>
  list <library>
  recover <library>
  import <library> <file.txt> [--name <name>] [--folder <relative folder>]
  export <library> <item-id> [--entry <stored.indices>]
  comment <library> <item-id> <text> [--entry <stored.indices>]

Export writes only source bytes to stdout. Other results use versioned JSON.
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
    let stage = "storage-prototype"
    let nativeFormatVersion = 1
    let profile = FactorioProfile.initial
    let capabilities = ["release", "init", "owner", "list", "recover", "import", "export", "comment"]
    let libraryOperationsAvailable = true
    let previewPaintingAvailable = false
}

private struct OwnerReport: Encodable { let state: LibraryOwnershipStatus }
private struct RecoveryReport: Encodable { let recovered = true }
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
              let value = Int(part), value <= 9_007_199_254_740_991 else { throw ArgumentsError.invalid }
        return value
    }
}

private func run(_ args: [String]) throws {
    guard let command = args.first else { print(usage); return }
    if command == "--help" || command == "-h" {
        guard args.count == 1 else { throw ArgumentsError.invalid }
        print(usage); return
    }
    if command == "release" {
        guard args.count == 1 else { throw ArgumentsError.invalid }
        try emit(Success(command: command, result: ReleaseReport())); return
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
    case "list", "recover":
        guard args.count == 2 else { throw ArgumentsError.invalid }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        if command == "list" { try emit(Success(command: command, result: library.list())) }
        else { try library.recover(); try emit(Success(command: command, result: RecoveryReport())) }
    case "import":
        guard args.count >= 3 else { throw ArgumentsError.invalid }
        let opts = try options(args.dropFirst(3), allowed: ["--name", "--folder"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let bytes = try NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[2]))
        let result = try library.importSource(bytes, name: opts["--name"], folder: opts["--folder"] ?? "")
        try emit(Success(command: command, result: result))
    case "export":
        guard args.count >= 3 else { throw ArgumentsError.invalid }
        let opts = try options(args.dropFirst(3), allowed: ["--entry"])
        let path = try entryPath(opts["--entry"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        try FileHandle.standardOutput.write(contentsOf: library.export(id: args[2], entryPath: path))
    case "comment":
        guard args.count >= 4 else { throw ArgumentsError.invalid }
        let opts = try options(args.dropFirst(4), allowed: ["--entry"])
        let path = try entryPath(opts["--entry"])
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let result = try library.addComment(id: args[2], entryPath: path, text: args[3])
        try emit(Success(command: command, result: result))
    default: throw ArgumentsError.invalid
    }
}

private let args = Array(CommandLine.arguments.dropFirst())
private let commands = Set(["release", "init", "owner", "list", "recover", "import", "export", "comment"])
do {
    try run(args)
} catch {
    let detail: Failure.Detail
    if let error = error as? NativeLibraryError {
        detail = .init(category: error.category, code: error.code, message: error.description, exitCode: error.exitCode)
    } else if let error = error as? BlueprintCodecError {
        let internalFailure = error == .compressionFailure || error == .invalidLimits
        detail = .init(category: internalFailure ? "internal" : "validation", code: "BLUEPRINT_CODEC_ERROR",
                       message: error.description, exitCode: internalFailure ? 1 : 7)
    } else if error is ArgumentsError {
        detail = .init(category: "arguments", code: "INVALID_ARGUMENTS", message: "Invalid arguments. Run fb-native --help.", exitCode: 2)
    } else {
        detail = .init(category: "io", code: "IO_ERROR", message: "The filesystem or output operation failed.", exitCode: 6)
    }
    try? emit(Failure(command: args.first.flatMap { commands.contains($0) ? $0 : nil }, error: detail), to: .standardError)
    exit(detail.exitCode)
}
