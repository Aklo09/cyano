import Darwin
import Foundation
import PreviewRenderer

do { try PreviewWorker.serve() } catch {
    try? FileHandle.standardError.write(contentsOf: Data("Preview worker failed: \(error)\n".utf8))
    exit(1)
}
