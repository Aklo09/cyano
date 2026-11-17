import CoreGraphics
import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func encode(_ json: String) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

/// A root book with two icons and two entries: one with four icons (one rare), one without icons.
private struct IconFixture {
    let parent: URL
    let url: URL
    let bookId: String
    let plainId: String

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-icons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        bookId = try library.importSource(
            encode(
                """
                {"blueprint_book":{"version":1,"label":"Smelting","icons":[
                  {"index":2,"signal":{"type":"space-location","name":"nauvis"}},
                  {"index":1,"signal":{"name":"iron-plate"}}],"blueprints":[
                  {"index":0,"blueprint":{"version":1,"label":"Four","icons":[
                    {"index":1,"signal":{"name":"iron-plate"}},{"index":2,"signal":{"type":"virtual","name":"signal-A"}},
                    {"index":3,"signal":{"type":"fluid","name":"water"}},
                    {"index":4,"signal":{"name":"copper-cable","quality":"rare"}}]}},
                  {"index":3,"blueprint":{"version":1,"label":"None"}}]}}
                """)
        ).id
        plainId = try library.importSource(encode(#"{"blueprint":{"version":1,"label":"Plain"}}"#)).id
    }

    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
private func rows(_ browser: LibraryBrowserModel) -> [BrowserRow] {
    if case .rows(let rows) = browser.content { return rows }
    return []
}

@MainActor
@Suite("Entry icons", .serialized)
struct EntryIconTests {
    @Test("ICN-1, ICN-3: folder rows carry root icons in slot order from the listing; rows without icons carry none")
    func rootRows() async throws {
        let fixture = try IconFixture()
        defer { fixture.cleanup() }
        let session = LibrarySession()
        await session.open(fixture.url)
        let browser = LibraryBrowserModel(session: session)
        browser.listingChanged()
        browser.show(folder: "")
        let byId = Dictionary(uniqueKeysWithValues: rows(browser).compactMap { row in row.itemId.map { ($0, row) } })
        #expect(
            byId[fixture.bookId]?.icons == [
                EntryIcon(index: 1, type: nil, name: "iron-plate", quality: nil),
                EntryIcon(index: 2, type: "space-location", name: "nauvis", quality: nil),
            ])
        #expect(byId[fixture.plainId]?.icons == [])
        await session.close()
    }

    @Test("ICN-1, ICN-2: book entry rows and the inspector detail carry each entry's own icons")
    func entryRowsAndDetail() async throws {
        let fixture = try IconFixture()
        defer { fixture.cleanup() }
        let session = LibrarySession()
        await session.open(fixture.url)
        let browser = LibraryBrowserModel(session: session)
        browser.listingChanged()
        browser.show(folder: "")
        browser.selection = ["item:" + fixture.bookId]
        await browser.loadSelectedDetail()
        #expect(browser.selectedDetail?.icons.map(\.name) == ["iron-plate", "nauvis"])
        await browser.openSelection()
        let entries = rows(browser)
        #expect(entries.map(\.icons.count) == [4, 0])
        #expect(entries.first?.icons.last == EntryIcon(index: 4, type: nil, name: "copper-cable", quality: "rare"))
        browser.selection = ["entry:0"]
        #expect(browser.selectedDetail?.icons.map(\.name) == ["iron-plate", "signal-A", "water", "copper-cable"])
        browser.selection = ["entry:3"]
        #expect(browser.selectedDetail?.icons == [])
        await session.close()
    }

    @Test("ICN-2: the inspector tile follows the game's layout for one to four icons")
    func layout() {
        #expect(EntryIconLayout.frames(count: 0, tile: 64).isEmpty)
        #expect(EntryIconLayout.frames(count: 1, tile: 64) == [CGRect(x: 8, y: 8, width: 48, height: 48)])
        #expect(
            EntryIconLayout.frames(count: 2, tile: 64) == [
                CGRect(x: 2, y: 18, width: 28, height: 28), CGRect(x: 34, y: 18, width: 28, height: 28),
            ])
        #expect(
            EntryIconLayout.frames(count: 3, tile: 64).map(\.origin) == [
                CGPoint(x: 2, y: 2), CGPoint(x: 34, y: 2), CGPoint(x: 2, y: 34),
            ])
        let four = EntryIconLayout.frames(count: 4, tile: 48)
        #expect(four.count == 4 && four.allSatisfy { $0.width == 21 } && four[3].maxX == 46.5)
    }

    @Test("Screen specs, Accessibility: icons are read by name with hyphens as spaces and quality when not normal")
    func spokenNames() {
        #expect(EntryIconLayout.spokenNames([]) == "")
        #expect(
            EntryIconLayout.spokenNames([
                EntryIcon(index: 1, type: nil, name: "iron-plate", quality: "rare"),
                EntryIcon(index: 2, type: nil, name: "copper-cable", quality: "normal"),
            ]) == "iron plate, rare; copper cable")
    }
}
