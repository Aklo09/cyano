import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private func encoded(_ json: String) throws -> Data {
    let compressed = try ZlibCodec.compress(Data(json.utf8), maximum: 1_000_000)
    return Data(("0" + compressed.base64EncodedString()).utf8)
}

private func book(entries: String) throws -> Data {
    try encoded(#"{"blueprint_book":{"version":1,"label":"Rail Book","blueprints":["# + entries + "]}}")
}

private struct CommentFixture {
    let parent: URL
    let url: URL
    let bookId: String
    let otherId: String
    let bookBytes: Data

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-comments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        url = parent.appendingPathComponent("Library")
        let library = try NativeLibrary.initialize(at: url)
        defer { library.close() }
        bookBytes = try book(
            entries: """
                {"index":3,"blueprint":{"version":1,"label":"Stop"}},
                {"index":8,"blueprint_book":{"version":1,"label":"Nested","blueprints":[
                  {"index":1,"blueprint":{"version":1,"label":"Deep"}}]}}
                """)
        bookId = try library.importSource(bookBytes).id
        otherId = try library.importSource(encoded(#"{"blueprint":{"version":1,"label":"Other"}}"#)).id
    }

    func reopen() throws -> NativeLibrary { try NativeLibrary(at: url) }
    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
private func openBrowser(_ fixture: CommentFixture) async -> (LibrarySession, LibraryBrowserModel) {
    let session = LibrarySession()
    await session.open(fixture.url)
    let browser = LibraryBrowserModel(session: session)
    browser.listingChanged()
    return (session, browser)
}

@MainActor
@Suite("Comments", .serialized)
struct LibraryCommentsTests {
    @Test("COM-1 to COM-3: comments belong to the root or an entry, show oldest first, and survive reopening")
    func addAndScope() async throws {
        let fixture = try CommentFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        #expect(browser.commentScope == nil)
        browser.selection = ["item:" + fixture.bookId]
        #expect(browser.commentScope == CommentScope(itemId: fixture.bookId, entryPath: []))
        #expect(browser.comments.isEmpty)

        browser.commentDraft = "First line\nsecond line"
        await browser.addComment()
        browser.commentDraft = "Later note"
        await browser.addComment()
        #expect(browser.comments.map(\.text) == ["First line\nsecond line", "Later note"])
        #expect(browser.commentDraft.isEmpty && browser.commentFailure == nil)

        await browser.openSelection()
        #expect(browser.commentScope == CommentScope(itemId: fixture.bookId, entryPath: []))
        browser.selection = ["entry:3"]
        #expect(
            browser.commentScope == CommentScope(itemId: fixture.bookId, entryPath: [3]) && browser.comments.isEmpty)
        browser.commentDraft = "On the stop"
        await browser.addComment()
        #expect(browser.comments.map(\.text) == ["On the stop"])
        browser.selection = ["entry:8"]
        await browser.openSelection()
        #expect(browser.commentScope == CommentScope(itemId: fixture.bookId, entryPath: [8]))
        browser.selection = ["entry:8.1"]
        browser.commentDraft = "Deep note"
        await browser.addComment()
        await session.close()

        let library = try fixture.reopen()
        defer { library.close() }
        let item = try #require(try library.list().items.first { $0.id == fixture.bookId })
        #expect(item.metadata.comments.map(\.entryPath) == [[], [], [3], [8, 1]])
        #expect(try library.export(id: fixture.bookId) == fixture.bookBytes)
    }

    @Test("COM-4, COM-5: empty, whitespace-only, and oversized comments are refused and the text is kept")
    func refusals() async throws {
        let fixture = try CommentFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.selection = ["item:" + fixture.otherId]
        #expect(!browser.canAddComment)
        browser.commentDraft = " \n\t "
        #expect(!browser.canAddComment)
        await browser.addComment()
        #expect(browser.comments.isEmpty)
        let long = String(repeating: "é", count: commentByteLimit / 2 + 1)
        browser.commentDraft = long
        #expect(browser.commentTooLong && !browser.canAddComment)
        await browser.addComment()
        #expect(browser.comments.isEmpty && browser.commentDraft == long)
        await session.close()
    }

    @Test("Drafts stay with their item or entry when the selection changes")
    func draftsPerScope() async throws {
        let fixture = try CommentFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.selection = ["item:" + fixture.bookId]
        browser.commentDraft = "For the book"
        browser.selection = ["item:" + fixture.otherId]
        #expect(browser.commentDraft.isEmpty)
        browser.commentDraft = "For the other"
        await browser.addComment()
        browser.selection = ["item:" + fixture.bookId]
        #expect(browser.commentDraft == "For the book" && browser.comments.isEmpty)
        browser.selection = ["item:" + fixture.bookId, "item:" + fixture.otherId]
        #expect(browser.commentScope == nil && !browser.canAddComment)
        await session.close()
    }

    @Test("COM-6, COM-7: deleting removes a comment for good; comments promoted by a replacement show as root text")
    func deleteAndPromoted() async throws {
        let fixture = try CommentFixture()
        defer { fixture.cleanup() }
        let (session, browser) = await openBrowser(fixture)
        browser.selection = ["item:" + fixture.bookId]
        await browser.openSelection()
        browser.selection = ["entry:3"]
        browser.commentDraft = "Stop comment"
        await browser.addComment()
        browser.commentDraft = "To delete"
        await browser.addComment()
        let doomed = try #require(browser.comments.last)
        await browser.deleteComment(doomed)
        #expect(browser.comments.map(\.text) == ["Stop comment"])

        let id = fixture.bookId
        let replacement = try book(entries: #"{"index":0,"blueprint":{"version":1,"label":"Only"}}"#)
        _ = await session.perform(.changing) { try $0.updateSource(id: id, bytes: replacement) }
        await browser.goUp()
        browser.listingChanged()
        browser.selection = ["item:" + fixture.bookId]
        #expect(browser.comments.map(\.text) == ["[Former book entry 3]\n\nStop comment"])

        browser.beginComment()
        #expect(browser.inspectorTab == .comments && browser.commentFocusRequested)
        await session.close()
        let library = try fixture.reopen()
        defer { library.close() }
        let item = try #require(try library.list().items.first { $0.id == fixture.bookId })
        #expect(!item.metadata.comments.contains { $0.text == "To delete" })
    }
}
