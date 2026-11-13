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
    case "initialize-crash", "import-crash", "comment-crash", "rename-crash", "move-crash", "delete-crash",
        "update-crash", "comment-delete-crash", "folder-move-crash", "folder-delete-crash", "unpack-crash":
        guard let phase = LibraryWritePhase(rawValue: args.last!) else { exit(2) }
        let library = try NativeLibrary.testingOpen(at: url, initializing: args[0] == "initialize-crash") { current in
            if current == phase { kill(getpid(), SIGKILL) }
        }
        defer { library.close() }
        if args[0] == "import-crash" {
            guard args.count == 4 else { exit(2) }
            _ = try library.importSource(
                NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[2])), name: "Interrupted")
        } else if args[0] == "comment-crash" {
            guard args.count == 4 else { exit(2) }
            _ = try library.addComment(id: args[2], text: "Interrupted comment")
        } else if args[0] == "rename-crash" {
            _ = try library.renameItem(id: args[2], name: "Renamed")
        } else if args[0] == "move-crash" {
            _ = try library.moveItem(id: args[2], folder: "Destination")
        } else if args[0] == "delete-crash" {
            try library.deleteItem(id: args[2])
        } else if args[0] == "update-crash" {
            _ = try library.updateSource(
                id: args[2], bytes: NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[3])))
        } else if args[0] == "comment-delete-crash" {
            _ = try library.deleteComment(id: args[2], commentId: args[3])
        } else if args[0] == "folder-move-crash" {
            _ = try library.moveFolder(args[2], parent: "", name: "Renamed")
        } else if args[0] == "folder-delete-crash" {
            try library.deleteFolder(args[2])
        } else if args[0] == "unpack-crash" {
            _ = try library.importUnpacked(NativeLibrary.readSourceFile(at: URL(fileURLWithPath: args[2])))
        }
    default: exit(2)
    }
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("\(error)\n".utf8))
    exit(1)
}
