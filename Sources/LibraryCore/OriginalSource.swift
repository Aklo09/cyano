import CryptoKit
import Foundation

/// Unmodified imported bytes. Format validation belongs to the forthcoming codec.
public struct OriginalSource: Sendable {
    public let bytes: Data
    public let sha256: String

    public init(bytes: Data) {
        self.bytes = bytes
        self.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
