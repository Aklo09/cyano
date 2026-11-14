import CoreGraphics
import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore
@testable import PreviewRenderer

private func encoded(_ json: String) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private func blueprint(_ label: String, empty: Bool = false) -> String {
    let entities =
        empty ? "" : #","entities":[{"entity_number":1,"name":"wooden-chest","position":{"x":0.5,"y":0.5}}]"#
    return #"{"blueprint":{"item":"blueprint","label":"\#(label)""# + entities + #","version":1}}"#
}

private func tinyImage() -> PreviewImage {
    let context = CGContext(
        data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return PreviewImage(image: context.makeImage()!)
}

/// A backend that never starts a worker: renders wait until the test finishes them, and record their order and
/// how many ran at once.
private final class FakeRenders: @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [String: DispatchSemaphore] = [:]
    private var failures: [String: Error] = [:]
    private var cachedIds: Set<String> = []
    private var startedIds: [String] = []
    private var cancelledIds: [String] = []
    private var running = 0
    private var peakRunning = 0

    var started: [String] { locked { startedIds } }
    var cancelled: [String] { locked { cancelledIds } }
    var peak: Int { locked { peakRunning } }

    func cache(_ id: String) { locked { _ = cachedIds.insert(id) } }
    func fail(_ id: String, with error: Error) { locked { failures[id] = error } }

    /// Lets the oldest unfinished render of `id` return.
    func finish(_ id: String) { locked { gates[id] }?.signal() }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var backend: PreviewBackend {
        PreviewBackend(
            lookup: { library, job in
                let entry = try library.entry(id: job.itemId, entryPath: job.entryPath)
                if PreviewBackend.isEmptyBlueprint(entry) { return .nothingToDraw }
                return self.locked { self.cachedIds.contains(job.itemId) } ? .cached(tinyImage()) : .needsRender
            },
            render: { _, job, token in
                let gate = DispatchSemaphore(value: 0)
                self.locked {
                    self.gates[job.itemId] = gate
                    self.startedIds.append(job.itemId)
                    self.running += 1
                    self.peakRunning = max(self.peakRunning, self.running)
                }
                defer { self.locked { self.running -= 1 } }
                while gate.wait(timeout: .now() + 0.01) == .timedOut {
                    if token.isCancelled {
                        self.locked { self.cancelledIds.append(job.itemId) }
                        throw PreviewError.cancelled
                    }
                }
                if let failure = self.locked({ self.failures.removeValue(forKey: job.itemId) }) { throw failure }
                return tinyImage()
            })
    }
}

@MainActor
private final class PreviewFixture {
    let parent: URL
    let url: URL
    let suite: String
    let session = LibrarySession()
    let assets: AssetSettings
    let renders = FakeRenders()
    let center: PreviewCenter
    var ids: [String: String] = [:]

    /// `standardBackend` uses the app's real lookup with no worker in place of the fake renders.
    init(release: Bool = true, standardBackend: Bool = false) async throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-previews-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        for name in ["A", "B", "C"] { ids[name] = try library.importSource(encoded(blueprint(name))).id }
        ids["Empty"] = try library.importSource(encoded(blueprint("Empty", empty: true))).id
        let book = """
            {"blueprint_book":{"item":"blueprint-book","label":"Book","version":1,"blueprints":[
              {"index":3,"blueprint":\(blueprint("Inner").dropFirst(13).dropLast())}]}}
            """
        ids["Book"] = try library.importSource(encoded(book)).id
        library.close()
        suite = "local.fb.library.tests-\(UUID().uuidString)"
        assets = AssetSettings(defaults: try #require(UserDefaults(suiteName: suite)))
        if release { await assets.choose(try AppTestAssetRelease(in: parent).root, library: url) }
        center = PreviewCenter(
            session: session, assets: assets,
            backend: standardBackend ? .standard(workerURL: nil) : renders.backend)
        await session.open(url)
    }

    func subject(_ name: String, _ entryPath: [Int] = []) -> PreviewSubject {
        PreviewSubject(libraryPath: url.path, itemId: ids[name] ?? name, entryPath: entryPath)
    }

    func cleanup() {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: parent)
    }
}

/// Waits up to 30 s for asynchronous scheduling to reach `condition`; library writes force data to disk and can take
/// seconds while other test targets run alongside.
@MainActor
private func until(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<3000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(condition())
}

private func isReady(_ state: PreviewState) -> Bool {
    if case .ready = state { return true }
    return false
}

@MainActor
@Suite("Previews", .serialized)
struct PreviewCenterTests {
    @Test("PRV-5, PRV-7: one render at a time in request order; viewers of the same entry share one render")
    func orderAndSharing() async throws {
        let fixture = try await PreviewFixture()
        defer { fixture.cleanup() }
        let (inspector, other, window) = (PreviewViewer(), PreviewViewer(), PreviewViewer())
        fixture.center.show(fixture.subject("A"), in: inspector)
        await until { fixture.renders.started == [fixture.ids["A"]!] }
        fixture.center.show(fixture.subject("B"), in: other)
        await until { other.state == .waiting }
        fixture.center.show(fixture.subject("A"), in: window)
        #expect(inspector.state == .rendering && window.state == .rendering)

        fixture.renders.finish(fixture.ids["A"]!)
        await until { isReady(inspector.state) && isReady(window.state) }
        #expect(inspector.state == window.state)
        await until { fixture.renders.started == [fixture.ids["A"]!, fixture.ids["B"]!] }
        #expect(other.state == .rendering)
        fixture.renders.finish(fixture.ids["B"]!)
        await until { isReady(other.state) }
        #expect(fixture.center.renderCount == 2)
        #expect(fixture.center.peakConcurrentRenders == 1 && fixture.renders.peak == 1)
    }

    @Test("PRV-6: a dropped waiting request leaves the render alone; a dropped render is cancelled and the next starts")
    func dropping() async throws {
        let fixture = try await PreviewFixture()
        defer { fixture.cleanup() }
        let (first, second, third) = (PreviewViewer(), PreviewViewer(), PreviewViewer())
        fixture.center.show(fixture.subject("A"), in: first)
        await until { fixture.renders.started.count == 1 }
        fixture.center.show(fixture.subject("B"), in: second)
        fixture.center.show(fixture.subject("C"), in: third)
        await until { second.state == .waiting && third.state == .waiting }

        fixture.center.release(second)
        #expect(second.state == .none)
        #expect(first.state == .rendering && fixture.renders.cancelled.isEmpty)

        fixture.center.show(nil, in: first)
        #expect(first.state == .none)
        await until { fixture.renders.started == [fixture.ids["A"]!, fixture.ids["C"]!] }
        #expect(fixture.renders.cancelled == [fixture.ids["A"]!])
        #expect(third.state == .rendering)
        fixture.renders.finish(fixture.ids["C"]!)
        await until { isReady(third.state) }
        #expect(fixture.center.renderCount == 2 && fixture.center.peakConcurrentRenders == 1)
    }

    @Test("PRV-2, PRV-12: cached previews and empty blueprints are shown without a render")
    func withoutRendering() async throws {
        let fixture = try await PreviewFixture()
        defer { fixture.cleanup() }
        fixture.renders.cache(fixture.ids["A"]!)
        let (cached, empty) = (PreviewViewer(), PreviewViewer())
        fixture.center.show(fixture.subject("A"), in: cached)
        fixture.center.show(fixture.subject("Empty"), in: empty)
        await until { isReady(cached.state) && empty.state == .nothingToDraw }
        #expect(fixture.center.renderCount == 0 && fixture.renders.started.isEmpty)
    }

    @Test("PRV-9: without an asset release, previews say so and never render")
    func noRelease() async throws {
        let fixture = try await PreviewFixture(release: false)
        defer { fixture.cleanup() }
        let viewer = PreviewViewer()
        fixture.center.show(fixture.subject("A"), in: viewer)
        #expect(viewer.state == .noAssets)
        fixture.center.show(fixture.subject("Book", [3]), in: viewer)
        #expect(viewer.state == .noAssets)
        #expect(fixture.center.renderCount == 0)
    }

    @Test("PRV-11: deleted items and missing book entries say so; book entries render by stored index")
    func deleted() async throws {
        let fixture = try await PreviewFixture()
        defer { fixture.cleanup() }
        let viewer = PreviewViewer()
        fixture.center.show(fixture.subject("Book", [7]), in: viewer)
        await until { viewer.state == .deleted(entry: true) }
        fixture.center.show(fixture.subject("Book", [3]), in: viewer)
        await until { viewer.state == .rendering }
        fixture.renders.finish(fixture.ids["Book"]!)
        await until { isReady(viewer.state) }

        let id = fixture.ids["A"]!
        _ = await fixture.session.perform(.changing) { try $0.deleteItem(id: id) }
        fixture.center.show(fixture.subject("A"), in: viewer)
        #expect(viewer.state == .deleted(entry: false))
    }

    @Test("PRV-10: a failed render gives the reason and Retry renders again")
    func failureAndRetry() async throws {
        let fixture = try await PreviewFixture()
        defer { fixture.cleanup() }
        let viewer = PreviewViewer()
        fixture.renders.fail(fixture.ids["A"]!, with: PreviewError.timedOut)
        fixture.center.show(fixture.subject("A"), in: viewer)
        await until { fixture.renders.started.count == 1 }
        fixture.renders.finish(fixture.ids["A"]!)
        await until {
            if case .failed = viewer.state { return true }
            return false
        }
        guard case .failed(let message) = viewer.state else { return }
        #expect(message.title == "The preview took too long" && message.code == "PREVIEW_TIMEOUT")
        fixture.center.retry(viewer)
        await until { fixture.renders.started.count == 2 && viewer.state == .rendering }
        fixture.renders.finish(fixture.ids["A"]!)
        await until { isReady(viewer.state) }
        #expect(fixture.center.renderCount == 2)
    }

    @Test("SET-5a, SET-6: clearing the release cancels the render and shows the no-assets state")
    func releaseCleared() async throws {
        let fixture = try await PreviewFixture()
        defer { fixture.cleanup() }
        let viewer = PreviewViewer()
        fixture.center.show(fixture.subject("A"), in: viewer)
        await until { fixture.renders.started.count == 1 }
        fixture.assets.clear()
        // The preview area asks again when the release's revision changes.
        fixture.center.show(fixture.subject("A"), in: viewer)
        #expect(viewer.state == .noAssets)
        await until { fixture.renders.cancelled == [fixture.ids["A"]!] && !fixture.center.isRendering }
        #expect(viewer.state == .noAssets)
    }

    @Test("PRV-12, PRV-10: the app's lookup finds empty blueprints itself, and a missing worker asks to reinstall")
    func standardBackend() async throws {
        let fixture = try await PreviewFixture(standardBackend: true)
        defer { fixture.cleanup() }
        let (empty, full) = (PreviewViewer(), PreviewViewer())
        fixture.center.show(fixture.subject("Empty"), in: empty)
        await until { empty.state == .nothingToDraw }
        fixture.center.show(fixture.subject("A"), in: full)
        await until {
            if case .failed = full.state { return true }
            return false
        }
        guard case .failed(let message) = full.state else { return }
        #expect(message.guidance == "The app's preview renderer is missing. Reinstall the app.")
        #expect(fixture.center.renderCount == 1)
        fixture.center.show(fixture.subject("Book", [3]), in: full)
        await until {
            if case .failed = full.state { return true }
            return false
        }
        fixture.center.show(fixture.subject("Book", [8]), in: full)
        await until { full.state == .deleted(entry: true) }
    }

    @Test("PRV-5: library calls are not held up by a render")
    func libraryCallsDuringRender() async throws {
        let fixture = try await PreviewFixture()
        defer { fixture.cleanup() }
        let viewer = PreviewViewer()
        fixture.center.show(fixture.subject("A"), in: viewer)
        await until { fixture.renders.started.count == 1 }
        let id = fixture.ids["B"]!
        let outcome = await fixture.session.perform(.commenting) { try $0.addComment(id: id, text: "While rendering") }
        guard case .success = outcome else {
            Issue.record("\(outcome)")
            return
        }
        #expect(viewer.state == .rendering)
        fixture.renders.finish(fixture.ids["A"]!)
        await until { isReady(viewer.state) }
    }
}

@Suite("Preview viewport")
struct PreviewViewportTests {
    @Test("PRV-8: fitting follows resizes until the owner zooms or pans")
    func fitting() {
        var viewport = PreviewViewport(
            imageSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 200, height: 200))
        #expect(viewport.fitting && viewport.scale == 0.5)
        viewport.resize(to: CGSize(width: 400, height: 400))
        #expect(viewport.fitting && viewport.scale == 1)
        viewport.zoomIn()
        #expect(!viewport.fitting && viewport.scale == 1.25)
        viewport.resize(to: CGSize(width: 800, height: 800))
        #expect(viewport.scale == 1.25)
        viewport.fit()
        #expect(viewport.fitting && viewport.scale == 2)
        viewport.pan(by: CGSize(width: 10, height: 0))
        #expect(!viewport.fitting)
        let tiny = PreviewViewport(imageSize: CGSize(width: 10, height: 10), viewSize: CGSize(width: 800, height: 800))
        #expect(tiny.scale == PreviewViewport.maximumFitScale)
    }

    @Test("PRV-8: zooming keeps the image point under the pointer; Actual Size and Fit alternate on double-click")
    func zoomAndToggle() {
        var viewport = PreviewViewport(
            imageSize: CGSize(width: 400, height: 400), viewSize: CGSize(width: 200, height: 200))
        let pointer = CGPoint(x: 150, y: 50)
        func imagePoint(_ v: PreviewViewport) -> CGPoint {
            CGPoint(x: (pointer.x - v.imageFrame.minX) / v.scale, y: (pointer.y - v.imageFrame.minY) / v.scale)
        }
        let before = imagePoint(viewport)
        viewport.zoom(to: 2, around: pointer)
        let after = imagePoint(viewport)
        #expect(abs(after.x - before.x) < 0.001 && abs(after.y - before.y) < 0.001)
        #expect(viewport.percentage == 200)

        viewport.fit()
        viewport.toggleFit()
        #expect(viewport.scale == 1 && !viewport.fitting)
        viewport.toggleFit()
        #expect(viewport.fitting && viewport.scale == 0.5)
        viewport.zoom(to: 1000, around: nil)
        #expect(viewport.scale == PreviewViewport.maximumScale)
    }

    @Test("PRV-8: panning keeps the middle of the view over the image; arrows pan by a tenth or a screen")
    func panning() {
        var viewport = PreviewViewport(
            imageSize: CGSize(width: 400, height: 400), viewSize: CGSize(width: 200, height: 200))
        viewport.actualSize()
        viewport.pan(direction: (1, 0), page: false)
        #expect(viewport.center.x == 220)
        viewport.pan(direction: (1, 0), page: true)
        #expect(viewport.center.x == 400)
        viewport.pan(by: CGSize(width: -10_000, height: 10_000))
        #expect(viewport.center == CGPoint(x: 400, y: 0))
    }
}
