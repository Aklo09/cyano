import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func encoded(_ json: String) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private struct ExportFixture {
    let parent: URL
    let url: URL
    let rootBytes: Data
    let bookId: String

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("fb-native-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        let book = try encoded(
            """
            {"blueprint_book":{"version":1,"label":"Rail/Book: 1","blueprints":[
              {"index":4,"blueprint":{"version":1,"label":"Stop","extra":12345678901234567890}}]}}
            """)
        rootBytes = Data("  \r\n".utf8) + book + Data("\r\n\t".utf8)
        bookId = try library.importSource(rootBytes).id
    }

    func exported(_ entryPath: [Int] = []) throws -> Data {
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        return try library.export(id: bookId, entryPath: entryPath)
    }

    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
private func openBrowser(_ fixture: ExportFixture) async -> (LibrarySession, LibraryBrowserModel, () -> [String]) {
    let session = LibrarySession()
    await session.open(fixture.url)
    let browser = LibraryBrowserModel(session: session)
    browser.listingChanged()
    var copied: [String] = []
    browser.pasteboardWriter = { copied.append($0) }
    return (session, browser, { copied })
}

@MainActor
@Suite("Export", .serialized)
struct ExportActionsTests {
    @Test("EXP-1, EXP-2: Copy String copies exact root bytes, or an entry's standalone string inside a book")
    func copy() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let entryBytes = try fixture.exported([4])
        let (session, browser, copied) = await openBrowser(fixture)
        #expect(browser.exportTarget == nil)
        browser.selection = ["item:" + fixture.bookId]
        let name = try #require(session.listing?.items.first?.name)
        #expect(browser.exportTarget?.fileName == name + ".txt")
        #expect(ExportTarget(itemId: "", entryPath: [4], name: "Rail/Book: 1").fileName == "Rail-Book- 1.txt")
        await browser.copySelectedString()
        #expect(copied().map { Data($0.utf8) } == [fixture.rootBytes])
        #expect(browser.confirmation == "Copied blueprint string")

        await browser.openSelection()
        #expect(browser.exportTarget == nil)
        browser.selection = ["entry:4"]
        #expect(browser.exportTarget == ExportTarget(itemId: fixture.bookId, entryPath: [4], name: "Stop"))
        await browser.copySelectedString()
        #expect(copied().last.map { Data($0.utf8) } == entryBytes)
        #expect(entryBytes != fixture.rootBytes)
        await session.close()
    }

    @Test("EXP-3, EXP-4: Save As TXT writes the export bytes; replacing moves the previous file to the Trash")
    func save() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let (session, browser, _) = await openBrowser(fixture)
        browser.selection = ["item:" + fixture.bookId]
        let target = try #require(browser.exportTarget)
        let destination = fixture.parent.appendingPathComponent("Export.txt")
        #expect(await browser.save(target, to: destination) == .saved(bytes: fixture.rootBytes.count))
        #expect(try Data(contentsOf: destination) == fixture.rootBytes)
        #expect(browser.confirmation == "Saved “Export.txt”")

        let previous = Data("previous contents \(UUID().uuidString)".utf8)
        try previous.write(to: destination)
        #expect(await browser.save(target, to: destination) == .saved(bytes: fixture.rootBytes.count))
        #expect(try Data(contentsOf: destination) == fixture.rootBytes)
        let trash = try #require(ProcessInfo.processInfo.environment["FB_NATIVE_TRASH_DIRECTORY"])
        let trashed = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: trash), includingPropertiesForKeys: nil)
        #expect(trashed.contains { (try? Data(contentsOf: $0)) == previous })
        await session.close()
    }

    @Test("EXP-5: a destination inside the library, directly or through a link, is refused without writing")
    func insideLibrary() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let (session, browser, _) = await openBrowser(fixture)
        browser.selection = ["item:" + fixture.bookId]
        let target = try #require(browser.exportTarget)
        let inside = fixture.url.appendingPathComponent("library/Inside.txt")
        #expect(await browser.save(target, to: inside) == .insideLibrary)
        #expect(!FileManager.default.fileExists(atPath: inside.path))
        // Replacing a stored file (the save panel's Replace) is refused before anything moves to the Trash.
        let stored = try #require(
            FileManager.default.contentsOfDirectory(
                at: fixture.url.appendingPathComponent("library"), includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "txt" })
        #expect(await browser.save(target, to: stored) == .insideLibrary)
        #expect(try Data(contentsOf: stored) == fixture.rootBytes)
        let alias = fixture.parent.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.url)
        #expect(await browser.save(target, to: alias.appendingPathComponent("Linked.txt")) == .insideLibrary)
        #expect(!FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent("Linked.txt").path))
        await session.close()
    }

    @Test("EXP-6: a failed save leaves no file at the destination, and a replaced file comes back")
    func failures() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let (session, browser, _) = await openBrowser(fixture)
        let missingFolder = fixture.parent.appendingPathComponent("Missing/Export.txt")
        let target = ExportTarget(itemId: fixture.bookId, entryPath: [], name: "Book")
        guard case .failed(let message) = await browser.save(target, to: missingFolder) else {
            Issue.record("saving into a missing folder succeeded")
            return
        }
        #expect(message.title == "The file wasn't saved")
        #expect(!FileManager.default.fileExists(atPath: missingFolder.path))

        let existing = fixture.parent.appendingPathComponent("Keep.txt")
        let kept = Data("keep me".utf8)
        try kept.write(to: existing)
        let gone = ExportTarget(itemId: UUID().uuidString.lowercased(), entryPath: [], name: "Gone")
        guard case .failed = await browser.save(gone, to: existing) else {
            Issue.record("exporting a missing item succeeded")
            return
        }
        #expect(try Data(contentsOf: existing) == kept)
        await session.close()
    }
}
