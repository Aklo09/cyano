import Darwin
import Foundation
@_spi(Testing) @testable import LibraryCore
import Testing

private struct TemporaryLibrary {
    let parent: URL
    let url: URL

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("fb-native-storage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
    }

    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

private func blueprintFixture(_ name: String = "RS.txt") throws -> Data {
    let url = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures/Blueprints/\(name)"))
    return try Data(contentsOf: url)
}

private func binary(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/\(name)")
}

private func child(_ name: String, _ args: [String]) throws -> (Int32, Data, Data) {
    let process = Process()
    process.executableURL = binary(name)
    process.arguments = args
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let stderr = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, data, stderr)
}

@Suite("Native library storage", .serialized)
struct NativeLibraryTests {
    @Test("Initialize, import, comment, close, reopen, and export exact original bytes")
    func completeSourceWorkflow() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        #expect(try NativeLibrary.inspectOwnership(at: target.url) == .uninitialized)
        #expect(!FileManager.default.fileExists(atPath: target.url.path))
        let library = try NativeLibrary.initialize(at: target.url)
        #expect(try library.list().items.isEmpty)
        #expect(try NativeLibrary.inspectOwnership(at: target.url) == .owned)
        var bytes = Data("\r\n  ".utf8)
        bytes.append(try blueprintFixture())
        bytes.append(Data(" \r\n".utf8))
        let item = try library.importSource(bytes, name: "Original")
        let updated = try library.addComment(id: item.id, text: "Plain text\r\n[font=default-bold]retained[/font]")
        #expect(updated.id == item.id)
        #expect(updated.metadata.createdAt == item.metadata.createdAt)
        #expect(updated.metadata.comments.count == 1)
        #expect(try library.export(id: item.id) == bytes)
        library.close(); library.close()
        #expect(throws: NativeLibraryError.closed) { try library.list() }
        #expect(try NativeLibrary.inspectOwnership(at: target.url) == .idle)
        let reopened = try NativeLibrary(at: target.url); defer { reopened.close() }
        let restored = try #require(reopened.list().items.first)
        #expect(restored.metadata == updated.metadata)
        #expect(try reopened.export(id: item.id) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.url.appendingPathComponent("operations").path).isEmpty)
    }

    @Test("Book entry comments and standalone exports use actual stored paths")
    func bookPaths() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url); defer { library.close() }
        let bytes = try blueprintFixture("v0.59.0.txt")
        let item = try library.importSource(bytes)
        let updated = try library.addComment(id: item.id, entryPath: [1, 1], text: "Large leaf")
        #expect(updated.metadata.comments.first?.entryPath == [1, 1])
        let entry = try BlueprintCodec.decode(library.export(id: item.id, entryPath: [1, 1]))
        #expect(entry.root.body["entities"]?.array?.count == 6814)
        #expect(throws: BlueprintCodecError.self) { try library.addComment(id: item.id, entryPath: [99999], text: "Invalid") }
        #expect(try library.export(id: item.id) == bytes)
    }

    @Test("Unknown nonempty stores, unsupported formats, and missing permanent locks are untouched")
    func formatAdmission() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        try FileManager.default.createDirectory(at: target.url, withIntermediateDirectories: false)
        let foreign = target.url.appendingPathComponent("foreign.txt")
        try Data("Keep me".utf8).write(to: foreign)
        #expect(throws: NativeLibraryError.invalidFormat) { try NativeLibrary.initialize(at: target.url) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.url.path) == ["foreign.txt"])
        #expect(try Data(contentsOf: foreign) == Data("Keep me".utf8))
        let bare = target.parent.appendingPathComponent("BareLock")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: false)
        try Data().write(to: bare.appendingPathComponent(".owner.lock"))
        #expect(throws: NativeLibraryError.invalidFormat) { try NativeLibrary.initialize(at: bare) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: bare.path) == [".owner.lock"])

        let native = target.parent.appendingPathComponent("Native")
        let library = try NativeLibrary.initialize(at: native)
        library.close()
        try FileManager.default.removeItem(at: native.appendingPathComponent(".owner.lock"))
        #expect(throws: NativeLibraryError.unsafePath) { try NativeLibrary.initialize(at: native) }
        #expect(throws: NativeLibraryError.unsafePath) { try NativeLibrary.inspectOwnership(at: native) }
        #expect(!FileManager.default.fileExists(atPath: native.appendingPathComponent(".owner.lock").path))
        let marker = native.appendingPathComponent(".library-format.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any])
        json["schemaVersion"] = 99
        let unknown = try JSONSerialization.data(withJSONObject: json)
        try unknown.write(to: marker)
        #expect(throws: NativeLibraryError.unsupportedVersion) { try NativeLibrary(at: native) }
        #expect(try Data(contentsOf: marker) == unknown)
    }

    @Test("Duplicate import names suffix safely and real empty folders remain visible")
    func namingAndFolders() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let initialized = try NativeLibrary.initialize(at: target.url)
        initialized.close()
        let empty = target.url.appendingPathComponent("library/Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        let library = try NativeLibrary(at: target.url); defer { library.close() }
        let source = try blueprintFixture()
        let first = try library.importSource(source, name: "Same")
        let second = try library.importSource(source, name: "same")
        #expect(first.basename == "Same")
        #expect(second.basename == "same (2)")
        #expect(first.id != second.id)
        let nested = try library.importSource(source, name: "[color=red]Safe[/color]/Name", folder: "Empty")
        #expect(nested.basename == "Safe Name")
        let list = try library.list()
        #expect(list.items.count == 3)
        #expect(list.folders == ["Empty"])
        #expect(list.issues.isEmpty)
        #expect(throws: NativeLibraryError.self) { try library.importSource(source, folder: "../escape") }
        let unicode = try library.importSource(source, name: "É")
        let normalized = try library.importSource(source, name: "E\u{301}")
        #expect(unicode.basename == "É")
        #expect(normalized.basename == "É (2)")
        #expect(LibraryNames.basename(label: String(repeating: "\u{301}", count: 10000), kind: .blueprint) == "Untitled Blueprint")
    }

    @Test("Symlinks, hardlinks, FIFOs, and changed control inodes are refused")
    func unsafeFilesystemObjects() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let remote = try #require(URL(string: "file://remote.invalid/private/tmp/Library"))
        #expect(throws: NativeLibraryError.unsafePath) { try NativeLibrary.initialize(at: remote) }
        let nul = try #require(URL(string: target.parent.absoluteString + "/Unsafe%00tail"))
        #expect(throws: NativeLibraryError.unsafePath) { try NativeLibrary.initialize(at: nul) }
        #expect(!FileManager.default.fileExists(atPath: target.parent.appendingPathComponent("Unsafe").path))
        let library = try NativeLibrary.initialize(at: target.url)
        let outside = target.parent.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let link = target.url.appendingPathComponent("library/Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(throws: NativeLibraryError.self) { try library.importSource(blueprintFixture(), folder: "Linked") }
        #expect(try library.list().issues.contains { $0.path == "Linked" })
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        let pipe = target.parent.appendingPathComponent("source.fifo")
        try #require(mkfifo(pipe.path, 0o600) == 0)
        #expect(throws: NativeLibraryError.unsafePath) { try NativeLibrary.readSourceFile(at: pipe) }
        let item = try library.importSource(blueprintFixture(), name: "Hardlink")
        let live = target.url.appendingPathComponent("library/Hardlink.txt")
        try FileManager.default.linkItem(at: live, to: target.parent.appendingPathComponent("alias.txt"))
        #expect(throws: NativeLibraryError.self) { try library.export(id: item.id) }
        let lock = target.url.appendingPathComponent(".owner.lock")
        try FileManager.default.moveItem(at: lock, to: target.url.appendingPathComponent("old-lock"))
        try Data().write(to: lock)
        #expect(throws: NativeLibraryError.unsafePath) { try library.list() }
        library.close()
    }

    @Test("Another process and a symlink alias cannot overlap the live owner")
    func processExclusion() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let initialized = try NativeLibrary.initialize(at: target.url); initialized.close()
        let process = Process()
        process.executableURL = binary("StorageTestDriver")
        process.arguments = ["hold", target.url.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        #expect(String(data: output.fileHandleForReading.availableData, encoding: .utf8) == "ready\n")
        #expect(throws: NativeLibraryError.inUse) { try NativeLibrary(at: target.url) }
        let alias = target.parent.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target.url)
        #expect(throws: NativeLibraryError.inUse) { try NativeLibrary(at: alias) }
        #expect(try NativeLibrary.inspectOwnership(at: alias) == .owned)
        let refusal = try child("fb-native", ["list", target.url.path])
        #expect(refusal.0 == 3)
        #expect(refusal.1.isEmpty)
        let probe = try child("fb-native", ["owner", target.url.path])
        #expect(probe.0 == 0)
        #expect(String(decoding: probe.1, as: UTF8.self).contains("owned"))
        process.terminate(); process.waitUntilExit()
        let reopened = try NativeLibrary(at: target.url); reopened.close()
    }

    @Test("Real process kills at import publication boundaries recover deterministically")
    func importInterruptions() throws {
        let before: [LibraryWritePhase] = [.sourceStaged, .metadataStaged]
        let after: [LibraryWritePhase] = [.intentPublished, .sourcePublished, .metadataPublished, .intentRemoved]
        for phase in before + after {
            let target = try TemporaryLibrary(); defer { target.cleanup() }
            let initialized = try NativeLibrary.initialize(at: target.url); initialized.close()
            let input = target.parent.appendingPathComponent("input.txt")
            let bytes = try blueprintFixture()
            try bytes.write(to: input)
            let killed = try child("StorageTestDriver", ["import-crash", target.url.path, input.path, phase.rawValue])
            #expect(killed.0 == SIGKILL, Comment(rawValue: phase.rawValue))
            let reopened = try NativeLibrary(at: target.url)
            let items = try reopened.list().items
            if before.contains(phase) { #expect(items.isEmpty) }
            else {
                #expect(items.count == 1)
                #expect(try reopened.export(id: #require(items.first?.id)) == bytes)
            }
            try reopened.recover()
            reopened.close()
            let again = try NativeLibrary(at: target.url); defer { again.close() }
            #expect(try again.list().items.count == items.count)
        }
    }

    @Test("Comments interrupted before or after their intent preserve identity and exact source")
    func commentInterruptions() throws {
        for phase in [LibraryWritePhase.metadataStaged, .intentPublished, .metadataPublished, .intentRemoved] {
            let target = try TemporaryLibrary(); defer { target.cleanup() }
            let initialized = try NativeLibrary.initialize(at: target.url)
            let bytes = try blueprintFixture()
            let item = try initialized.importSource(bytes)
            initialized.close()
            let killed = try child("StorageTestDriver", ["comment-crash", target.url.path, item.id, phase.rawValue])
            #expect(killed.0 == SIGKILL)
            let reopened = try NativeLibrary(at: target.url); defer { reopened.close() }
            let updated = try #require(reopened.list().items.first)
            #expect(updated.id == item.id)
            #expect(updated.metadata.createdAt == item.metadata.createdAt)
            #expect(updated.metadata.comments.count == (phase == .metadataStaged ? 0 : 1))
            #expect(try reopened.export(id: item.id) == bytes)
        }
    }

    @Test("Conflicting published bytes block recovery and preserve staged originals")
    func recoveryConflict() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let initialized = try NativeLibrary.initialize(at: target.url); initialized.close()
        let input = target.parent.appendingPathComponent("input.txt")
        let bytes = try blueprintFixture()
        try bytes.write(to: input)
        _ = try child("StorageTestDriver", ["import-crash", target.url.path, input.path, "sourcePublished"])
        let live = target.url.appendingPathComponent("library/Interrupted.txt")
        let foreign = Data("Unexpected live bytes".utf8)
        try foreign.write(to: live)
        #expect(throws: NativeLibraryError.integrity) { try NativeLibrary(at: target.url) }
        #expect(try Data(contentsOf: live) == foreign)
        let operations = target.url.appendingPathComponent("operations")
        let stage = try #require(FileManager.default.contentsOfDirectory(at: operations, includingPropertiesForKeys: nil).first)
        #expect(try Data(contentsOf: stage.appendingPathComponent("source.txt")) == bytes)
        #expect(FileManager.default.fileExists(atPath: stage.appendingPathComponent("intent.json").path))
    }

    @Test("Unknown sidecar fields, corrupt hashes, and oversized source reads remain non-mutating")
    func metadataAndReadLimits() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url)
        let item = try library.importSource(blueprintFixture(), name: "Metadata")
        library.close()
        let sidecar = target.url.appendingPathComponent("library/Metadata.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any])
        json["future"] = true
        let unknown = try JSONSerialization.data(withJSONObject: json)
        try unknown.write(to: sidecar)
        let reopened = try NativeLibrary(at: target.url); defer { reopened.close() }
        #expect(try reopened.list().items.isEmpty)
        #expect(try reopened.list().issues.contains { $0.code == "INVALID_METADATA" })
        #expect(throws: NativeLibraryError.notFound) { try reopened.addComment(id: item.id, text: "Must not overwrite") }
        #expect(try Data(contentsOf: sidecar) == unknown)
        let large = target.parent.appendingPathComponent("large.txt")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(BlueprintCodecLimits.standard.sourceBytes + 1))
        try handle.close()
        #expect(throws: NativeLibraryError.limitExceeded) { try NativeLibrary.readSourceFile(at: large) }
    }

    @Test("Initialization interrupted after marker publication resumes without changing its identity")
    func initializationInterruption() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let killed = try child("StorageTestDriver", ["initialize-crash", target.url.path, "formatPublished"])
        #expect(killed.0 == SIGKILL)
        let marker = target.url.appendingPathComponent(".library-format.json")
        let bytes = try Data(contentsOf: marker)
        let reopened = try NativeLibrary(at: target.url); defer { reopened.close() }
        #expect(try reopened.list().items.isEmpty)
        #expect(try Data(contentsOf: marker) == bytes)
    }

    @Test("Concurrent comments serialize complete read-modify-write operations")
    func concurrentComments() throws {
        final class Failures: @unchecked Sendable {
            let lock = NSLock()
            var values: [String] = []
            func add(_ error: Error) { lock.lock(); defer { lock.unlock() }; values.append(String(describing: error)) }
        }
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let library = try NativeLibrary.initialize(at: target.url); defer { library.close() }
        let item = try library.importSource(blueprintFixture())
        let failures = Failures()
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            do { _ = try library.addComment(id: item.id, text: "Comment \(index)") }
            catch { failures.add(error) }
        }
        #expect(failures.values.isEmpty)
        let metadata = try #require(library.list().items.first?.metadata)
        #expect(metadata.comments.count == 8)
        #expect(Set(metadata.comments.map(\.text)).count == 8)
        #expect(metadata.createdAt == item.metadata.createdAt)
    }

    @Test("The CLI emits versioned JSON and exact-byte stdout exports")
    func cliWorkflow() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let input = target.parent.appendingPathComponent("input.txt")
        var bytes = Data("\r\n ".utf8)
        bytes.append(try blueprintFixture()); bytes.append(Data("\r\n".utf8))
        try bytes.write(to: input)
        let probe = try child("fb-native", ["owner", target.url.path])
        #expect(probe.0 == 0)
        #expect(!FileManager.default.fileExists(atPath: target.url.path))
        #expect(try child("fb-native", ["init", target.url.path]).0 == 0)
        let imported = try child("fb-native", ["import", target.url.path, input.path, "--name", "CLI"])
        #expect(imported.0 == 0)
        #expect(imported.2.isEmpty)
        let envelope = try #require(JSONSerialization.jsonObject(with: imported.1) as? [String: Any])
        #expect(envelope["schema"] as? Int == 1)
        #expect(envelope["ok"] as? Bool == true)
        let result = try #require(envelope["result"] as? [String: Any])
        let id = try #require(result["id"] as? String)
        #expect(try child("fb-native", ["comment", target.url.path, id, "CLI note"]).0 == 0)
        let exported = try child("fb-native", ["export", target.url.path, id])
        #expect(exported.0 == 0)
        #expect(exported.1 == bytes)
        #expect(exported.2.isEmpty)
        #expect(try child("fb-native", ["recover", target.url.path]).0 == 0)
        let invalid = try child("fb-native", ["export", target.url.path, id, "--entry", "../bad"])
        #expect(invalid.0 == 2)
        #expect(invalid.1.isEmpty)
        let failure = try #require(JSONSerialization.jsonObject(with: invalid.2) as? [String: Any])
        #expect(failure["ok"] as? Bool == false)
        #expect((failure["error"] as? [String: Any])?["category"] as? String == "arguments")
    }

    @Test("Damaged live hashes and unsupported metadata are reported without overwriting evidence")
    func damagedMetadataAndSources() throws {
        let target = try TemporaryLibrary(); defer { target.cleanup() }
        let original = try NativeLibrary.initialize(at: target.url)
        let first = try original.importSource(blueprintFixture(), name: "Source")
        _ = try original.importSource(blueprintFixture(), name: "Version")
        original.close()
        let sourceURL = target.url.appendingPathComponent("library/Source.txt")
        let damaged = Data("Unknown source bytes".utf8)
        try damaged.write(to: sourceURL)
        let metadataURL = target.url.appendingPathComponent("library/Version.json")
        var metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any])
        metadata["schemaVersion"] = 99
        let future = try JSONSerialization.data(withJSONObject: metadata)
        try future.write(to: metadataURL)
        let library = try NativeLibrary(at: target.url); defer { library.close() }
        let listing = try library.list()
        #expect(listing.items.isEmpty)
        #expect(Set(listing.issues.map(\.code)).isSuperset(of: ["INTEGRITY_CONFLICT", "UNSUPPORTED_VERSION"]))
        #expect(throws: NativeLibraryError.notFound) { try library.addComment(id: first.id, text: "Must not replace") }
        #expect(try Data(contentsOf: sourceURL) == damaged)
        #expect(try Data(contentsOf: metadataURL) == future)
    }
}
