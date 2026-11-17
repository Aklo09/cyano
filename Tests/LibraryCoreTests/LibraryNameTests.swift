import Foundation
import Testing

@_spi(Testing) @testable import LibraryCore

/// A scratch directory on the system temporary volume, which is case-insensitive APFS by default.
private struct InsensitiveVolume {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

/// A freshly created case-sensitive APFS disk image, attached privately at a unique mount point.
private struct SensitiveVolume {
    let parent: URL
    let root: URL
    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-cs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let image = parent.appendingPathComponent("volume.dmg").path
        root = parent.appendingPathComponent("mount")
        do {
            try Self.run(
                "/usr/bin/hdiutil",
                ["create", "-quiet", "-size", "32m", "-fs", "Case-sensitive APFS", "-volname", "fbcs", image])
            try Self.run("/usr/sbin/diskutil", ["image", "attach", "--nobrowse", "--mountPoint", root.path, image])
        } catch {
            try? FileManager.default.removeItem(at: parent)
            throw error
        }
    }
    func cleanup() {
        try? Self.run("/usr/bin/hdiutil", ["detach", "-force", root.path])
        try? FileManager.default.removeItem(at: parent)
    }
    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "\(tool) \(arguments) failed"])
        }
    }
}

private func nameSource(_ label: String) throws -> Data {
    let json = "{\"blueprint\":{\"version\":1,\"label\":\"\(label)\"}}"
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

/// Exercises every name-creating operation with names that APFS case-insensitive volumes treat as equal
/// but that simple lowercasing distinguishes, then reopens the library.
private func checkCollisions(at url: URL) throws {
    let library = try NativeLibrary.initialize(at: url)
    _ = try library.createFolder(name: "Straße")
    #expect(throws: NativeLibraryError.nameCollision) { try library.createFolder(name: "STRASSE") }
    _ = try library.createFolder(name: "σ")
    #expect(throws: NativeLibraryError.nameCollision) { try library.createFolder(name: "ς") }
    _ = try library.createFolder(name: "в")
    #expect(throws: NativeLibraryError.nameCollision) { try library.createFolder(name: "\u{1C80}") }  // folds to в

    let first = try library.importSource(nameSource("Fluß"))
    let second = try library.importSource(nameSource("FLUSS"))
    #expect(first.basename == "Fluß" && second.basename == "FLUSS (2)")

    let moved = try library.importSource(nameSource("Moved"), folder: "σ")
    _ = try library.importSource(nameSource("ff"), folder: "σ")
    #expect(throws: NativeLibraryError.nameCollision) { _ = try library.renameItem(id: moved.id, name: "\u{FB00}") }
    #expect(throws: NativeLibraryError.nameCollision) { _ = try library.moveFolder("в", parent: "", name: "STRASSE") }
    _ = try library.importSource(nameSource("Fluss"), folder: "Straße")
    #expect(throws: NativeLibraryError.nameCollision) { _ = try library.moveItem(id: first.id, folder: "Straße") }

    // A rename that differs only under case folding is allowed for the item's own name.
    #expect(try library.renameItem(id: first.id, name: "FLUSS").basename == "FLUSS")
    #expect(try library.moveFolder("Straße", parent: "", name: "STRASSE") == "STRASSE")
    library.close()

    let reopened = try NativeLibrary(at: url)
    defer { reopened.close() }
    let listing = try reopened.list()
    #expect(listing.issues.isEmpty)
    #expect(Set(listing.folders) == ["STRASSE", "σ", "в"])
}

@Suite("Volume-independent name collisions")
struct LibraryNameTests {
    @Test("Collision keys follow APFS case-insensitive equivalence, including full case folding")
    func keys() {
        let equal = [
            ("File", "file"), ("Straße", "STRASSE"), ("ß", "ẞ"), ("σ", "ς"), ("Σ", "ς"), ("ﬀ", "FF"),
            ("\u{1C80}", "В"), ("\u{1C88}", "\u{A64A}"), ("é", "e\u{301}"), ("İ", "i\u{307}"), ("ǅ", "ǆ"), ("K", "k"),
            ("Ω", "ω"), ("\u{10400}", "\u{10428}"),
        ]
        for (left, right) in equal {
            #expect(LibraryNames.key(left) == LibraryNames.key(right), "\(left) / \(right)")
        }
        for (left, right) in [("a", "b"), ("e", "é"), ("ss", "s"), ("в", "б")] {
            #expect(LibraryNames.key(left) != LibraryNames.key(right), "\(left) / \(right)")
        }
    }

    @Test("Folded names collide on a case-insensitive volume without breaking the library")
    func insensitiveVolume() throws {
        let volume = try InsensitiveVolume()
        defer { volume.cleanup() }
        try checkCollisions(at: volume.root.appendingPathComponent("Library"))
    }

    @Test("Folded names collide identically on a case-sensitive volume")
    func sensitiveVolume() throws {
        let volume = try SensitiveVolume()
        defer { volume.cleanup() }
        try checkCollisions(at: volume.root.appendingPathComponent("Library"))
    }

    @Test("Existing folded duplicates on a case-sensitive volume become listing issues")
    func existingDuplicates() throws {
        let volume = try SensitiveVolume()
        defer { volume.cleanup() }
        let url = volume.root.appendingPathComponent("Library")
        try NativeLibrary.initialize(at: url).close()
        for name in ["Straße", "STRASSE", "Other"] {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("library/\(name)"), withIntermediateDirectories: false)
        }
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        let listing = try library.list()
        #expect(listing.folders == ["Other"])
        #expect(Set(listing.issues.map(\.path)) == ["Straße", "STRASSE"])
        #expect(listing.issues.allSatisfy { $0.code == NativeLibraryError.integrity.code })
    }
}
