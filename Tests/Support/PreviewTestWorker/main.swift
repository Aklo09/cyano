import Darwin
import Foundation
import PreviewRenderer
import PreviewTestPlatform

// Tests choose behavior by basename through a disposable symlink to this executable.
let mode = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
let args = Array(CommandLine.arguments.dropFirst())
if args == ["descendant-holder"] {
    Thread.sleep(forTimeInterval: 120)
    exit(0)
}
if args.count == 1, args[0] == "parent" {
    let input = Pipe()
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["lifeline"]
    child.standardInput = input
    child.standardOutput = FileHandle.standardOutput
    try child.run()
    let request = PreviewRequest(source: Data([1]), assetsPath: "unused")
    let bytes = try JSONEncoder().encode(request)
    var length = UInt64(bytes.count).bigEndian
    try withUnsafeBytes(of: &length) { try input.fileHandleForWriting.write(contentsOf: Data($0)) }
    try input.fileHandleForWriting.write(contentsOf: bytes)
    child.waitUntilExit()
    exit(child.terminationStatus)
}
if args.count == 1, args[0] == "lifeline" {
    try PreviewWorker.serve { _ in
        try FileHandle.standardOutput.write(contentsOf: Data("\(getpid())\n".utf8))
        Thread.sleep(forTimeInterval: 120)
        throw PreviewError.workerFailed
    }
    exit(0)
}
switch mode {
case "preview-test-descendant":
    guard let path = ProcessInfo.processInfo.environment["FB_PREVIEW_TEST_READY"] else { exit(2) }
    var child: Int32 = 0
    guard CommandLine.arguments[0].withCString({ fb_test_spawn_descendant($0, &child) }) == 0 else { exit(1) }
    try JSONSerialization.data(withJSONObject: ["pid": child]).write(to: URL(fileURLWithPath: path), options: .atomic)
    try FileHandle.standardOutput.write(contentsOf: Data("{}".utf8))
case "preview-test-orphan":
    guard let path = ProcessInfo.processInfo.environment["FB_PREVIEW_TEST_READY"] else { exit(2) }
    var info = stat()
    var other = stat()
    let unrelated = Int32(ProcessInfo.processInfo.environment["FB_PREVIEW_TEST_PRIVATE_FD"] ?? "-1") ?? -1
    let bytes = try JSONSerialization.data(withJSONObject: [
        "pid": getpid(), "descriptor3": fstat(3, &info) == 0, "unrelated": fstat(unrelated, &other) == 0,
    ])
    try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
    // Deliberately ignore the lifeline: an orphaned helper must not keep the library owned.
    Thread.sleep(forTimeInterval: 120)
case "preview-test-crash": kill(getpid(), SIGKILL)
case "preview-test-malformed":
    try FileHandle.standardOutput.write(contentsOf: Data("{}".utf8))
case "preview-test-large":
    signal(SIGPIPE, SIG_IGN)
    let chunk = Data(repeating: 65, count: 1024 * 1024)
    for _ in 0..<100 { try FileHandle.standardOutput.write(contentsOf: chunk) }
default:
    // Parent tests terminate this process through timeout/cancellation.
    Thread.sleep(forTimeInterval: 120)
}
