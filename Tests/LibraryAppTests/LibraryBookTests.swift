import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

/// Factorio 2.0.55 packed as four 16-bit parts.
private let packedVersion2055 = (2 << 48) | (0 << 32) | (55 << 16)

private func encode(_ json: String) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

/// A book stored out of index order with sparse indices, a nested book, both planner kinds, an untitled entry,
/// an empty nested book, descriptions with line breaks, and unknown fields.
private func sparseBook() throws -> Data {
    try encode(
        """
        {"blueprint_book":{"version":\(packedVersion2055),"label":"Rail Book","description":"Line one\\nLine two",
          "future_field":{"kept":true},"blueprints":[
          {"index":9,"blueprint":{"version":\(packedVersion2055),"label":"Depot","description":"Depot notes"}},
          {"index":0,"blueprint":{"version":\(packedVersion2055),"label":"Stop 1","unknown":12345678901234567890}},
          {"index":5,"blueprint_book":{"version":\(packedVersion2055),"label":"Stations","blueprints":[
            {"index":3,"blueprint":{"version":\(packedVersion2055),"label":"Stop 2"}},
            {"index":7,"blueprint_book":{"version":\(packedVersion2055),"label":"Empty","blueprints":[]}}]}},
          {"index":12,"upgrade_planner":{"version":\(packedVersion2055),"label":"Belts","settings":{
            "description":"Upgrade\\nall belts","mappers":[
              {"index":0,"from":{"type":"entity","name":"transport-belt"},"to":{"type":"entity","name":"fast-transport-belt"}}]}}},
          {"index":14,"deconstruction_planner":{"version":\(packedVersion2055),"settings":{
            "entity_filter_mode":1,"entity_filters":[{"index":1,"name":"stone-wall"}],"trees_and_rocks_only":false}}},
          {"index":20,"blueprint":{"version":0,"label":"Ancient"}},
          {"index":21,"blueprint":{"version":1,"label":"[item=iron-plate,quality=legendary]Iron plate [virtual-signal=signal-A]"}},
          {"index":22,"blueprint":{"version":1,"label":"[item=iron-plate]"}}]}}
        """)
}

private struct BookFixture {
    let parent: URL
    let url: URL
    let bookId: String
    let bytes: Data

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-books-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        _ = try library.createFolder(name: "Trains")
        bytes = try sparseBook()
        bookId = try library.importSource(bytes, folder: "Trains").id
        _ = try library.importSource(
            encode(#"{"blueprint_book":{"version":1,"label":"Hollow","blueprints":[]}}"#), folder: "Trains")
    }

    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
private func open(_ fixture: BookFixture) async -> (LibrarySession, LibraryBrowserModel) {
    let session = LibrarySession()
    await session.open(fixture.url)
    let browser = LibraryBrowserModel(session: session)
    browser.listingChanged()
    browser.show(folder: "Trains")
    return (session, browser)
}

@MainActor
private func rows(_ browser: LibraryBrowserModel) -> [BrowserRow] {
    if case .rows(let rows) = browser.content { return rows }
    return []
}

@MainActor
@Suite("Books and planners", .serialized)
struct LibraryBookTests {
    @Test("BOOK-1, BOOK-2: a book opens like a folder with entries in stored order and their sparse indices")
    func openBook() async throws {
        let fixture = try BookFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await open(fixture)
        browser.selection = ["item:" + fixture.bookId]
        #expect(browser.canOpenSelection)
        await browser.openSelection()
        #expect(browser.showsBook)
        let entries = rows(browser)
        #expect(entries.map(\.storedIndex) == [9, 0, 5, 12, 14, 20, 21, 22])
        #expect(
            entries.map(\.name) == [
                "Depot", "Stop 1", "Stations", "Belts", "Untitled Deconstruction Planner", "Ancient",
                "[item=iron-plate,quality=legendary]Iron plate [virtual-signal=signal-A]", "[item=iron-plate]",
            ])
        #expect(
            entries.map(\.kind) == [
                .blueprint, .blueprint, .book, .upgradePlanner, .deconstructionPlanner, .blueprint, .blueprint,
                .blueprint,
            ])
        #expect(entries.allSatisfy { $0.entryPath?.count == 1 && $0.itemId == fixture.bookId })
        #expect(browser.pathComponents.map(\.name) == ["Library", "Trains", "Rail Book"])
        await session.close()
    }

    @Test("BOOK-3, BOOK-4: nested books open and close through Open, the path bar, and Enclosing Folder")
    func nestedBooks() async throws {
        let fixture = try BookFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await open(fixture)
        browser.selection = ["item:" + fixture.bookId]
        await browser.openSelection()
        browser.selection = ["entry:5"]
        await browser.openSelection()
        #expect(rows(browser).map(\.storedIndex) == [3, 7])
        #expect(rows(browser).map(\.entryPath) == [[5, 3], [5, 7]])
        browser.selection = ["entry:5.7"]
        await browser.openSelection()
        #expect(browser.content == .bookEmpty)
        #expect(browser.pathComponents.map(\.name) == ["Library", "Trains", "Rail Book", "Stations", "Empty"])
        #expect(browser.pathComponents.last?.target == .book([5, 7]))

        await browser.goUp()
        #expect(browser.book?.path == [5] && browser.selection == ["entry:5.7"])
        await browser.navigate(to: .book([]))
        #expect(browser.book?.path == [] && rows(browser).count == 8)
        await browser.goUp()
        #expect(browser.book == nil && browser.folder == "Trains" && browser.selection == ["item:" + fixture.bookId])

        let hollow = try #require(rows(browser).first { $0.name == "Hollow" })
        browser.selection = [hollow.id]
        await browser.openSelection()
        #expect(browser.content == .bookEmpty)
        await browser.navigate(to: .folder(""))
        #expect(browser.book == nil && browser.folder == "")
        await session.close()
    }

    @Test(
        "BOOK-5, BOOK-5a, BOOK-6: descriptions keep line breaks, versions show major.minor.patch, planners list settings"
    )
    func details() async throws {
        let fixture = try BookFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await open(fixture)
        browser.selection = ["item:" + fixture.bookId]
        await browser.loadSelectedDetail()
        let root = try #require(browser.selectedDetail)
        #expect(root.name == "Rail Book" && root.version == "2.0.55" && root.description == "Line one\nLine two")
        #expect(root.entryCount == 8 && root.location == nil)

        await browser.openSelection()
        let book = try #require(browser.selectedDetail)
        #expect(book.name == "Rail Book" && book.entryCount == 8)
        browser.selection = ["entry:12"]
        let upgrade = try #require(browser.selectedDetail)
        #expect(upgrade.description == "Upgrade\nall belts" && upgrade.location == "Entry 12 in Rail Book")
        #expect(upgrade.settings == ["Mappings:", "  0: transport-belt (entity) → fast-transport-belt (entity)"])
        browser.selection = ["entry:14"]
        let deconstruction = try #require(browser.selectedDetail)
        #expect(
            deconstruction.settings == [
                "entity filter mode: 1", "Entity filters: stone-wall", "trees and rocks only: no",
            ])
        browser.selection = ["entry:20"]
        #expect(browser.selectedDetail?.version == nil)
        browser.selection = ["entry:5"]
        await browser.openSelection()
        browser.selection = ["entry:5.3"]
        #expect(browser.selectedDetail?.location == "Entry 5.3 in Stations")
        await session.close()
    }

    @Test("BOOK-8: browsing never changes the stored source, unknown fields included")
    func preservesSource() async throws {
        let fixture = try BookFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await open(fixture)
        browser.selection = ["item:" + fixture.bookId]
        await browser.loadSelectedDetail()
        await browser.openSelection()
        browser.selection = ["entry:5"]
        await browser.openSelection()
        let id = fixture.bookId
        guard
            case .success(let exported) = await session.perform(
                .exporting, refreshing: false, { try $0.export(id: id) })
        else {
            Issue.record("export failed")
            return
        }
        #expect(exported == fixture.bytes)
        await session.close()
        let stored = try #require(
            FileManager.default.contentsOfDirectory(
                at: fixture.url.appendingPathComponent("library/Trains"), includingPropertiesForKeys: nil
            )
            .first { $0.lastPathComponent.hasPrefix("Rail Book") && $0.pathExtension == "txt" })
        #expect(try Data(contentsOf: stored) == fixture.bytes)
    }

    @Test(
        "An open book follows its item: a replaced source reloads, a deleted item closes the book; search still works")
    func followsItem() async throws {
        let fixture = try BookFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await open(fixture)
        browser.selection = ["item:" + fixture.bookId]
        await browser.openSelection()
        browser.filterText = "hollow"
        #expect(!browser.showsBook && rows(browser).map(\.name) == ["Hollow"])
        browser.filterText = ""
        #expect(browser.showsBook && rows(browser).count == 8)

        let id = fixture.bookId
        let replacement = try encode(
            #"{"blueprint_book":{"version":1,"label":"Rail Book","blueprints":[{"index":2,"blueprint":{"version":1,"label":"New"}}]}}"#
        )
        _ = await session.perform(.changing) { try $0.updateSource(id: id, bytes: replacement) }
        browser.listingChanged()
        for _ in 0..<50 where rows(browser).map(\.name) != ["New"] { try await Task.sleep(for: .milliseconds(20)) }
        #expect(rows(browser).map(\.name) == ["New"] && browser.book?.path == [])

        _ = await session.perform(.changing) { try $0.deleteItem(id: id) }
        browser.listingChanged()
        #expect(browser.book == nil && browser.folder == "Trains" && rows(browser).map(\.name) == ["Hollow"])
        await session.close()
    }

    @Test("Versions and stored paths are formatted from their packed and indexed forms")
    func formatting() {
        #expect(BlueprintEntryReader.version(packedVersion2055) == "2.0.55")
        #expect(BlueprintEntryReader.version((1 << 48) | (1 << 32) | (110 << 16) | 3) == "1.1.110")
        #expect(BlueprintEntryReader.version(0) == nil)
        #expect(BlueprintEntryReader.pathText([5, 0, 12]) == "5.0.12")
    }
}
