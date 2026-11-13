import Darwin
import Foundation
@_spi(Testing) import LibraryCore
import PreviewRenderer

let args = Array(CommandLine.arguments.dropFirst())
do {
    guard args.count >= 4 else { exit(2) }
    let root = URL(fileURLWithPath: args[1])
    let library: NativeLibrary
    if args[0] == "cache-crash", args.count == 5, let phase = LibraryWritePhase(rawValue: args[4]) {
        library = try NativeLibrary.testingOpen(at: root) { current in
            if current == phase { kill(getpid(), SIGKILL) }
        }
    } else {
        library = try NativeLibrary(at: root)
    }
    defer { library.close() }
    let worker: URL
    if args[0] == "hold", args.count == 5 {
        worker = URL(fileURLWithPath: args[4])
        // Verify the spawn allowlist also closes unrelated descriptors lacking FD_CLOEXEC.
        let descriptor = open("/dev/null", O_RDONLY)
        let unrelated = fcntl(descriptor, F_DUPFD, 200)
        close(descriptor)
        setenv("FB_PREVIEW_TEST_PRIVATE_FD", String(unrelated), 1)
    } else {
        worker = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(
            "preview-worker")
    }
    _ = try LibraryPreviewService(workerURL: worker).render(
        library: library, id: args[2], assetsURL: URL(fileURLWithPath: args[3]),
        options: LibraryPreviewOptions(maximumDimension: 128))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("\(error)\n".utf8))
    exit(1)
}
