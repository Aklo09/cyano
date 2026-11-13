import Darwin
import Foundation
import Testing

@_spi(Testing) @testable import LibraryCore
@testable import PreviewRenderer

private struct PreviewLibrary {
    let parent: URL
    let root: URL
    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-owned-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        root = parent.appendingPathComponent("Library")
    }
    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}
private func ownedBinary(_ name: String = "preview-worker") -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/debug/\(name)")
}
private func ownedChild(_ name: String, _ args: [String], environment: [String: String] = [:]) throws -> (
    Int32, Data, Data
) {
    let process = Process()
    let out = Pipe()
    let err = Pipe()
    process.executableURL = ownedBinary(name)
    process.arguments = args
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let bytes = out.fileHandleForReading.readDataToEndOfFile()
    let errors = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, bytes, errors)
}
private final class PreviewStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didEnter = false
    let release = DispatchSemaphore(value: 0)
    var hasEntered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didEnter
    }
    func arriveAndWait() {
        lock.lock()
        didEnter = true
        lock.unlock()
        release.wait()
    }
}

@Suite("Owned library preview integration", .serialized)
struct LibraryPreviewTests {
    let options = LibraryPreviewOptions(maximumDimension: 128)

    @Test("Close before worker launch remains cancelled and never starts a child")
    func closeBeforeLaunch() async throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let initial = try NativeLibrary.initialize(at: target.root)
        let item = try initial.importSource(renderSource())
        initial.close()
        let gate = PreviewStartGate()
        let library = try NativeLibrary.testingOpen(at: target.root) { phase in
            if phase == .previewWorkerStarting { gate.arriveAndWait() }
        }
        let service = LibraryPreviewService(workerURL: ownedBinary())
        let settings = options
        let render = Task.detached { () -> PreviewError? in
            do {
                _ = try service.render(library: library, id: item.id, assetsURL: assets.root, options: settings)
                return nil
            } catch { return error as? PreviewError }
        }
        let readyDeadline = Date().addingTimeInterval(3)
        while !gate.hasEntered && Date() < readyDeadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.hasEntered)
        let closing = Task.detached { library.close() }
        let deadline = Date().addingTimeInterval(3)
        while !library.isClosing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(library.isClosing)
        gate.release.signal()
        await closing.value
        #expect(await render.value == .cancelled)
        #expect(service.lastWorkerPID == nil)
        #expect(try NativeLibrary.inspectOwnership(at: target.root) == .idle)
    }

    @Test("Book preview keys use actual sparse indices without rewriting the book or its scoped notes")
    func sparseEntries() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        defer { library.close() }
        let leafJSON = try BlueprintCodec.decode(renderSource()).root.value.encoded(maximum: 1_000_000)
        var nestedLeaf = try #require(JSONSerialization.jsonObject(with: leafJSON) as? [String: Any])
        nestedLeaf["index"] = 0
        var directLeaf = nestedLeaf
        directLeaf["index"] = 9
        let book: [String: Any] = [
            "blueprint_book": [
                "version": 1,
                "blueprints": [
                    ["index": 5, "blueprint_book": ["version": 1, "blueprints": [nestedLeaf]]], directLeaf,
                ],
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: book)
        let bytes = Data(("0" + (try ZlibCodec.compress(data, maximum: 1_000_000)).base64EncodedString()).utf8)
        let item = try library.importSource(bytes)
        let commented = try library.addComment(id: item.id, entryPath: [5, 0], text: "Sparse leaf")
        let service = LibraryPreviewService(workerURL: ownedBinary())
        let nested = try service.render(
            library: library, id: item.id, entryPath: [5, 0], assetsURL: assets.root, options: options)
        let direct = try service.render(
            library: library, id: item.id, entryPath: [9], assetsURL: assets.root, options: options)
        #expect(nested.key != direct.key)
        #expect(nested.preview.report.entryPath == [5, 0])
        #expect(
            try service.render(
                library: library, id: item.id, entryPath: [5, 0], assetsURL: assets.root, options: options
            ).cacheHit)
        #expect(try library.export(id: item.id) == bytes)
        #expect(try library.list().items.first?.metadata == commented.metadata)
    }

    @Test("Cache links and asset overlap are rejected before a worker or cache publication")
    func confinedPaths() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        defer { library.close() }
        let item = try library.importSource(renderSource())
        let cache = target.root.appendingPathComponent("cache/\(item.id)")
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: assets.root)
        let service = LibraryPreviewService(workerURL: ownedBinary())
        #expect(throws: NativeLibraryError.unsafePath) {
            try service.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        }
        #expect(service.lastWorkerPID == nil)
        try FileManager.default.removeItem(at: cache)
        let overlap = target.root.appendingPathComponent("cache/Assets")
        try FileManager.default.copyItem(at: assets.root, to: overlap)
        #expect(throws: NativeLibraryError.unsafePath) {
            try service.render(library: library, id: item.id, assetsURL: overlap, options: options)
        }
        #expect(service.lastWorkerPID == nil)
        #expect(try library.export(id: item.id) == renderSource())
    }

    @Test("Cache hits require no worker and preserve originals, comments, identities, and metadata")
    func reuse() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        defer { library.close() }
        var bytes = Data("\r\n ".utf8)
        bytes.append(try renderSource())
        bytes.append(Data(" \r\n".utf8))
        let item = try library.importSource(bytes)
        let service = LibraryPreviewService(workerURL: ownedBinary())
        let first = try service.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        #expect(!first.cacheHit)
        let imageURL = target.root.appendingPathComponent(first.cachePath)
        let metadataURL = imageURL.deletingPathExtension().appendingPathExtension("json")
        let cacheMetadata = try Data(contentsOf: metadataURL)
        let imageDate = try imageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let commented = try library.addComment(id: item.id, text: "Keep this note")
        let authoritative = target.root.appendingPathComponent("library/\(item.basename).json")
        let metadataBefore = try Data(contentsOf: authoritative)
        let withoutWorker = LibraryPreviewService(workerURL: target.parent.appendingPathComponent("missing-worker"))
        let second = try withoutWorker.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        #expect(second.cacheHit && second.key == first.key && second.preview.png == first.preview.png)
        #expect(withoutWorker.lastWorkerPID == nil)
        #expect(try Data(contentsOf: metadataURL) == cacheMetadata)
        #expect(
            try imageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == imageDate)
        #expect(try Data(contentsOf: authoritative) == metadataBefore)
        #expect(try library.export(id: item.id) == bytes)
        #expect(try library.list().items.first?.metadata == commented.metadata)
        #expect(try library.cleanupCache().selection.isEmpty)
    }

    @Test("Settings distinguish cache identities; source replacement and item deletion invalidate all variants")
    func invalidation() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        defer { library.close() }
        let item = try library.importSource(renderSource())
        let service = LibraryPreviewService(workerURL: ownedBinary())
        let first = try service.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        let other = try service.render(
            library: library, id: item.id, assetsURL: assets.root,
            options: LibraryPreviewOptions(maximumDimension: 256, checkerboard: true))
        #expect(first.key != other.key)
        #expect(
            try library.cleanupCache(
                scope: .obsolete, assetIdentity: first.preview.report.assetIdentity, generator: options.generator
            ).selection.count == 2)
        _ = try library.renameItem(id: item.id, name: "Renamed")
        #expect(try service.render(library: library, id: item.id, assetsURL: assets.root, options: options).cacheHit)
        let changed = Data(" \n".utf8) + (try renderSource())
        _ = try library.updateSource(id: item.id, bytes: changed)
        let cache = target.root.appendingPathComponent("cache/\(item.id)")
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        let updated = try service.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        #expect(!updated.cacheHit && updated.key != first.key)
        try library.deleteItem(id: item.id)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test("Known corrupt images regenerate; unknown metadata versions stay protected")
    func corruption() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        defer { library.close() }
        let item = try library.importSource(renderSource())
        let service = LibraryPreviewService(workerURL: ownedBinary())
        let first = try service.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        let image = target.root.appendingPathComponent(first.cachePath)
        try Data([1]).write(to: image)
        let repaired = try service.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        #expect(!repaired.cacheHit && repaired.preview.png == first.preview.png)
        let metadata = image.deletingPathExtension().appendingPathExtension("json")
        var record = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        record["schemaVersion"] = 99
        let future = try JSONSerialization.data(withJSONObject: record)
        try future.write(to: metadata)
        #expect(throws: NativeLibraryError.unsupportedVersion) {
            try service.render(library: library, id: item.id, assetsURL: assets.root, options: options)
        }
        #expect(try Data(contentsOf: metadata) == future)
        #expect(try library.cleanupCache().selection.isEmpty)
        #expect(try library.cleanupCache(scope: .all, apply: true).selection.count == 2)
    }

    @Test("Library close cancels, kills, and reaps a blocked renderer before releasing ownership")
    func closeDuringRender() async throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        let item = try library.importSource(renderSource())
        let fake = target.parent.appendingPathComponent("preview-test-wait")
        try FileManager.default.createSymbolicLink(at: fake, withDestinationURL: ownedBinary("PreviewTestWorker"))
        let service = LibraryPreviewService(workerURL: fake)
        let settings = options
        let task = Task.detached { () -> PreviewError? in
            do {
                _ = try service.render(library: library, id: item.id, assetsURL: assets.root, options: settings)
                return nil
            } catch { return error as? PreviewError }
        }
        let deadline = Date().addingTimeInterval(3)
        while service.lastWorkerPID == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let pid = try #require(service.lastWorkerPID)
        #expect(try NativeLibrary.inspectOwnership(at: target.root) == .owned)
        #expect(throws: NativeLibraryError.inUse) { try NativeLibrary(at: target.root) }
        #expect(throws: PreviewError.workerBusy) {
            try service.render(library: library, id: item.id, assetsURL: assets.root)
        }
        let start = Date()
        library.close()
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(await task.value == .cancelled)
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(try NativeLibrary.inspectOwnership(at: target.root) == .idle)
        let reopened = try NativeLibrary(at: target.root)
        defer { reopened.close() }
        #expect(try reopened.export(id: item.id) == renderSource())
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: target.root.appendingPathComponent("cache").path)
                .isEmpty)
    }

    @Test("Library reads and mutations complete while a render is in flight")
    func operationsDuringRender() async throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        let item = try library.importSource(renderSource())
        let other = try library.importSource(Data(" ".utf8) + (try renderSource()), name: "Other")
        let fake = target.parent.appendingPathComponent("preview-test-wait")
        try FileManager.default.createSymbolicLink(at: fake, withDestinationURL: ownedBinary("PreviewTestWorker"))
        let service = LibraryPreviewService(workerURL: fake)
        let settings = options
        let task = Task.detached { () -> PreviewError? in
            do {
                _ = try service.render(library: library, id: item.id, assetsURL: assets.root, options: settings)
                return nil
            } catch { return error as? PreviewError }
        }
        let deadline = Date().addingTimeInterval(3)
        while service.lastWorkerPID == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        _ = try #require(service.lastWorkerPID)
        let start = Date()
        #expect(try library.list().items.count == 2)
        _ = try library.addComment(id: other.id, text: "Written during a render")
        _ = try library.renameItem(id: item.id, name: "Renamed during a render")
        #expect(Date().timeIntervalSince(start) < 2)
        library.close()
        #expect(await task.value == .cancelled)
    }

    @Test("A source replaced or deleted during rendering is never published")
    func sourceChangedDuringRender() async throws {
        for deleting in [false, true] {
            let target = try PreviewLibrary()
            defer { target.cleanup() }
            let assets = try SyntheticPreviewAssets()
            defer { assets.cleanup() }
            let library = try NativeLibrary.initialize(at: target.root)
            defer { library.close() }
            let item = try library.importSource(renderSource())
            let fake = target.parent.appendingPathComponent("preview-test-gated")
            try FileManager.default.createSymbolicLink(at: fake, withDestinationURL: ownedBinary("PreviewTestWorker"))
            let service = LibraryPreviewService(workerURL: fake)
            let settings = options
            let task = Task.detached { () -> NativeLibraryError? in
                do {
                    _ = try service.render(library: library, id: item.id, assetsURL: assets.root, options: settings)
                    return nil
                } catch { return error as? NativeLibraryError }
            }
            let deadline = Date().addingTimeInterval(3)
            while service.lastWorkerPID == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            _ = try #require(service.lastWorkerPID)
            if deleting {
                try library.deleteItem(id: item.id)
            } else {
                _ = try library.updateSource(id: item.id, bytes: Data(" \n".utf8) + (try renderSource()))
            }
            FileManager.default.createFile(atPath: target.parent.appendingPathComponent("gate").path, contents: Data())
            #expect(await task.value == .sourceChanged, "deleting: \(deleting)")
            let cache = target.root.appendingPathComponent("cache/\(item.id)")
            let published = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
            #expect(published.isEmpty, "deleting: \(deleting)")
        }
    }

    @Test("An orphaned noncooperating helper holds no lease or unrelated descriptor and does not keep ownership")
    func orphanedHelper() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        let item = try library.importSource(renderSource())
        library.close()
        let fake = target.parent.appendingPathComponent("preview-test-orphan")
        try FileManager.default.createSymbolicLink(at: fake, withDestinationURL: ownedBinary("PreviewTestWorker"))
        let ready = target.parent.appendingPathComponent("ready.json")
        let parent = Process()
        let errorPipe = Pipe()
        parent.executableURL = ownedBinary("LibraryPreviewTestDriver")
        parent.arguments = ["hold", target.root.path, item.id, assets.root.path, fake.path]
        parent.environment = ProcessInfo.processInfo.environment.merging(["FB_PREVIEW_TEST_READY": ready.path]) {
            _, new in new
        }
        parent.standardError = errorPipe
        try parent.run()
        var child: Int32?
        defer {
            if let child { kill(child, SIGKILL) }
            if parent.isRunning {
                kill(parent.processIdentifier, SIGKILL)
                parent.waitUntilExit()
            }
        }
        let deadline = Date().addingTimeInterval(4)
        while !FileManager.default.fileExists(atPath: ready.path) && parent.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let record = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ready)) as? [String: Any])
        child = try #require((record["pid"] as? NSNumber)?.int32Value)
        #expect(record["descriptor3"] as? Bool == false)
        #expect(record["unrelated"] as? Bool == false)
        kill(parent.processIdentifier, SIGKILL)
        parent.waitUntilExit()
        // The helper outlives its parent, yet the library is immediately available to a new owner.
        #expect(kill(child!, 0) == 0)
        #expect(try NativeLibrary.inspectOwnership(at: target.root) == .idle)
        let reopened = try NativeLibrary(at: target.root)
        #expect(try reopened.export(id: item.id) == renderSource())
        reopened.close()
    }

    @Test("A worker's descendants cannot keep its pipes or the library owned after the leader exits")
    func descendants() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        let item = try library.importSource(renderSource())
        library.close()
        let fake = target.parent.appendingPathComponent("preview-test-descendant")
        try FileManager.default.createSymbolicLink(at: fake, withDestinationURL: ownedBinary("PreviewTestWorker"))
        let ready = target.parent.appendingPathComponent("descendant.json")
        let response = try ownedChild(
            "LibraryPreviewTestDriver", ["hold", target.root.path, item.id, assets.root.path, fake.path],
            environment: ["FB_PREVIEW_TEST_READY": ready.path])
        #expect(response.0 != 0)
        let value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ready)) as? [String: Any])
        let pid = try #require((value["pid"] as? NSNumber)?.int32Value)
        let until = Date().addingTimeInterval(3)
        while kill(pid, 0) == 0 && Date() < until { Thread.sleep(forTimeInterval: 0.01) }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(try NativeLibrary.inspectOwnership(at: target.root) == .idle)
    }

    @Test(
        "Process death at every derived-cache publication boundary leaves originals intact and permits reuse or regeneration"
    )
    func cacheCrashes() throws {
        for phase in [
            "previewImageStaged", "previewManifestStaged", "previewImagePublished", "previewManifestPublished",
        ] {
            let target = try PreviewLibrary()
            defer { target.cleanup() }
            let assets = try SyntheticPreviewAssets()
            defer { assets.cleanup() }
            let library = try NativeLibrary.initialize(at: target.root)
            let bytes = try renderSource()
            let item = try library.importSource(bytes)
            let metadataURL = target.root.appendingPathComponent("library/\(item.basename).json")
            let before = try Data(contentsOf: metadataURL)
            library.close()
            let result = try ownedChild(
                "LibraryPreviewTestDriver", ["cache-crash", target.root.path, item.id, assets.root.path, phase])
            #expect(result.0 == SIGKILL, "\(phase): \(String(decoding: result.2, as: UTF8.self))")
            let reopened = try NativeLibrary(at: target.root)
            defer { reopened.close() }
            #expect(try reopened.export(id: item.id) == bytes)
            #expect(try Data(contentsOf: metadataURL) == before)
            let preview = try LibraryPreviewService(workerURL: ownedBinary()).render(
                library: reopened, id: item.id, assetsURL: assets.root, options: options)
            #expect(preview.cacheHit == (phase == "previewManifestPublished"))
            let cleaned = try reopened.cleanupCache(apply: true)
            #expect(cleaned.selection.allSatisfy { $0.reason == "abandoned-temporary" })
            #expect(try reopened.cleanupCache().selection.isEmpty)
        }
    }

    @Test("CLI preview returns cache metadata without emitting PNG bytes and supports explicit refresh")
    func cli() throws {
        let target = try PreviewLibrary()
        defer { target.cleanup() }
        let assets = try SyntheticPreviewAssets()
        defer { assets.cleanup() }
        let library = try NativeLibrary.initialize(at: target.root)
        let item = try library.importSource(renderSource())
        library.close()
        let arguments = ["preview", target.root.path, item.id, "--assets", assets.root.path, "--max-dimension", "128"]
        for (extra, hit) in [([], false), ([], true), (["--refresh"], false)] {
            let response = try ownedChild("fb-native", arguments + extra)
            #expect(response.0 == 0, "\(String(decoding: response.2, as: UTF8.self))")
            let json = try #require(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
            let result = try #require(json["result"] as? [String: Any])
            #expect(result["cacheHit"] as? Bool == hit)
            #expect(result["png"] == nil && result["cachePath"] as? String != nil)
        }
        #expect(try ownedChild("fb-native", ["preview", target.root.path, item.id]).0 == 2)
    }
}
