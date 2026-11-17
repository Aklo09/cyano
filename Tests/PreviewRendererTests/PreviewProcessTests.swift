import Darwin
import Foundation
import Testing

@testable import PreviewRenderer

private func previewBinary(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/debug/\(name)")
}
private struct PreviewTestDirectory {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cyano-preview-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
    func worker(_ mode: String) throws -> URL {
        let path = url.appendingPathComponent("preview-test-" + mode)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: previewBinary("PreviewTestWorker"))
        return path
    }
    func cleanup() { try? FileManager.default.removeItem(at: url) }
}

@Suite("Supervised preview lifecycle", .serialized)
struct PreviewProcessTests {
    private var request: PreviewRequest { PreviewRequest(source: Data([1]), assetsPath: "unused") }

    @Test("Timeout kills and reaps a stalled child before returning")
    func timeout() throws {
        let folder = try PreviewTestDirectory()
        defer { folder.cleanup() }
        let owner = PreviewProcess(workerURL: try folder.worker("wait"))
        let start = Date()
        #expect(throws: PreviewError.timedOut) { try owner.render(request, deadline: 0.1) }
        #expect(Date().timeIntervalSince(start) < 3)
        let pid = try #require(owner.lastWorkerPID)
        #expect(kill(pid, 0) == (-1) && errno == ESRCH)
        #expect(throws: PreviewError.timedOut) { try owner.render(request, deadline: 0.1) }
    }

    @Test("Cancellation and one-active-job exclusion apply across caller threads")
    func cancellation() async throws {
        let folder = try PreviewTestDirectory()
        defer { folder.cleanup() }
        let owner = PreviewProcess(workerURL: try folder.worker("wait"))
        let request = self.request
        let task = Task.detached { () -> PreviewError? in
            do {
                _ = try owner.render(request, deadline: 5)
                return nil
            } catch { return error as? PreviewError }
        }
        let until = Date().addingTimeInterval(2)
        while owner.lastWorkerPID == nil && Date() < until { try await Task.sleep(for: .milliseconds(10)) }
        #expect(owner.lastWorkerPID != nil)
        #expect(throws: PreviewError.workerBusy) { try owner.render(request, deadline: 1) }
        owner.cancel()
        #expect(await task.value == .cancelled)
    }

    @Test("Crashes, malformed results, and oversized responses are rejected")
    func badWorkers() throws {
        let folder = try PreviewTestDirectory()
        defer { folder.cleanup() }
        for mode in ["crash", "malformed", "large"] {
            let owner = PreviewProcess(workerURL: try folder.worker(mode))
            #expect(throws: PreviewError.self) { try owner.render(request, deadline: 5) }
        }
    }

    @Test("Malformed or truncated input cannot activate the production worker")
    func badInput() throws {
        let process = Process()
        let input = Pipe()
        let errors = Pipe()
        process.executableURL = previewBinary("preview-worker")
        process.standardInput = input
        process.standardError = errors
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data([255, 255, 255, 255, 255, 255, 255, 255]))
        try input.fileHandleForWriting.close()
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0)
        #expect(throws: PreviewError.invalidInput) {
            try PreviewProcess(workerURL: previewBinary("preview-worker")).render(
                PreviewRequest(source: Data([1]), assetsPath: "unused", maximumDimension: 8192))
        }
    }

    @Test("Resident memory enforcement terminates and reaps the child")
    func memoryCeiling() throws {
        let folder = try PreviewTestDirectory()
        defer { folder.cleanup() }
        let owner = PreviewProcess(workerURL: try folder.worker("wait"), residentLimit: 1)
        #expect(throws: PreviewError.memoryLimit) { try owner.render(request, deadline: 3) }
    }

    @Test("The worker exits when its parent dies after installing the pipe lifeline")
    func parentDeath() throws {
        let parent = Process()
        let output = Pipe()
        parent.executableURL = previewBinary("PreviewTestWorker")
        parent.arguments = ["parent"]
        parent.standardOutput = output
        try parent.run()
        defer {
            if parent.isRunning {
                kill(parent.processIdentifier, SIGKILL)
                parent.waitUntilExit()
            }
        }
        var line = Data()
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let readyDeadline = Date().addingTimeInterval(3)
        while line.last != 10 && Date() < readyDeadline {
            var byte: UInt8 = 0
            if Darwin.read(descriptor, &byte, 1) == 1 {
                line.append(byte)
            } else {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        let pid = try #require(
            Int32(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == 0)
        kill(parent.processIdentifier, SIGKILL)
        parent.waitUntilExit()
        let until = Date().addingTimeInterval(3)
        while kill(pid, 0) == 0 && Date() < until { Thread.sleep(forTimeInterval: 0.01) }
        #expect(kill(pid, 0) == (-1) && errno == ESRCH)
    }
}
