import Darwin
import Foundation
@_spi(Testing) import LibraryCore

let args = Array(CommandLine.arguments.dropFirst())
do {
    guard args.count >= 2 else { exit(2) }
    let url = URL(fileURLWithPath: args[1])
    switch args[0] {
    case "hold":
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        try FileHandle.standardOutput.write(contentsOf: Data("ready\n".utf8))
        _ = FileHandle.standardInput.readDataToEndOfFile()
    case "probe":
        print(try NativeLibrary.inspectOwnership(at: url).rawValue)
    case "initialize-crash", "import-crash", "comment-crash":
        guard let phase = LibraryWritePhase(rawValue: args.last!) else { exit(2) }
        let library = try NativeLibrary.testingOpen(at: url, initializing: args[0] == "initialize-crash") { current in
            if current == phase { kill(getpid(), SIGKILL) }
        }
        defer { library.close() }
        if args[0] == "import-crash" {
            guard args.count == 4 else { exit(2) }
            _ = try library.importSource(NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[2])), name: "Interrupted")
        } else if args[0] == "comment-crash" {
            guard args.count == 4 else { exit(2) }
            _ = try library.addComment(id: args[2], text: "Interrupted comment")
        }
    default: exit(2)
    }
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("\(error)\n".utf8))
    exit(1)
}
