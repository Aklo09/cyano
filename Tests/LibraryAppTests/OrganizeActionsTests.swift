import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func encoded(_ json: String) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private func blueprint(_ label: String) throws -> Data {
    try encoded("{\"blueprint\":{\"version\":1,\"label\":\"\(label)\"}}")
}

private struct OrganizeFixture {
    let parent: URL
    let url: URL
    let itemId: String
    let bookId: String
    let itemBytes: Data

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-organize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        _ = try library.createFolder(name: "Trains")
        _ = try library.createFolder(parent: "Trains", name: "Stations")
        _ = try library.createFolder(name: "Smelting")
        itemBytes = try blueprint("Loop")
        itemId = try library.importSource(itemBytes, folder: "Trains").id
        _ = try library.addComment(id: itemId, text: "Keep me")
        bookId = try library.importSource(
            encoded(
                """
                {"blueprint_book":{"version":1,"label":"Book","blueprints":[
                  {"index":4,"blueprint":{"version":1,"label":"Leaf"}}]}}
                """)
        ).id
    }

    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
private func openBrowser(_ fixture: OrganizeFixture) async -> (LibrarySession, LibraryBrowserModel) {
    let session = LibrarySession()
    await session.open(fixture.url)
    let browser = LibraryBrowserModel(session: session)
    browser.listingChanged()
    return (session, browser)
}

@MainActor
private func row(_ browser: LibraryBrowserModel, _ id: String) throws -> BrowserRow {
    guard case .rows(let rows) = browser.content, let found = rows.first(where: { $0.id == id }) else {
        throw CocoaError(.featureUnsupported)
    }
    return found
}

@MainActor
private func item(_ session: LibrarySession, _ id: String) -> LibraryCore.LibraryItem? {
    session.listing?.items.first { $0.id == id }
}

@MainActor
@Suite("Organization", .serialized)
struct OrganizeActionsTests {
    @Test("ORG-1: New Folder creates the next free name, selects it, and starts renaming")
    func newFolder() async throws {
        let fixture = try OrganizeFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        await browser.newFolder()
        #expect(browser.selection == ["folder:New Folder"] && browser.renamingRow == "folder:New Folder")
        await browser.newFolder()
        #expect(browser.selection == ["folder:New Folder 2"])
        browser.show(folder: "Trains")
        await browser.newFolder()
        #expect(session.listing?.folders.contains("Trains/New Folder") == true && browser.folder == "Trains")
        await session.close()
    }

    @Test(
        "ORG-2 to ORG-5: renaming keeps identity and comments; case-only renames work; collisions and bad names keep the field"
    )
    func rename() async throws {
        let fixture = try OrganizeFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.show(folder: "Trains")
        let loop = try row(browser, "item:" + fixture.itemId)
        let before = try #require(item(session, fixture.itemId))
        #expect(await browser.rename(loop, to: "  Loop line  ") == nil)
        let after = try #require(item(session, fixture.itemId))
        #expect(after.name == "Loop line" && after.metadata.createdAt == before.metadata.createdAt)
        #expect(
            after.metadata.comments == before.metadata.comments && after.metadata.updatedAt >= before.metadata.updatedAt
        )
        #expect(await browser.rename(try row(browser, "item:" + fixture.itemId), to: "LOOP LINE") == nil)
        #expect(item(session, fixture.itemId)?.name == "LOOP LINE")

        let folderRow = try row(browser, "folder:Trains/Stations")
        #expect(await browser.rename(folderRow, to: "STATIONS") == nil)
        #expect(browser.selection == ["folder:Trains/STATIONS"])

        _ = await session.perform(.changing) { try $0.createFolder(parent: "Trains", name: "Depots") }
        let depots = try row(browser, "folder:Trains/Depots")
        browser.renamingRow = depots.id
        let clash = try #require(await browser.rename(depots, to: "stations"))
        #expect(clash.code == "NAME_COLLISION" && browser.renamingRow == depots.id && browser.renameFailure == clash)
        let invalid = try #require(await browser.rename(depots, to: ".hidden"))
        #expect(invalid.code == "INVALID_INPUT" || invalid.code == "UNSAFE_PATH")
        browser.cancelRename()
        #expect(browser.renamingRow == nil && session.listing?.folders.contains("Trains/Depots") == true)
        await session.close()
    }

    @Test("ORG-6, ORG-7: moving keeps metadata; invalid targets are excluded; collisions are refused")
    func move() async throws {
        let fixture = try OrganizeFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.show(folder: "Trains")
        let loop = try row(browser, "item:" + fixture.itemId)
        let before = try #require(item(session, fixture.itemId))
        #expect(!browser.moveTargets(for: [loop]).contains("Trains"))
        #expect(await browser.move([loop], to: "Smelting", reveal: true).isEmpty)
        let after = try #require(item(session, fixture.itemId))
        #expect(after.folder == "Smelting" && after.metadata == before.metadata)
        #expect(browser.folder == "Smelting" && browser.selection == ["item:" + fixture.itemId])

        browser.show(folder: "")
        let trains = try row(browser, "folder:Trains")
        let targets = browser.moveTargets(for: [trains])
        #expect(!targets.contains("Trains") && !targets.contains("Trains/Stations") && !targets.contains(""))
        #expect(targets.contains("Smelting"))
        #expect(await browser.move([trains], to: "Smelting", reveal: false).isEmpty)
        #expect(session.listing?.folders.contains("Smelting/Trains/Stations") == true && browser.folder == "")

        _ = await session.perform(.changing) { try $0.createFolder(name: "Trains") }
        browser.show(folder: "Smelting")
        let moved = try row(browser, "folder:Smelting/Trains")
        let failures = await browser.move([moved], to: "", reveal: true)
        #expect(failures.map(\.code) == ["NAME_COLLISION"] && browser.organizeFailure?.code == "NAME_COLLISION")
        await session.close()
    }

    @Test("Dragged rows are resolved from their identifiers; book entries never move")
    func dragging() async throws {
        let fixture = try OrganizeFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        let text = ["item:" + fixture.bookId, "folder:Trains"].map { LibraryBrowserModel.dragPrefix + $0 }
            .joined(separator: "\n")
        #expect(Set(browser.rows(fromDragged: text).map(\.id)) == ["item:" + fixture.bookId, "folder:Trains"])
        #expect(browser.rows(fromDragged: "plain text").isEmpty)
        browser.selection = ["item:" + fixture.bookId]
        await browser.openSelection()
        browser.selection = ["entry:4"]
        #expect(browser.organizableSelection.isEmpty && !browser.canRenameSelection)
        browser.requestDelete()
        #expect(browser.pendingDeletion == nil)
        await session.close()
    }

    @Test("ORG-8 to ORG-10: deleting asks first, sends originals to the Trash, and refuses non-empty folders")
    func delete() async throws {
        let fixture = try OrganizeFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.selection = ["item:" + fixture.bookId]
        browser.requestDelete()
        let pending = try #require(browser.pendingDeletion)
        #expect(pending.title == "Move “Book” to the Trash?" && pending.actionTitle == "Move to Trash")
        browser.pendingDeletion = nil
        #expect(item(session, fixture.bookId) != nil)
        browser.requestDelete()
        // As the alert does: dismissing clears the pending value before the button's action runs.
        let confirmed = browser.pendingDeletion
        browser.pendingDeletion = nil
        await browser.confirmDelete(confirmed)
        #expect(item(session, fixture.bookId) == nil && browser.organizeFailure == nil)

        browser.selection = ["folder:Trains"]
        browser.requestDelete()
        #expect(browser.pendingDeletion == nil && browser.organizeFailure?.title == "“Trains” isn't empty")
        browser.organizeFailure = nil
        browser.selection = ["folder:Smelting"]
        browser.requestDelete()
        #expect(browser.pendingDeletion?.title == "Delete the folder “Smelting”?")
        await browser.confirmDelete()
        #expect(session.listing?.folders.contains("Smelting") == false)
        await session.close()
    }

    @Test("ORG-11 to ORG-13: replacing keeps identity and name, reports moved comments, and refuses invalid input")
    func replace() async throws {
        let fixture = try OrganizeFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        let bookId = fixture.bookId
        _ = await session.perform(.commenting) { try $0.addComment(id: bookId, entryPath: [4], text: "Leaf note") }
        browser.selection = ["item:" + fixture.bookId]
        #expect(browser.canReplaceSelection)
        let before = try #require(item(session, fixture.bookId))
        let replacement = String(decoding: try blueprint("Brand new"), as: UTF8.self) + "\r\n"
        browser.beginReplace(text: "not a blueprint")
        let sheet = try #require(browser.replaceSheet)
        await sheet.analyze()
        #expect(sheet.blocker == "This isn't a blueprint string")
        await browser.runReplace()
        #expect(browser.replaceSheet != nil && item(session, fixture.bookId)?.metadata == before.metadata)

        sheet.text = replacement
        await sheet.analyze()
        await browser.runReplace()
        #expect(browser.replaceSheet == nil && browser.confirmation == "Replaced. 1 comment moved to the item.")
        let after = try #require(item(session, fixture.bookId))
        #expect(
            after.id == before.id && after.name == before.name && after.metadata.createdAt == before.metadata.createdAt)
        #expect(after.metadata.comments.map(\.text) == ["[Former book entry 4]\n\nLeaf note"])
        #expect(after.kind == "blueprint")
        guard
            case .success(let stored) = await session.perform(
                .exporting, refreshing: false, { try $0.export(id: bookId) })
        else {
            Issue.record("export failed")
            return
        }
        #expect(stored == Data(replacement.utf8))

        browser.show(folder: "Trains")
        browser.selection = ["folder:Trains/Stations"]
        #expect(!browser.canReplaceSelection)
        await session.close()
    }
}
