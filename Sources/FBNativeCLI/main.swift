import Darwin
import FactorioData
import Foundation
import LibraryCore

let usage = """
Usage: fb-native --help | release

  release   Print the foundation build's profile and available capabilities.

Library storage commands are not implemented yet.
"""

struct ReleaseReport: Encodable {
    let schema = 1
    let product = "fb-native"
    let stage = "foundation"
    let profile = FactorioProfile.initial
    let capabilities = ["release"]
    let libraryOperationsAvailable = false
    let previewPaintingAvailable = false
}

do {
    switch Array(CommandLine.arguments.dropFirst()) {
    case [], ["--help"], ["-h"]:
        print(usage)
    case ["release"]:
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(ReleaseReport()))
        FileHandle.standardOutput.write(Data("\n".utf8))
    default:
        FileHandle.standardError.write(Data("Unknown arguments. Run fb-native --help.\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("Could not encode release information: \(error)\n".utf8))
    exit(1)
}
