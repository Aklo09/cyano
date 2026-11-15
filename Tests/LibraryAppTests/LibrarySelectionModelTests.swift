import AppKit
import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

/// A scratch folder and a private preferences domain, removed afterwards.
private struct Fixture {
    let parent: URL
    let suite: String
    let defaults: UserDefaults

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("fb-native-select-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        suite = "local.fb.library.tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    func url(_ name: String) -> URL { parent.appendingPathComponent(name) }

    func library(_ name: String) throws -> URL {
        try NativeLibrary.initialize(at: url(name)).close()
        return url(name)
    }

    func cleanup() {
        removeTestPreferences(suite)
        try? FileManager.default.removeItem(at: parent)
    }
}

@MainActor private func failure(_ model: LibrarySelectionModel) -> LibraryMessage? {
    if case .openFailed(_, let message) = model.session.phase { return message }
    return nil
}

private func owner(_ url: URL) throws -> LibraryOwnershipStatus { try NativeLibrary.inspectOwnership(at: url) }

@MainActor
@Suite("Library selection", .serialized)
struct LibrarySelectionModelTests {
    @Test("LIB-1, LIB-2: a first launch shows selection; an empty folder asks before creating a library")
    func firstLaunchAndCreation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = LibrarySelectionModel(defaults: fixture.defaults)
        #expect(model.windowGoal == .selection && model.recents.isEmpty && model.reopenCandidate == nil)
        await model.launch()
        #expect(model.windowGoal == .selection && model.session.phase == .closed)

        let empty = fixture.url("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        try Data("finder".utf8).write(to: empty.appendingPathComponent(".DS_Store"))
        await model.chooseFolderToOpen(empty)
        #expect(model.pendingCreation == empty && model.session.phase == .closed)
        await model.confirmCreation()
        #expect(model.pendingCreation == nil && model.windowGoal == .library)
        #expect(model.session.listing?.items.isEmpty == true && model.session.listing?.folders.isEmpty == true)
        await model.closeLibrary()

        let fresh = fixture.url("Fresh")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: false)
        await model.chooseFolderToCreate(fresh)
        #expect(model.session.libraryURL?.path == fresh.path && model.windowGoal == .library)
        await model.closeLibrary()
        // New Library on an existing library opens it instead of refusing.
        await model.chooseFolderToCreate(fresh)
        #expect(model.session.libraryURL?.path == fresh.path)
        await model.closeLibrary()
    }

    @Test("LIB-3, LIB-4: recents put the latest library first, mark missing folders, and can be removed")
    func recents() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = try fixture.library("First")
        let second = try fixture.library("Second")
        let model = LibrarySelectionModel(defaults: fixture.defaults)
        await model.chooseFolderToOpen(first)
        await model.chooseFolderToOpen(second)
        await model.closeLibrary()
        #expect(model.recents.map(\.library.name) == ["Second", "First"])
        #expect(model.recents.allSatisfy { $0.available })

        try FileManager.default.removeItem(at: first)
        model.refreshRecents()
        let missing = try #require(model.recents.first { $0.library.name == "First" })
        #expect(!missing.available)
        await model.openRecent(missing)
        #expect(model.session.phase == .closed && model.windowGoal == .selection)
        model.removeRecent(missing)
        #expect(model.recents.map(\.library.name) == ["Second"])
        model.clearRecents()
        #expect(model.recents.isEmpty)
    }

    @Test("Recents keep one entry per folder, newest first, at most ten")
    func recentStore() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = RecentLibraryStore(defaults: fixture.defaults)
        let folder = fixture.url("Library")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let link = fixture.url("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        store.record(folder)
        store.record(URL(fileURLWithPath: folder.path + "/", isDirectory: true))
        store.record(link)
        #expect(store.recents.count == 1)
        for index in 0..<12 { store.record(fixture.url("Other \(index)")) }
        #expect(store.recents.count == 10 && store.recents.first?.name == "Other 11")
        store.reopenPath = store.recents[3].path
        store.remove(store.recents[3].path)
        #expect(store.reopenPath == nil)
    }

    @Test("LIB-5, LIB-7: a foreign folder or an unsupported library is refused without writing")
    func refusedFolders() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = LibrarySelectionModel(defaults: fixture.defaults)
        let foreign = fixture.url("Foreign")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        try Data("notes".utf8).write(to: foreign.appendingPathComponent("notes.txt"))
        await model.chooseFolderToOpen(foreign)
        #expect(failure(model)?.code == "INVALID_LIBRARY_FORMAT" && model.windowGoal == .selection)
        #expect(try FileManager.default.contentsOfDirectory(atPath: foreign.path) == ["notes.txt"])
        model.back()
        #expect(model.session.phase == .closed)

        let future = try fixture.library("Future")
        let marker = future.appendingPathComponent(".library-format.json")
        let original = try Data(contentsOf: marker)
        try Data(
            String(decoding: original, as: UTF8.self).replacingOccurrences(
                of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"
            ).utf8
        ).write(to: marker)
        let changed = try Data(contentsOf: marker)
        #expect(changed != original)
        await model.chooseFolderToOpen(future)
        let message = try #require(failure(model))
        #expect(message.code == "UNSUPPORTED_VERSION")
        #expect(try Data(contentsOf: marker) == changed)
        #expect(model.recents.isEmpty)
    }

    @Test("LIB-6: a synchronized location is refused with its own message (opener injected)")
    func synchronizedLocation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let refusing = LibraryOpener(
            open: { _ in throw NativeLibraryError.unsupportedFilesystem },
            initialize: { _ in throw NativeLibraryError.unsupportedFilesystem },
            inspectOperations: { _ in [] })
        let model = LibrarySelectionModel(session: LibrarySession(opener: refusing), defaults: fixture.defaults)
        await model.chooseFolderToCreate(fixture.url("iCloud Library"))
        let message = try #require(failure(model))
        #expect(message.code == "UNSUPPORTED_FILESYSTEM" && message.guidance.contains("iCloud Drive"))
    }

    @Test("LIB-8, LIB-9, LIB-10: in use with Try Again; switching libraries releases the first")
    func ownership() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = try fixture.library("First")
        let second = try fixture.library("Second")
        let holder = try NativeLibrary(at: first)
        let model = LibrarySelectionModel(defaults: fixture.defaults)
        await model.chooseFolderToOpen(first)
        #expect(failure(model)?.code == "LIBRARY_IN_USE" && model.windowGoal == .selection)
        #expect(try owner(first) == .owned)
        holder.close()
        await model.tryAgain()
        #expect(model.session.libraryURL?.path == first.path && model.windowGoal == .library)
        #expect(try owner(first) == .owned)

        await model.chooseFolderToOpen(second)
        #expect(model.session.libraryURL?.path == second.path)
        #expect(try owner(first) == .idle)
        #expect(try owner(second) == .owned)
        await model.closeLibrary()
        #expect(try owner(second) == .idle && model.windowGoal == .selection)
    }

    @Test("LIB-11: the last library reopens unless the owner closed it; quitting keeps it")
    func reopenAtLaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.library("Trains")
        let first = LibrarySelectionModel(defaults: fixture.defaults)
        await first.chooseFolderToOpen(url)
        await first.session.close()

        let relaunched = LibrarySelectionModel(defaults: fixture.defaults)
        #expect(relaunched.windowGoal == .library && relaunched.reopenCandidate?.path == url.path)
        await relaunched.launch()
        #expect(relaunched.session.libraryURL?.path == url.path)

        // The app dismissing its own window, or quitting, keeps the library for the next launch.
        relaunched.willDismissLibraryWindow()
        #expect(await relaunched.libraryWindowDisappeared() == false)
        relaunched.didDismissLibraryWindow()
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(await relaunched.libraryWindowDisappeared() == false)
        await relaunched.session.close()
        #expect(LibrarySelectionModel(defaults: fixture.defaults).windowGoal == .library)

        // The owner closing the library window forgets it.
        let again = LibrarySelectionModel(defaults: fixture.defaults)
        await again.launch()
        #expect(await again.libraryWindowDisappeared() == true)
        #expect(try owner(url) == .idle)
        #expect(LibrarySelectionModel(defaults: fixture.defaults).windowGoal == .selection)

        // A missing last library leaves selection with the entry marked unavailable.
        let reopening = LibrarySelectionModel(defaults: fixture.defaults)
        await reopening.chooseFolderToOpen(url)
        await reopening.session.close()
        try FileManager.default.removeItem(at: url)
        let missing = LibrarySelectionModel(defaults: fixture.defaults)
        #expect(missing.windowGoal == .selection && missing.reopenCandidate == nil)
        #expect(missing.recents.first?.available == false)

        // A last library held elsewhere ends in selection with the in-use message.
        let held = try fixture.library("Held")
        let holding = LibrarySelectionModel(defaults: fixture.defaults)
        await holding.chooseFolderToOpen(held)
        await holding.session.close()
        let holder = try NativeLibrary(at: held)
        defer { holder.close() }
        let blocked = LibrarySelectionModel(defaults: fixture.defaults)
        #expect(blocked.windowGoal == .library)
        await blocked.launch()
        #expect(blocked.windowGoal == .selection && failure(blocked)?.code == "LIBRARY_IN_USE")
    }

    @Test("REC-2 to REC-4: recovery required stays visible, Back dismisses it, Try Again opens after quarantine")
    func recovery() async throws {
        struct Interrupted: Error {}
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let url = try fixture.library("Library")
        let setup = try NativeLibrary(at: url)
        _ = try setup.createFolder(name: "Source")
        setup.close()
        let crashed = try NativeLibrary.testingOpen(at: url) { phase in
            if phase == .intentPublished { throw Interrupted() }
        }
        #expect(throws: Interrupted.self) { _ = try crashed.moveFolder("Source", parent: "", name: "Moved") }
        crashed.close()
        let folder = url.appendingPathComponent("library/Source")
        let copy = fixture.url("Lookalike")
        try FileManager.default.copyItem(at: folder, to: copy)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: copy, to: folder)

        let model = LibrarySelectionModel(defaults: fixture.defaults)
        await model.chooseFolderToOpen(url)
        guard case .recoveryRequired(_, let operations, _, false) = model.session.phase else {
            Issue.record("\(model.session.phase)")
            return
        }
        #expect(model.windowGoal == .selection)
        await model.session.close()
        guard case .recoveryRequired = model.session.phase else {
            Issue.record("closing without a library cleared recovery: \(model.session.phase)")
            return
        }
        await model.tryAgain()
        guard case .recoveryRequired(_, _, _, true) = model.session.phase else {
            Issue.record("\(model.session.phase)")
            return
        }
        model.back()
        #expect(model.session.phase == .closed)
        await model.chooseFolderToOpen(url)
        _ = try NativeLibrary.quarantineOperation(at: url, id: operations[0].id)
        await model.tryAgain()
        #expect(model.session.libraryURL?.path == url.path && model.windowGoal == .library)
        await model.closeLibrary()
    }

    @Test("The preferences override selects a separate domain")
    func preferencesOverride() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        #expect(LibraryPreferences.defaults(fixture.defaults) === fixture.defaults)
        let isolated = "local.fb.library.tests-isolated-\(UUID().uuidString)"
        fixture.defaults.set(isolated, forKey: LibraryPreferences.suiteArgument)
        let chosen = LibraryPreferences.defaults(fixture.defaults)
        chosen.set("marker", forKey: "probe")
        #expect(fixture.defaults.string(forKey: "probe") == nil)
        #expect(UserDefaults(suiteName: isolated)?.string(forKey: "probe") == "marker")
        removeTestPreferences(isolated)
    }
}
