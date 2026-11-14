import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private struct Scratch {
    let parent: URL
    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("fb-native-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    }
    func url(_ name: String = "Library") -> URL { parent.appendingPathComponent(name) }
    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

private func source(_ label: String) throws -> Data {
    let json = "{\"blueprint\":{\"version\":1,\"label\":\"\(label)\"}}"
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private struct Interrupted: Error {}

/// An opener whose libraries throw `Interrupted` at `phase` while `armed` is set, simulating a crash mid-change.
private final class Interrupting: @unchecked Sendable {
    var armed = false
    let phase: LibraryWritePhase
    init(at phase: LibraryWritePhase) { self.phase = phase }
    var opener: LibraryOpener {
        LibraryOpener(
            open: { url in
                try NativeLibrary.testingOpen(at: url) { [self] current in
                    if armed && current == phase { throw Interrupted() }
                }
            },
            initialize: { try NativeLibrary.initialize(at: $0) },
            inspectOperations: { try NativeLibrary.inspectOperations(at: $0) })
    }
}

@MainActor
@Suite("Library session")
struct LibrarySessionTests {
    @Test("Creating, listing, changing, and closing a library; closing releases ownership")
    func lifecycle() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let session = LibrarySession()
        #expect(session.phase == .closed && session.listing == nil)
        await session.open(scratch.url(), create: true)
        #expect(session.libraryURL?.path == scratch.url().path)
        #expect(session.listing?.items.isEmpty == true && session.revision == 1)
        #expect(try NativeLibrary.inspectOwnership(at: scratch.url()) == .owned)

        let created = await session.perform(.changing) { try $0.createFolder(name: "Smelting") }
        guard case .success("Smelting") = created else {
            Issue.record("\(created)")
            return
        }
        #expect(session.listing?.folders == ["Smelting"] && session.revision == 2)

        let collision = await session.perform(.changing) { try $0.createFolder(name: "SMELTING") }
        guard case .failure(let message) = collision else {
            Issue.record("\(collision)")
            return
        }
        #expect(message.code == "NAME_COLLISION" && message.title == "That name already exists here")

        let offMain = await session.perform(.listing, refreshing: false) { _ in Thread.isMainThread }
        guard case .success(false) = offMain else {
            Issue.record("library call ran on the main thread")
            return
        }

        await session.close()
        #expect(session.phase == .closed && session.listing == nil)
        #expect(try NativeLibrary.inspectOwnership(at: scratch.url()) == .idle)
        guard case .failure(let closed) = await session.perform(.changing, { _ in 1 }) else {
            Issue.record("closed session accepted a call")
            return
        }
        #expect(closed.code == "LIBRARY_CLOSED")
    }

    @Test("Open failures: in use, not a library, synchronized location; Try Again succeeds once free")
    func openFailures() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let holder = try NativeLibrary.initialize(at: scratch.url("Trains"))
        let session = LibrarySession()
        await session.open(scratch.url("Trains"))
        guard case .openFailed(_, let inUse) = session.phase else {
            Issue.record("\(session.phase)")
            return
        }
        #expect(inUse.code == "LIBRARY_IN_USE" && inUse.title == "“Trains” is in use")
        holder.close()
        await session.retryOpen()
        #expect(session.libraryURL?.path == scratch.url("Trains").path)
        await session.close()

        let foreign = scratch.url("Foreign")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        try Data("notes".utf8).write(to: foreign.appendingPathComponent("notes.txt"))
        await session.open(foreign, create: true)
        guard case .openFailed(_, let notLibrary) = session.phase else {
            Issue.record("\(session.phase)")
            return
        }
        #expect(notLibrary.code == "INVALID_LIBRARY_FORMAT")
        #expect(try FileManager.default.contentsOfDirectory(atPath: foreign.path) == ["notes.txt"])
    }

    @Test("A refused replay shows the pending operation with its quarantine command, then opens once set aside")
    func recoveryRequired() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let url = scratch.url("O'Brien Library")
        let setup = try NativeLibrary.initialize(at: url)
        _ = try setup.createFolder(name: "Source")
        _ = try setup.importSource(source("Item"), folder: "Source")
        setup.close()
        let interrupting = Interrupting(at: .intentPublished)
        interrupting.armed = true
        let crashed = try interrupting.opener.open(url)
        #expect(throws: Interrupted.self) { _ = try crashed.moveFolder("Source", parent: "", name: "Moved") }
        crashed.close()
        // A look-alike folder makes replay refuse the committed move.
        let folder = url.appendingPathComponent("library/Source")
        let copy = scratch.url("Lookalike")
        try FileManager.default.copyItem(at: folder, to: copy)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: copy, to: folder)

        let session = LibrarySession()
        await session.open(url)
        guard case .recoveryRequired(_, let operations, _, let retried) = session.phase else {
            Issue.record("\(session.phase)")
            return
        }
        #expect(!retried && operations.count == 1 && operations[0].kind == "tree-move")
        #expect(
            operations[0].quarantineCommand
                == "fb-native recover '\(url.path.replacingOccurrences(of: "'", with: "'\\''"))' --quarantine "
                + operations[0].id)

        await session.retryOpen()
        guard case .recoveryRequired(_, _, _, true) = session.phase else {
            Issue.record("\(session.phase)")
            return
        }
        _ = try NativeLibrary.quarantineOperation(at: url, id: operations[0].id)
        await session.retryOpen()
        #expect(session.libraryURL?.path == url.path)
        await session.close()
    }

    @Test("Opening reports a completed interrupted change once; a failed change blocks the session until Recover")
    func completedAndBlocked() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        try NativeLibrary.initialize(at: scratch.url()).close()
        let interrupting = Interrupting(at: .intentPublished)
        let session = LibrarySession(opener: interrupting.opener)
        await session.open(scratch.url())
        #expect(session.completedNotice == nil)

        interrupting.armed = true
        let failed = await session.perform(.importing) { try $0.importSource(source("Pending")) }
        interrupting.armed = false
        guard case .failure = failed else {
            Issue.record("\(failed)")
            return
        }
        #expect(session.requiresRecovery)
        await session.recover()
        #expect(!session.requiresRecovery && session.recoveryFailure == nil)
        #expect(session.listing?.items.map(\.name) == ["Pending"])

        interrupting.armed = true
        _ = await session.perform(.changing) { try $0.createFolder(name: "Interrupted") }
        interrupting.armed = false
        #expect(session.requiresRecovery)
        await session.close()

        await session.open(scratch.url())
        #expect(
            session.completedNotice
                == "A change was interrupted when the library was last used (folder creation or book unpacking). "
                + "It has been completed.")
        #expect(session.listing?.folders == ["Interrupted"])
        session.dismissCompletedNotice()
        #expect(session.completedNotice == nil)
        await session.close()
        await session.open(scratch.url())
        #expect(session.completedNotice == nil)
        await session.close()
    }

    @Test("Overlapping opens leave exactly one library open and release the other; late results are dropped")
    func reentrancy() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        for name in ["First", "Second"] { try NativeLibrary.initialize(at: scratch.url(name)).close() }
        let session = LibrarySession()
        // The two opens may start in either order; whichever starts last must win, with the other released.
        async let first: Void = session.open(scratch.url("First"))
        async let second: Void = session.open(scratch.url("Second"))
        _ = await (first, second)
        let opened = try #require(session.libraryURL?.lastPathComponent)
        let released = opened == "First" ? "Second" : "First"
        #expect(try NativeLibrary.inspectOwnership(at: scratch.url(opened)) == .owned)
        #expect(try NativeLibrary.inspectOwnership(at: scratch.url(released)) == .idle)
        await session.open(scratch.url("Second"))

        async let again: Void = session.open(scratch.url("Second"))
        async let repeated: Void = session.open(scratch.url("Second"))
        _ = await (again, repeated)
        #expect(session.libraryURL?.path == scratch.url("Second").path)

        let slow = Task {
            await session.perform(.changing) { library -> String in
                Thread.sleep(forTimeInterval: 0.2)
                return try library.createFolder(name: "Late")
            }
        }
        while session.pendingCalls == 0 { await Task.yield() }
        await session.close()
        let outcome = await slow.value
        guard case .ignored = outcome else {
            Issue.record("late result was delivered: \(outcome)")
            return
        }
        #expect(session.phase == .closed)
        #expect(try NativeLibrary.inspectOwnership(at: scratch.url("Second")) == .idle)
    }

    @Test("Notices name each kind of interrupted change")
    func noticeWording() {
        #expect(LibrarySession.notice(for: []) == nil)
        for (kind, text) in [
            ("import", "import"), ("comment", "comment"), ("files", "item change"),
            ("tree-create", "folder creation or book unpacking"), ("tree-move", "folder move"),
            ("tree-delete", "folder deletion"), ("unknown", "library change"),
        ] {
            #expect(LibrarySession.describeKind(kind) == text)
        }
        #expect(LibrarySession.shellQuoted("/a b/it's") == "'/a b/it'\\''s'")
    }
}
