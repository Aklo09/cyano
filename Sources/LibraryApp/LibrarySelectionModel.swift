import AppKit
import Foundation
import LibraryCore
import Observation

/// Library selection and the hand-off between the selection window and the library window.
/// It outlives both windows: windows only mirror `windowGoal`, so a failure in either brings selection back.
@MainActor @Observable
public final class LibrarySelectionModel {
    /// Which window should be showing.
    public enum WindowGoal: Equatable { case selection, library }

    public struct RecentRow: Equatable, Identifiable {
        public let library: RecentLibrary
        public let available: Bool
        public var id: String { library.id }
    }

    public let session: LibrarySession
    /// Browsing state for the library window.
    public let browser: LibraryBrowserModel
    /// The asset release for previews and statistics.
    public let assets: AssetSettings
    public private(set) var windowGoal: WindowGoal
    public private(set) var recents: [RecentRow] = []
    /// An empty folder chosen with Open Library, awaiting "Create a library in …?" (LIB-2).
    public var pendingCreation: URL?

    private let store: RecentLibraryStore
    /// Set while the app itself dismisses the library window, so its disappearance does not close the library.
    @ObservationIgnored public private(set) var dismissingLibraryWindow = false
    @ObservationIgnored private var terminating = false
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    public init(session: LibrarySession = LibrarySession(), defaults: UserDefaults) {
        self.session = session
        browser = LibraryBrowserModel(session: session)
        assets = AssetSettings(defaults: defaults)
        let assets = assets
        Task { await assets.verifySaved() }
        store = RecentLibraryStore(defaults: defaults)
        windowGoal = .selection
        if let path = store.reopenPath, RecentLibraryStore.isAvailable(path) { windowGoal = .library }
        refreshRecents()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminating = true }
        }
    }

    /// The library to reopen at launch (LIB-11), when it is still reachable.
    public var reopenCandidate: URL? {
        guard let path = store.reopenPath, RecentLibraryStore.isAvailable(path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Called once by the first window: reopens the last library, or stays in selection.
    public func launch() async {
        guard let url = reopenCandidate else {
            windowGoal = .selection
            return
        }
        await open(url)
    }

    /// Open Library… chose `url`: an empty folder asks before creating a library there (LIB-2).
    public func chooseFolderToOpen(_ url: URL) async {
        if (try? NativeLibrary.inspectOwnership(at: url)) == .uninitialized {
            pendingCreation = url
            return
        }
        await open(url)
    }

    /// New Library… chose `url`; an existing library there is opened rather than refused.
    public func chooseFolderToCreate(_ url: URL) async {
        await open(url, create: true)
    }

    public func confirmCreation() async {
        guard let url = pendingCreation else { return }
        pendingCreation = nil
        await open(url, create: true)
    }

    public func openRecent(_ row: RecentRow) async {
        guard RecentLibraryStore.isAvailable(row.library.path) else {
            refreshRecents()
            return
        }
        await open(row.library.url)
    }

    public func removeRecent(_ row: RecentRow) {
        store.remove(row.library.path)
        refreshRecents()
    }

    public func clearRecents() {
        store.clear()
        refreshRecents()
    }

    /// Back from an error or recovery view.
    public func back() {
        session.reset()
        windowGoal = .selection
    }

    public func tryAgain() async {
        await session.retryOpen()
        settle()
    }

    /// Close Library, or the owner closed the library window: release it and forget it for the next launch.
    public func closeLibrary() async {
        store.reopenPath = nil
        await session.close()
        windowGoal = .selection
    }

    /// The library window disappeared. Returns true when the owner closed it, so selection must be shown.
    public func libraryWindowDisappeared() async -> Bool {
        if dismissingLibraryWindow || terminating { return false }
        guard session.libraryURL != nil else { return false }
        await closeLibrary()
        return true
    }

    /// The app is about to dismiss the library window itself.
    public func willDismissLibraryWindow() {
        dismissingLibraryWindow = true
    }

    public func didDismissLibraryWindow() {
        dismissingLibraryWindow = false
    }

    public func refreshRecents() {
        recents = store.recents.map { RecentRow(library: $0, available: RecentLibraryStore.isAvailable($0.path)) }
    }

    private func open(_ url: URL, create: Bool = false) async {
        await session.open(url, create: create)
        settle()
    }

    /// Mirrors the session after an open attempt: success shows the library and remembers it.
    private func settle() {
        if let url = session.libraryURL {
            store.record(url)
            store.reopenPath = RecentLibraryStore.normalizedPath(url)
            windowGoal = .library
        } else {
            windowGoal = .selection
        }
        refreshRecents()
    }
}
