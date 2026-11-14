import Foundation

/// Runs blocking library calls one at a time, in submission order, off the main thread.
/// `NativeLibrary` methods block on the library's own queue (and `close()` waits for renders), so they run on this
/// dedicated serial queue instead of the cooperative thread pool.
final class LibraryWorker: Sendable {
    private let queue: DispatchQueue

    init(label: String = "fb-native.app.library-worker") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }
}
