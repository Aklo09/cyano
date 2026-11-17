import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func encoded(_ json: String) throws -> String {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return "0" + compressed.base64EncodedString()
}

private func blueprint(_ label: String?) throws -> String {
    let field = label.map { ",\"label\":\"\($0)\"" } ?? ""
    return try encoded("{\"blueprint\":{\"version\":1\(field)}}")
}

private func book(_ label: String) throws -> String {
    try encoded(
        """
        {"blueprint_book":{"version":1,"label":"\(label)","description":"About\\nthe book","blueprints":[
          {"index":2,"blueprint":{"version":1,"label":"Leaf"}}]}}
        """)
}

private struct ImportFixture {
    let parent: URL
    let url: URL

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        _ = try library.createFolder(name: "Trains")
        library.close()
    }

    func file(_ name: String, _ bytes: Data) throws -> URL {
        let file = parent.appendingPathComponent(name)
        try bytes.write(to: file)
        return file
    }

    func stored(_ id: String) throws -> Data {
        let library = try NativeLibrary(at: url)
        defer { library.close() }
        return try library.export(id: id)
    }

    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
private func openBrowser(_ fixture: ImportFixture) async -> (LibrarySession, LibraryBrowserModel) {
    let session = LibrarySession()
    await session.open(fixture.url)
    let browser = LibraryBrowserModel(session: session)
    browser.listingChanged()
    return (session, browser)
}

@MainActor
private func items(_ session: LibrarySession, in folder: String = "") -> [LibraryCore.LibraryItem] {
    (session.listing?.items ?? []).filter { $0.folder == folder }
}

@MainActor
@Suite("Import", .serialized)
struct ImportModelTests {
    @Test("IMP-1, IMP-5: pasted text is stored byte for byte and the new item is selected in its folder")
    func pasteExactBytes() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.show(folder: "Trains")
        let text = "  \r\n" + (try blueprint("Rail stop")) + "\r\n\t "
        browser.beginImport(text: text)
        let sheet = try #require(browser.importSheet)
        #expect(sheet.destination == "Trains")
        await sheet.analyze()
        #expect(sheet.analysis == .valid(kind: .blueprint, entries: nil, label: "Rail stop"))
        #expect(sheet.blocker == nil && sheet.acceptsName)
        await browser.runImport()
        #expect(browser.importSheet == nil)
        let item = try #require(items(session, in: "Trains").first)
        #expect(item.name == "Rail stop" && browser.folder == "Trains" && browser.selection == ["item:" + item.id])
        await session.close()
        #expect(try fixture.stored(item.id) == Data(text.utf8))
    }

    @Test("IMP-2, IMP-3: files keep their exact bytes; several files import one by one with a failure summary")
    func files() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let crlf = Data(((try blueprint("From file")) + "\r\n  \r\n").utf8)
        let good = try fixture.file("good.txt", crlf)
        let other = try fixture.file("other.txt", Data((try blueprint(nil)).utf8))
        let bad = try fixture.file("bad.txt", Data("not a blueprint".utf8))
        let empty = try fixture.file("empty.txt", Data())
        let (session, browser) = await openBrowser(fixture)

        browser.beginImport(files: [good])
        await browser.runImport()
        let imported = try #require(items(session).first)
        #expect(imported.name == "From file" && browser.selection == ["item:" + imported.id])

        browser.beginImport(files: [bad, other, empty], folder: "Trains")
        let sheet = try #require(browser.importSheet)
        #expect(sheet.importTitle == "Import 3 Files" && !sheet.acceptsName && sheet.destination == "Trains")
        await browser.runImport()
        let summary = try #require(browser.importSummary)
        #expect(summary.imported == 1 && summary.total == 3)
        #expect(summary.failures.map(\.name) == ["bad.txt", "empty.txt"])
        #expect(summary.failures[0].reason == "This isn't a blueprint string")
        #expect(items(session, in: "Trains").map(\.name) == ["Untitled Blueprint"])
        #expect(browser.folder == "Trains" && browser.selection.count == 1)
        await session.close()
        #expect(try fixture.stored(imported.id) == crlf)
    }

    @Test("IMP-4, IMP-6: the default destination follows the folder or open book; duplicate names get a suffix")
    func destinationAndDuplicates() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        let bookText = try book("Rail Book")
        browser.show(folder: "Trains")
        browser.beginImport(text: bookText)
        await browser.importSheet?.analyze()
        await browser.runImport()
        let bookItem = try #require(items(session, in: "Trains").first)
        browser.selection = ["item:" + bookItem.id]
        await browser.openSelection()
        #expect(browser.showsBook && browser.importDestination == "Trains")

        browser.beginImport(text: bookText)
        await browser.importSheet?.analyze()
        await browser.runImport()
        #expect(items(session, in: "Trains").map(\.name).sorted() == ["Rail Book", "Rail Book (2)"])

        browser.beginImport(text: try blueprint("Named later"))
        browser.importSheet?.name = "  Chosen name  "
        await browser.importSheet?.analyze()
        await browser.runImport()
        #expect(items(session, in: "Trains").contains { $0.name == "Chosen name" })
        await session.close()
    }

    @Test("IMP-7, IMP-8: invalid, oversized, and empty sources are refused and nothing is created")
    func refusals() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.beginImport(text: "0notbase64!")
        let sheet = try #require(browser.importSheet)
        await sheet.analyze()
        guard case .invalid(let message) = sheet.analysis else {
            Issue.record("\(sheet.analysis)")
            return
        }
        #expect(message.title == "This isn't a blueprint string" && sheet.blocker == message.title)
        #expect(await sheet.run() == nil)

        sheet.text = String(repeating: "0", count: 17 * 1024 * 1024)
        await sheet.analyze()
        if case .invalid(let large) = sheet.analysis {
            #expect(large.title == "This blueprint exceeds the 16 MB string size limit")
        } else {
            Issue.record("oversized string accepted: \(sheet.analysis)")
        }

        sheet.text = ""
        await sheet.analyze()
        #expect(sheet.blocker == "Paste a blueprint string or choose TXT files.")
        sheet.text = " \n\t"
        await sheet.analyze()
        #expect(sheet.blocker == "The pasted text is empty.")
        browser.importSheet = nil

        browser.beginImport(files: [try fixture.file("empty.txt", Data())])
        await browser.runImport()
        #expect(browser.importSheet?.failure?.title == "The file is empty")
        #expect(session.listing?.items.isEmpty == true)
        await session.close()
    }

    @Test("IMP-9 to IMP-12: books unpack into a selected folder tree; non-books are refused; collisions get a suffix")
    func unpacking() async throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.beginImport(text: try book("Smelting"))
        let sheet = try #require(browser.importSheet)
        sheet.mode = .unpack
        await sheet.analyze()
        #expect(!sheet.acceptsName && sheet.blocker == nil)
        await browser.runImport()
        #expect(browser.selection == ["folder:Smelting"])
        #expect(session.listing?.folderComments["Smelting"] == "About\nthe book")
        #expect(items(session, in: "Smelting").map(\.name) == ["2 - Leaf"])

        browser.beginImport(text: try book("Smelting"))
        browser.importSheet?.mode = .unpack
        await browser.importSheet?.analyze()
        await browser.runImport()
        #expect(browser.selection == ["folder:Smelting (2)"])

        browser.beginImport(text: try blueprint("Not a book"))
        let single = try #require(browser.importSheet)
        single.mode = .unpack
        await single.analyze()
        #expect(single.blocker == "Only books can be unpacked.")
        browser.importSheet = nil

        browser.beginImport(files: [try fixture.file("loose.txt", Data((try blueprint("Loose")).utf8))])
        browser.importSheet?.mode = .unpack
        await browser.runImport()
        #expect(browser.importSheet?.failure?.title == "Only books can be unpacked")
        #expect(items(session).isEmpty)
        await session.close()
    }
}
