import Darwin
import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func encoded(_ label: String) throws -> Data {
    let json =
        #"{"blueprint":{"item":"blueprint","label":"\#(label)","entities":[{"entity_number":1,"#
        + #""name":"wooden-chest","position":{"x":0.5,"y":0.5}}],"version":1}}"#
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

/// A stand-in worker that records its process ID and blocks: a render that is in progress until it is cancelled.
/// Workers start with an empty environment, so it uses absolute paths, and `exec` keeps the recorded ID.
private struct BlockingWorker {
    let url: URL
    let pidFile: URL

    init(in directory: URL) throws {
        url = directory.appendingPathComponent("blocking-worker")
        pidFile = directory.appendingPathComponent("worker.pid")
        let script = "#!/bin/sh\necho $$ > '\(pidFile.path)'\nexec /bin/sleep 60\n"
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    var pid: Int32? {
        (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap {
            Int32($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno != ESRCH }
}

/// Write phases where a quit arrives during an import; `entered` is set from the library queue.
private final class SlowWrite: @unchecked Sendable {
    let phase: LibraryWritePhase
    private let lock = NSLock()
    private var armedValue = false
    private var enteredValue = false
    init(at phase: LibraryWritePhase) { self.phase = phase }

    var armed: Bool {
        get { lock.withLock { armedValue } }
        set { lock.withLock { armedValue = newValue } }
    }
    var entered: Bool { lock.withLock { enteredValue } }

    var opener: LibraryOpener {
        LibraryOpener(
            open: { url in
                try NativeLibrary.testingOpen(at: url) { [self] current in
                    guard current == phase, armed else { return }
                    lock.withLock { enteredValue = true }
                    // The quit blocks the main actor while it closes, so the pause is timed, not signalled.
                    Thread.sleep(forTimeInterval: 0.4)
                }
            },
            initialize: { try NativeLibrary.initialize(at: $0) },
            inspectOperations: { try NativeLibrary.inspectOperations(at: $0) })
    }
}

@MainActor
private final class LifecycleFixture {
    let parent: URL
    let url: URL
    let suite: String
    let defaults: UserDefaults
    let worker: BlockingWorker
    let release: URL
    var itemId = ""

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        itemId = try library.importSource(encoded("Chest")).id
        suite = "local.fb.library.tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        worker = try BlockingWorker(in: parent)
        release = try AppTestAssetRelease(in: parent).root
    }

    /// A selection model with the library open, the release chosen, and a render blocked in the worker.
    func renderingModel() async throws -> (LibrarySelectionModel, PreviewViewer, Int32) {
        let model = LibrarySelectionModel(
            defaults: defaults, previewBackend: .standard(workerURL: worker.url))
        await model.assets.choose(release, library: url)
        await model.chooseFolderToOpen(url)
        #expect(model.session.libraryURL != nil)
        let viewer = PreviewViewer()
        model.previews.show(
            PreviewSubject(libraryPath: url.path, itemId: itemId, entryPath: []), in: viewer)
        for _ in 0..<3000 where worker.pid == nil { try await Task.sleep(for: .milliseconds(10)) }
        let pid = try #require(worker.pid, "the render never started a worker")
        #expect(BlockingWorker.isAlive(pid) && viewer.state == .rendering && model.previews.isRendering)
        return (model, viewer, pid)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: parent)
    }
}

@MainActor
@Suite("Lifecycle", .serialized)
struct LifecycleTests {
    @Test("LIFE-1: closing the library cancels the render, reaps its worker, and releases ownership")
    func closeDuringRender() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanup() }
        let (model, _, pid) = try await fixture.renderingModel()
        let started = Date()
        await model.closeLibrary()
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(!BlockingWorker.isAlive(pid))
        #expect(try NativeLibrary.inspectOwnership(at: fixture.url) == .idle)
        #expect(model.session.libraryURL == nil && model.windowGoal == .selection)
        // Closing the library window forgets it for the next launch.
        #expect(model.reopenCandidate == nil)
        for _ in 0..<200 where model.previews.isRendering { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.previews.isRendering)
        // No preview was published for the cancelled render.
        let cache = fixture.url.appendingPathComponent("cache/\(fixture.itemId)")
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test("LIFE-2: quitting during a render reaps the worker and releases the library, which reopens next launch")
    func quitDuringRender() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanup() }
        let (model, _, pid) = try await fixture.renderingModel()
        let started = Date()
        model.prepareForTermination()
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(!BlockingWorker.isAlive(pid))
        #expect(try NativeLibrary.inspectOwnership(at: fixture.url) == .idle)
        #expect(model.reopenCandidate?.path == fixture.url.path)
        // The library window disappearing while quitting neither closes nor forgets the library.
        #expect(await model.libraryWindowDisappeared() == false)
        #expect(model.reopenCandidate?.path == fixture.url.path)
        guard case .failure = await model.session.perform(.changing, { _ in 1 }) else {
            Issue.record("a call after quitting reached the library")
            return
        }
    }

    @Test(
        "LIFE-3: quitting during an import finishes it; the library reopens with nothing to recover",
        arguments: [LibraryWritePhase.sourceStaged, .metadataPublished])
    func quitDuringChange(phase: LibraryWritePhase) async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanup() }
        let slow = SlowWrite(at: phase)
        let model = LibrarySelectionModel(session: LibrarySession(opener: slow.opener), defaults: fixture.defaults)
        await model.chooseFolderToOpen(fixture.url)
        #expect(model.session.libraryURL != nil)
        slow.armed = true
        let bytes = try encoded("Late")
        let importing = Task { await model.session.perform(.importing) { try $0.importSource(bytes) } }
        for _ in 0..<3000 where !slow.entered { try await Task.sleep(for: .milliseconds(10)) }
        #expect(slow.entered)
        model.prepareForTermination()
        #expect(try NativeLibrary.inspectOwnership(at: fixture.url) == .idle)
        _ = await importing.value

        #expect(try NativeLibrary.inspectOperations(at: fixture.url).filter { $0.state == "committed" }.isEmpty)
        let reopened = try NativeLibrary(at: fixture.url)
        defer { reopened.close() }
        #expect(reopened.completedOnOpen.isEmpty && !reopened.requiresRecovery)
        #expect(try reopened.list().items.map(\.name).sorted() == ["Chest", "Late"])
    }
}
