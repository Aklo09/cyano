import Foundation
import zlib

enum ZlibCodec {
    private static let chunkSize = 32 * 1024

    static func decompress(_ input: Data, maximum: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw BlueprintCodecError.compressionFailure
        }
        defer { inflateEnd(&stream) }
        return try input.withUnsafeBytes { source in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            while true {
                let remaining = maximum - output.count
                let capacity = remaining >= chunkSize ? chunkSize : remaining + 1
                let before = stream.avail_in
                let status = buffer.withUnsafeMutableBytes { destination in
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(capacity)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = capacity - Int(stream.avail_out)
                guard produced <= remaining else { throw BlueprintCodecError.limitExceeded(.decodedBytes) }
                output.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else {
                        throw BlueprintCodecError.invalidSource("Trailing data after the zlib stream.")
                    }
                    return output
                }
                guard status == Z_OK, produced > 0 || stream.avail_in < before else {
                    throw BlueprintCodecError.invalidSource("Invalid, incomplete, or unsupported zlib stream.")
                }
            }
        }
    }

    static func compress(_ input: Data, maximum: Int) throws -> Data {
        var stream = z_stream()
        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw BlueprintCodecError.compressionFailure
        }
        defer { deflateEnd(&stream) }
        return try input.withUnsafeBytes { source in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            while true {
                let before = stream.avail_in
                let status = buffer.withUnsafeMutableBytes { destination in
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return deflate(&stream, Z_FINISH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                guard produced <= maximum - output.count else {
                    throw BlueprintCodecError.limitExceeded(.sourceBytes)
                }
                output.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END { return output }
                guard status == Z_OK, produced > 0 || stream.avail_in < before else {
                    throw BlueprintCodecError.compressionFailure
                }
            }
        }
    }
}
