import Foundation
import LibraryCore
import Observation

/// How the session opens libraries; tests substitute hooked or failing openers.
public struct LibraryOpener: Sendable {
    public var open: @Sendable (URL) throws -> NativeLibrary
    public var initialize: @Sendable (URL) throws -> NativeLibrary
    public var inspectOperations: @Sendable (URL) throws -> [LibraryOperationRecord]

    public init(
        open: @escaping @Sendable (URL) throws -> NativeLibrary,
        initialize: @escaping @Sendable (URL) throws -> NativeLibrary,
        inspectOperations: @escaping @Sendable (URL) throws -> [LibraryOperationRecord]
    ) {
        self.open = open
        self.initialize = initialize
        self.inspectOperations = inspectOperations
    }

    public static let standard = LibraryOpener(
        open: { try NativeLibrary(at: $0) }, initialize: { try NativeLibrary.initialize(at: $0) },
        inspectOperations: { try NativeLibrary.inspectOperations(at: $0) })
}

/// The result of a library call made through the session.
public enum LibraryOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(LibraryMessage)
    /// Nothing to show: the owner cancelled, or the library closed or changed before the result arrived.
    case ignored
}

/// Owns the open library for the app's windows and runs every library call off the main thread, one at a time.
/// Windows observe `phase`, `listing`, and `revision`; each completed change publishes a fresh listing.
@MainActor @Observable
public final class LibrarySession {
    public enum Phase: Equatable {
        case closed
        case opening(URL)
        case open(URL)
        /// Opening failed and no committed operation is pending; `message` says why (LIB-5 to LIB-8).
        case openFailed(URL, LibraryMessage)
        /// Opening failed with committed operations pending, which the CLI can quarantine (REC-2, REC-3).
        /// `retried` is true after Recover failed again.
        case recoveryRequired(URL, operations: [PendingOperation], message: LibraryMessage, retried: Bool)
    }

    /// A committed operation that blocks opening, with the command that sets it aside (REC-2).
    public struct PendingOperation: Equatable, Sendable {
        public let id: String
        public let kind: String?
        public let quarantineCommand: String
    }

    public private(set) var phase: Phase = .closed
    /// The latest successful listing of the open library; kept when a later refresh fails.
    public private(set) var listing: LibraryListing?
    /// Why the latest refresh failed while the library stayed open (BRW-10), or nil.
    public private(set) var listingFailure: LibraryMessage?
    /// Increases with every published listing, so windows can react to any change.
    public private(set) var revision = 0
    /// Interrupted changes completed when the library opened (REC-1), until dismissed.
    public private(set) var completedNotice: String?
    /// A failed change blocked the session until Recover succeeds (REC-5).
    public private(set) var requiresRecovery = false
    /// Why the latest in-session Recover failed; the app then offers to close the library (REC-5).
    public private(set) var recoveryFailure: LibraryMessage?
    /// Library calls submitted but not finished; the toolbar spinner shows after 0.5 s.
    public private(set) var pendingCalls = 0

    public var libraryURL: URL? {
        if case .open(let url) = phase { return url }
        return nil
    }

    private let opener: LibraryOpener
    private let worker = LibraryWorker()
    private var library: NativeLibrary?
    /// Changes on every open and close, so results from an earlier library are dropped.
    private var generation = 0
    /// Opens and closes run one after another, so a second open waits for the first and then closes it.
    private var lifecycle: Task<Void, Never>?

    public init(opener: LibraryOpener = .standard) {
        self.opener = opener
    }

    /// Opens an existing library, or creates one in an empty folder when `create` is true.
    /// Any open library is closed first, and its ownership released, before the new one opens (LIB-9).
    public func open(_ url: URL, create: Bool = false) async {
        await serialized { await self.openNow(url, create: create) }
    }

    private func openNow(_ url: URL, create: Bool) async {
        await closeNow()
        generation += 1
        let current = generation
        phase = .opening(url)
        let opener = opener
        do {
            let opened = try await call { create ? try opener.initialize(url) : try opener.open(url) }
            guard current == generation else {
                _ = try? await call { opened.close() }
                return
            }
            library = opened
            requiresRecovery = false
            recoveryFailure = nil
            completedNotice = Self.notice(for: opened.completedOnOpen)
            phase = .open(url)
            await refresh()
        } catch {
            guard current == generation else { return }
            await fail(url, error: error, activity: create ? .creating : .opening, retried: false)
        }
    }

    /// Recover from the Recovery required view: replay again by reopening (REC-3, REC-4).
    public func retryOpen() async {
        let retried: Bool
        let url: URL
        switch phase {
        case .recoveryRequired(let failed, _, _, _):
            (url, retried) = (failed, true)
        case .openFailed(let failed, _):
            (url, retried) = (failed, false)
        default:
            return
        }
        await open(url)
        if retried, case .recoveryRequired(let url, let operations, let message, _) = phase {
            phase = .recoveryRequired(url, operations: operations, message: message, retried: true)
        }
    }

    /// Closes the open library after earlier calls finish, releasing ownership (LIFE-1). Safe to repeat.
    /// Without an open library, a failed open's state stays visible; `reset()` dismisses it.
    public func close() async {
        await serialized { await self.closeNow() }
    }

    private func closeNow() async {
        generation += 1
        guard let closed = library else {
            if case .opening = phase { phase = .closed }
            return
        }
        library = nil
        listing = nil
        listingFailure = nil
        completedNotice = nil
        requiresRecovery = false
        recoveryFailure = nil
        phase = .closed
        _ = try? await call { closed.close() }
    }

    /// Quitting: closes the open library before the app exits, without waiting for earlier session calls
    /// (LIFE-2, LIFE-3). Closing waits for the library's own queue, so a change in progress finishes; renders are
    /// cancelled and their workers reaped; later calls are refused. The phase and listing stay as they are,
    /// because the app is exiting. An open or close still in flight is left to process exit, which releases the
    /// lease too.
    public func closeForTermination() {
        generation += 1
        guard let closed = library else { return }
        library = nil
        closed.close()
    }

    private func serialized(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = lifecycle
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        lifecycle = task
        await task.value
    }

    /// Lists the library again and publishes the result; the previous listing stays on failure.
    public func refresh() async {
        guard let library, case .open = phase else { return }
        let current = generation
        do {
            let fresh = try await call { try library.list() }
            guard current == generation else { return }
            listing = fresh
            listingFailure = nil
            revision += 1
        } catch {
            guard current == generation else { return }
            listingFailure = LibraryMessage.describing(error, activity: .listing, libraryName: libraryName)
        }
    }

    /// Runs `body` with the open library off the main thread. A change refreshes the listing afterwards.
    public func perform<Value: Sendable>(
        _ activity: LibraryActivity, refreshing: Bool = true,
        _ body: @escaping @Sendable (NativeLibrary) throws -> Value
    ) async -> LibraryOutcome<Value> {
        guard let library, case .open = phase else {
            return .failure(LibraryMessage.describing(NativeLibraryError.closed, activity: activity)!)
        }
        let current = generation
        let result: Result<Value, Error>
        let blocked: Bool
        do {
            (result, blocked) = try await call {
                do {
                    return (.success(try body(library)), false)
                } catch {
                    return (.failure(error), library.requiresRecovery)
                }
            }
        } catch {
            (result, blocked) = (.failure(error), false)
        }
        guard current == generation else { return .ignored }
        if blocked { requiresRecovery = true }
        if refreshing || blocked { await refresh() }
        switch result {
        case .success(let value): return .success(value)
        case .failure(let error):
            guard let message = LibraryMessage.describing(error, activity: activity, libraryName: libraryName) else {
                return .ignored
            }
            return .failure(message)
        }
    }

    /// Runs a preview call with the open library on `worker` instead of the library worker, so a long render never
    /// holds up library calls and `close()` can cancel it (renders are cancelled through the library). Returns nil
    /// when no library is open, or when the library closed or changed before the call finished.
    func previewCall<Value: Sendable>(
        on worker: LibraryWorker, _ body: @escaping @Sendable (NativeLibrary) throws -> Value
    ) async -> Result<Value, Error>? {
        guard let library, case .open = phase else { return nil }
        let current = generation
        let result: Result<Value, Error>
        do {
            result = try await worker.run { Result { try body(library) } }
        } catch {
            result = .failure(error)
        }
        guard current == generation else { return nil }
        return result
    }

    /// Recover from a failed change without reopening (REC-5).
    public func recover() async {
        guard let library, case .open = phase else { return }
        let current = generation
        do {
            _ = try await call { try library.recover() }
            guard current == generation else { return }
            requiresRecovery = false
            recoveryFailure = nil
            await refresh()
        } catch {
            guard current == generation else { return }
            recoveryFailure = LibraryMessage.describing(error, activity: .recovering, libraryName: libraryName)
        }
    }

    /// Dismisses a failed open (Back in library selection) when no library is open.
    public func reset() {
        guard library == nil else { return }
        switch phase {
        case .openFailed, .recoveryRequired: phase = .closed
        default: break
        }
    }

    public func dismissCompletedNotice() {
        completedNotice = nil
    }

    private var libraryName: String? {
        switch phase {
        case .opening(let url), .open(let url), .openFailed(let url, _), .recoveryRequired(let url, _, _, _):
            url.lastPathComponent
        case .closed: nil
        }
    }

    private func call<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        pendingCalls += 1
        defer { pendingCalls -= 1 }
        return try await worker.run(body)
    }

    private func fail(_ url: URL, error: Error, activity: LibraryActivity, retried: Bool) async {
        let current = generation
        let opener = opener
        let committed = (try? await call { try opener.inspectOperations(url) })?.filter { $0.state == "committed" }
        guard current == generation else { return }
        let message =
            LibraryMessage.describing(error, activity: activity, libraryName: url.lastPathComponent)
            ?? LibraryMessage(title: "The library couldn't be opened", guidance: "Try again.")
        guard let committed, !committed.isEmpty else {
            phase = .openFailed(url, message)
            return
        }
        let operations = committed.map {
            PendingOperation(
                id: $0.id, kind: $0.kind,
                quarantineCommand: "fb-native recover \(Self.shellQuoted(url.path)) --quarantine \($0.id)")
        }
        phase = .recoveryRequired(url, operations: operations, message: message, retried: retried)
    }

    static func notice(for completed: [LibraryOperationRecord]) -> String? {
        guard !completed.isEmpty else { return nil }
        let kinds = completed.map { describeKind($0.kind) }
        let listed = Array(NSOrderedSet(array: kinds)).compactMap { $0 as? String }.joined(separator: ", ")
        return completed.count == 1
            ? "A change was interrupted when the library was last used (\(listed)). It has been completed."
            : "\(completed.count) changes were interrupted when the library was last used (\(listed)). "
                + "They have been completed."
    }

    static func describeKind(_ kind: String?) -> String {
        switch kind {
        case "import": "import"
        case "comment": "comment"
        case "files": "item change"
        case "tree-create": "folder creation or book unpacking"
        case "tree-move": "folder move"
        case "tree-delete": "folder deletion"
        default: "library change"
        }
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
