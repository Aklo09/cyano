import Foundation

/// Sticky across asset verification, source selection, worker startup, validation, and cache publication.
public final class PreviewCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    func check() throws { if isCancelled { throw PreviewError.cancelled } }
}
