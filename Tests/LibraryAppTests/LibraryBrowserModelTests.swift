import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func blueprint(_ label: String, padding: Int = 0) throws -> Data {
    let json =
        "{\"blueprint\":{\"version\":1,\"label\":\"\(label)\",\"description\":\"\(String(repeating: "x", count: padding))\"}}"
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private func book(_ label: String, description: String) throws -> Data {
    let json = """
        {"blueprint_book":{"version":1,"label":"\(label)","description":"\(description)","blueprints":[
          {"index":0,"blueprint":{"version":1,"label":"Leaf"}}]}}
        """
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

/// A fixture library: two folders (one nested), items with different kinds, sizes, and dates, an unpacked book
/// with a description, and one malformed item.
private struct BrowsingFixture {
    let parent: URL
    let url: URL

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("fb-native-browse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        _ = try library.createFolder(name: "Trains")
        _ = try library.createFolder(name: "smelting")
        _ = try library.createFolder(parent: "Trains", name: "Stations")
        _ = try library.importSource(blueprint("Rocket silo", padding: 400))
        Thread.sleep(forTimeInterval: 0.01)
        _ = try library.importSource(book("Résumé book", description: "Kept"), name: "Résumé book")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try library.importSource(blueprint("assembler"))
        _ = try library.importSource(blueprint("Stop"), folder: "Trains/Stations")
        _ = try library.importSource(blueprint("Loop"), folder: "Trains")
        _ = try library.importUnpacked(book("Unpacked", description: "Line one\\nLine two"), folder: "smelting")
        try Data("not a blueprint".utf8).write(to: url.appendingPathComponent("library/Broken.txt"))
        try Data("{}".utf8).write(to: url.appendingPathComponent("library/Broken.json"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
private func openBrowser(_ url: URL) async -> (LibrarySession, LibraryBrowserModel) {
    let session = LibrarySession()
    await session.open(url)
    let browser = LibraryBrowserModel(session: session)
    browser.listingChanged()
    return (session, browser)
}

@MainActor
private func rows(_ browser: LibraryBrowserModel) -> [BrowserRow] {
    if case .rows(let rows) = browser.content { return rows }
    return []
}

@MainActor
@Suite("Library browsing", .serialized)
struct LibraryBrowserModelTests {
    @Test("BRW-1: the root lists subfolders first, then items, with kind, updated date, and size")
    func rootRows() async throws {
        let fixture = try BrowsingFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture.url)
        defer { Task { await session.close() } }
        let listed = rows(browser)
        #expect(listed.map(\.name) == ["smelting", "Trains", "assembler", "Résumé book", "Rocket silo"])
        #expect(listed.map(\.kind) == [.folder, .folder, .blueprint, .book, .blueprint])
        let silo = try #require(listed.first { $0.name == "Rocket silo" })
        #expect(silo.updated != nil && silo.created != nil && (silo.sizeBytes ?? 0) > 100)
        #expect(listed.first?.updated == nil && listed.first?.sizeBytes == nil)
        #expect(browser.folderTree.children?.map(\.name) == ["smelting", "Trains"])
        #expect(browser.folderTree.children?.last?.children?.map(\.path) == ["Trains/Stations"])
    }

    @Test("Sorting by each column keeps folders first and orders items")
    func sorting() async throws {
        let fixture = try BrowsingFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture.url)
        defer { Task { await session.close() } }
        func items() -> [String] { rows(browser).filter { $0.kind != .folder }.map(\.name) }
        browser.sortKey = .name
        browser.ascending = false
        #expect(items() == ["Rocket silo", "Résumé book", "assembler"])
        #expect(rows(browser).prefix(2).allSatisfy { $0.kind == .folder })
        browser.sortKey = .kind
        browser.ascending = true
        #expect(items() == ["assembler", "Rocket silo", "Résumé book"])
        browser.sortKey = .updated
        #expect(items() == ["Rocket silo", "Résumé book", "assembler"])
        browser.sortKey = .size
        browser.ascending = false
        let sizes = rows(browser).compactMap(\.sizeBytes)
        #expect(sizes.count == 3 && sizes == sizes.sorted(by: >))
    }

    @Test("BRW-4: folders open and close through the path bar, double-click, and Enclosing Folder")
    func navigation() async throws {
        let fixture = try BrowsingFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture.url)
        defer { Task { await session.close() } }
        browser.selection = ["folder:Trains"]
        browser.openSelection()
        #expect(browser.folder == "Trains" && rows(browser).map(\.name) == ["Stations", "Loop"])
        browser.show(folder: "Trains/Stations")
        #expect(browser.pathComponents.map(\.name) == ["Library", "Trains", "Stations"])
        #expect(browser.pathComponents.map(\.folder) == ["", "Trains", "Trains/Stations"])
        browser.goUp()
        #expect(browser.folder == "Trains" && browser.selection == ["folder:Trains/Stations"])
        browser.show(folder: "Missing")
        #expect(browser.folder == "Trains")
        browser.show(folder: "")
        #expect(browser.pathComponents.map(\.name) == ["Library"])
    }

    @Test("BRW-5, BRW-6: the filter searches every folder ignoring case and accents; no match has its own state")
    func filtering() async throws {
        let fixture = try BrowsingFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture.url)
        defer { Task { await session.close() } }
        browser.show(folder: "Trains")
        browser.filterText = "  STOP "
        #expect(browser.isFiltering && rows(browser).map(\.name) == ["Stop"])
        #expect(rows(browser).first?.folder == "Trains/Stations")
        browser.filterText = "resume"
        #expect(rows(browser).map(\.name) == ["Résumé book"])
        browser.filterText = "leaf"
        #expect(rows(browser).map(\.folder) == ["smelting/Unpacked"])
        browser.filterText = "zzz"
        #expect(browser.content == .noMatches("zzz"))
        browser.filterText = ""
        #expect(browser.folder == "Trains" && rows(browser).map(\.name) == ["Stations", "Loop"])
    }

    @Test("BRW-2, BRW-3, BRW-7, BRW-8: empty library and folders, folder descriptions, and listing issues")
    func statesAndIssues() async throws {
        let fixture = try BrowsingFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture.url)
        browser.show(folder: "smelting/Unpacked")
        #expect(browser.folderDescription == "Line one\nLine two")
        #expect(rows(browser).map(\.name) == ["0 - Leaf"])
        #expect(browser.issues.map(\.path).contains("Broken.json"))
        #expect(browser.issues.allSatisfy { $0.message.hasSuffix("Close the library before fixing it in Finder.") })
        _ = await session.perform(.changing) { try $0.createFolder(name: "Empty") }
        browser.show(folder: "Empty")
        #expect(browser.content == .folderEmpty("Empty"))
        await session.close()

        let empty = fixture.parent.appendingPathComponent("Empty Library")
        let (emptySession, emptyBrowser) = await openBrowser(
            try {
                try NativeLibrary.initialize(at: empty).close()
                return empty
            }())
        #expect(emptyBrowser.content == .libraryEmpty)
        _ = await emptySession.perform(.changing) { try $0.createFolder(name: "Only folder") }
        #expect(rows(emptyBrowser).map(\.name) == ["Only folder"])
        emptyBrowser.show(folder: "Only folder")
        #expect(emptyBrowser.content == .folderEmpty("Only folder"))
        await emptySession.close()
    }

    @Test("BRW-10: a failed first listing shows the too-large state, never a partial list")
    func tooLarge() throws {
        let message = try #require(LibraryMessage.describing(NativeLibraryError.limitExceeded, activity: .listing))
        let content = LibraryBrowserModel.content(
            listing: nil, failure: message, folder: "", filter: "", key: .name, ascending: true)
        #expect(content == .tooLarge(message) && message.title == "This library is too large to list")
        #expect(
            LibraryBrowserModel.content(listing: nil, failure: nil, folder: "", filter: "", key: .name, ascending: true)
                == .loading)
    }

    @Test("A changed listing keeps the location valid and prunes the selection; a new library starts at the root")
    func listingChanges() async throws {
        let fixture = try BrowsingFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture.url)
        browser.show(folder: "Trains/Stations")
        let stop = try #require(rows(browser).first?.itemId)
        browser.selection = ["item:" + stop]
        #expect(browser.selectedItem?.name == "Stop")
        _ = await session.perform(.changing) { try $0.deleteItem(id: stop) }
        _ = await session.perform(.changing) { try $0.deleteFolder("Trains/Stations") }
        browser.listingChanged()
        #expect(browser.folder == "Trains" && browser.selection.isEmpty)

        let other = fixture.parent.appendingPathComponent("Other")
        try NativeLibrary.initialize(at: other).close()
        await session.open(other)
        browser.listingChanged()
        #expect(browser.folder == "" && browser.content == .libraryEmpty)
        await session.close()
    }

    @Test("Formats: decimal sizes with exact bytes, stored timestamps parsed")
    func formats() {
        #expect(LibraryFormat.size(4_213) == ByteCountFormatter.string(fromByteCount: 4_213, countStyle: .file))
        #expect(LibraryFormat.exactSize(4_213).hasSuffix("(\(4_213.formatted()) bytes)"))
        #expect(LibraryFormat.date("2026-11-14T11:09:18.317Z") != nil)
        #expect(LibraryFormat.date("not a date") == nil)
        #expect(ItemKind(stored: "upgrade_planner").label == "Upgrade Planner")
        #expect(ItemKind(stored: "deconstruction_planner").symbol == "xmark.square")
    }
}
