import Darwin
import Foundation
import PreviewRenderer

do {
    switch Array(CommandLine.arguments.dropFirst()) {
    case [], ["--help"], ["-h"]:
        print("Usage: preview-probe --self-test\n\nLoads the bundled planner and plans empty upgrade/deconstruction diagrams.\nThis checks JavaScriptCore execution; it does not paint images.")
    case ["--self-test"]:
        let report = try PlannerRuntime().selfTest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
    default:
        FileHandle.standardError.write(Data("Unknown arguments. Run preview-probe --help.\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("Preview self-test failed: \(error)\n".utf8))
    exit(1)
}
