import Foundation
import LibraryCore
import Testing
import zlib

private let version = "281479275151360"
private let minimal = #"{"blueprint":{"version":281479275151360}}"#

/// Independent one-shot zlib input builder; production uses bounded streaming operations.
private func compressed(_ data: Data) throws -> Data {
    var length = compressBound(uLong(data.count))
    var result = Data(count: Int(length))
    let status = result.withUnsafeMutableBytes { output in
        data.withUnsafeBytes { input in
            compress2(output.bindMemory(to: Bytef.self).baseAddress, &length,
                      input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count), Z_DEFAULT_COMPRESSION)
        }
    }
    try #require(status == Z_OK)
    result.count = Int(length)
    return result
}

private func source(_ json: String) throws -> Data {
    Data(("0" + (try compressed(Data(json.utf8))).base64EncodedString()).utf8)
}

private func framed(_ compressed: Data) -> Data {
    Data(("0" + compressed.base64EncodedString()).utf8)
}

@Suite("Bounded native blueprint codec")
struct BlueprintCodecTests {
    @Test("All supplied strings decode and export their original bytes")
    func suppliedCorpus() throws {
        let directory = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures/Blueprints"))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 9)
        for file in files {
            let bytes = try Data(contentsOf: file)
            let document = try BlueprintCodec.decode(bytes)
            #expect(try document.export() == bytes, Comment(rawValue: file.lastPathComponent))
            #expect(document.original.sha256 == OriginalSource(bytes: bytes).sha256)
        }
    }

    @Test("Root whitespace is preserved while format decoding trims its boundaries")
    func originalBytes() throws {
        var bytes = Data("\u{feff}\r\n  ".utf8)
        bytes.append(try source(minimal))
        bytes.append(Data(" \r\n".utf8))
        let document = try BlueprintCodec.decode(bytes)
        #expect(document.root.kind == .blueprint)
        #expect(try document.export() == bytes)
    }

    @Test("Sparse stored indices select entries independently of array order")
    func sparseEntries() throws {
        let json = #"{"blueprint_book":{"version":281479275151360,"blueprints":[{"index":19,"upgrade_planner":{"version":281479275151360}},{"index":5,"blueprint_book":{"version":281479275151360,"blueprints":[{"index":0,"blueprint":{"version":281479275151360,"label":"Leaf"}}]}}]}}"#
        let document = try BlueprintCodec.decode(source(json))
        #expect(try document.entry(at: [5, 0]).label == "Leaf")
        #expect(try document.entry(at: [19]).kind == .upgradePlanner)
        #expect(throws: BlueprintCodecError.invalidEntryPath) { try document.entry(at: [0]) }
        #expect(throws: BlueprintCodecError.invalidEntryPath) { try document.entry(at: [-1]) }
        #expect(throws: BlueprintCodecError.invalidEntryPath) { try document.entry(at: [19, 0]) }
        let exported = try BlueprintCodec.decode(document.export(at: [5, 0]))
        #expect(exported.root.kind == .blueprint)
        #expect(exported.root.label == "Leaf")
        #expect(exported.root.value["index"] == nil)
    }

    @Test("Unknown fields and arbitrary-precision numeric tokens survive entry export")
    func losslessUnknownContent() throws {
        let json = #"{"blueprint_book":{"version":281479275151360,"blueprints":[{"index":7,"future_wrapper":{"flag":true},"blueprint":{"version":281479275151360,"future":{"big":123456789012345678901234567890,"precise":1.000000000000000000000000000000000001,"huge":1e9999,"nested":[null,false,"😀"]}}}]}}"#
        let document = try BlueprintCodec.decode(source(json))
        let exported = try BlueprintCodec.decode(document.export(at: [7]))
        let original = try document.entry(at: [7])
        #expect(exported.root.body["future"] == original.body["future"])
        #expect(exported.root.value["future_wrapper"] == original.value["future_wrapper"])
        if case .number(let number) = exported.root.body["future"]?["precise"] {
            #expect(number.literal == "1.000000000000000000000000000000000001")
        } else { Issue.record("Unknown precise numeric value was lost.") }
    }

    @Test("Canonically equivalent Unicode keys retain distinct scalar sequences")
    func distinctUnicodeKeys() throws {
        let json = #"{"blueprint_book":{"version":281479275151360,"blueprints":[{"index":1,"blueprint":{"version":281479275151360,"future":{"é":1,"e\u0301":2}}}]}}"#
        let document = try BlueprintCodec.decode(source(json))
        let exported = try BlueprintCodec.decode(document.export(at: [1]))
        guard case .object(let members) = exported.root.body["future"] else {
            Issue.record("Future object was lost."); return
        }
        #expect(members.count == 2)
        #expect(!members[0].key.utf8.elementsEqual(members[1].key.utf8))
    }

    @Test("Both planner kinds accept minimal payloads and prefer settings descriptions")
    func planners() throws {
        for key in ["upgrade_planner", "deconstruction_planner"] {
            let json = "{\"\(key)\":{\"version\":\(version),\"description\":\"legacy\",\"settings\":{\"description\":\"\"}}}"
            let document = try BlueprintCodec.decode(source(json))
            #expect(document.root.description == "")
            #expect(try BlueprintCodec.decode(source("{\"\(key)\":{\"version\":\(version)}}")).root.version == 281479275151360)
        }
    }

    @Test("Malformed transport and noncanonical base64 are rejected")
    func invalidTransport() throws {
        for text in ["", "1AAAA", "0bad?", "0AAAA", "0e30=", "0AB==", "0AA=A", "0AAAA\nAAAA"] {
            #expect(throws: BlueprintCodecError.self) { try BlueprintCodec.decode(Data(text.utf8)) }
        }
        #expect(throws: BlueprintCodecError.self) { try BlueprintCodec.decode(Data([0xff, 0xfe])) }
        #expect(throws: BlueprintCodecError.self) { try BlueprintCodec.decode(framed(compressed(Data([0xff])))) }
    }

    @Test("Truncated streams, damaged checksums, raw deflate, and trailing streams fail")
    func invalidFraming() throws {
        let bytes = try compressed(Data(minimal.utf8))
        var damaged = bytes
        damaged[damaged.count - 1] ^= 1
        for payload in [Data(bytes.dropLast()), damaged, Data(bytes.dropFirst(2).dropLast(4)), bytes + Data([0]), bytes + bytes] {
            #expect(throws: BlueprintCodecError.self) { try BlueprintCodec.decode(framed(payload)) }
        }
        // Independently generated with Python gzip.compress(minimal, mtime=0).
        let gzip = try #require(Data(base64Encoded: "H4sIAAAAAAAC/6tWSsopTS0oyswrUbKqVipLLSrOzM9TsjKyMDQxtzQyNzU0NTQ2M6itBQCcAZGPKQAAAA=="))
        #expect(throws: BlueprintCodecError.self) { try BlueprintCodec.decode(framed(gzip)) }
    }

    @Test("Source, decoded-byte boundaries, and decompression bombs are bounded")
    func byteLimits() throws {
        let bytes = try source(minimal)
        var limits = BlueprintCodecLimits()
        limits.sourceBytes = bytes.count - 1
        #expect(throws: BlueprintCodecError.limitExceeded(.sourceBytes)) { try BlueprintCodec.decode(bytes, limits: limits) }
        limits.sourceBytes = bytes.count
        limits.decodedBytes = minimal.utf8.count
        _ = try BlueprintCodec.decode(bytes, limits: limits)
        limits.decodedBytes -= 1
        #expect(throws: BlueprintCodecError.limitExceeded(.decodedBytes)) { try BlueprintCodec.decode(bytes, limits: limits) }
        limits = BlueprintCodecLimits()
        limits.decodedBytes = 1024
        let bomb = try source("{\"blueprint\":{\"version\":\(version),\"label\":\"\(String(repeating: "x", count: 128 * 1024))\"}}")
        #expect(throws: BlueprintCodecError.limitExceeded(.decodedBytes)) { try BlueprintCodec.decode(bomb, limits: limits) }
    }

    @Test("JSON budgets are checked during parsing, including unknown subtrees")
    func structuralLimits() throws {
        let bytes = try source(minimal)
        var limits = BlueprintCodecLimits()
        limits.jsonNodes = 2
        #expect(throws: BlueprintCodecError.limitExceeded(.jsonNodes)) { try BlueprintCodec.decode(bytes, limits: limits) }
        limits.jsonNodes = 3
        limits.jsonDepth = 2
        _ = try BlueprintCodec.decode(bytes, limits: limits)
        limits.jsonDepth = 1
        #expect(throws: BlueprintCodecError.limitExceeded(.jsonDepth)) { try BlueprintCodec.decode(bytes, limits: limits) }
        let unknown = try source("{\"blueprint\":{\"version\":\(version),\"future\":\(String(repeating: "[", count: 130))0\(String(repeating: "]", count: 130))}}")
        #expect(throws: BlueprintCodecError.limitExceeded(.jsonDepth)) { try BlueprintCodec.decode(unknown) }
    }

    @Test("Entry counts, book depth, and entity/tile totals apply across a whole document")
    func documentLimits() throws {
        let json = "{\"blueprint_book\":{\"version\":\(version),\"blueprints\":[{\"index\":2,\"blueprint\":{\"version\":\(version),\"entities\":[{\"name\":\"unknown-mod\",\"position\":{\"x\":0,\"y\":0}}]}},{\"index\":9,\"blueprint\":{\"version\":\(version),\"tiles\":[{\"name\":\"concrete\",\"position\":{\"x\":0,\"y\":0}}]}}]}}"
        let bytes = try source(json)
        var limits = BlueprintCodecLimits()
        limits.entries = 2
        #expect(throws: BlueprintCodecError.limitExceeded(.entries)) { try BlueprintCodec.decode(bytes, limits: limits) }
        limits = BlueprintCodecLimits()
        limits.bookDepth = 0
        #expect(throws: BlueprintCodecError.limitExceeded(.bookDepth)) { try BlueprintCodec.decode(bytes, limits: limits) }
        limits = BlueprintCodecLimits()
        limits.entitiesAndTiles = 1
        #expect(throws: BlueprintCodecError.limitExceeded(.entitiesAndTiles)) { try BlueprintCodec.decode(bytes, limits: limits) }
        limits.entitiesAndTiles = 2
        _ = try BlueprintCodec.decode(bytes, limits: limits)
    }

    @Test("Thirty-two nested book levels are supported; the next level is refused")
    func maximumBookDepth() throws {
        var json = minimal
        for _ in 0..<32 {
            json = "{\"blueprint_book\":{\"version\":\(version),\"blueprints\":[{\"index\":5,\(json.dropFirst().dropLast())}]}}"
        }
        let document = try BlueprintCodec.decode(source(json))
        #expect(try document.entry(at: Array(repeating: 5, count: 32)).kind == .blueprint)
        json = "{\"blueprint_book\":{\"version\":\(version),\"blueprints\":[{\"index\":5,\(json.dropFirst().dropLast())}]}}"
        #expect(throws: BlueprintCodecError.limitExceeded(.bookDepth)) { try BlueprintCodec.decode(source(json)) }
    }

    @Test("The large supplied leaf exports as a complete standalone blueprint")
    func largeLeafExport() throws {
        let file = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures/Blueprints/v0.59.0.txt"))
        let document = try BlueprintCodec.decode(Data(contentsOf: file))
        let original = try document.entry(at: [1, 1])
        #expect(original.body["entities"]?.array?.count == 6814)
        let exported = try BlueprintCodec.decode(document.export(at: [1, 1]))
        #expect(exported.root.body == original.body)
    }

    @Test("Ambiguous or malformed known content cannot enter the library")
    func invalidShapes() throws {
        for json in [
            "[]", "true", "null", "{\"blueprint\":{}}",
            "{\"blueprint\":{\"version\":true}}",
            "{\"blueprint\":{\"version\":1.0000000000000000000000000001}}",
            "{\"blueprint\":{\"version\":9007199254740992}}",
            "{\"blueprint\":{\"version\":-1}}",
            "{\"blueprint\":{\"version\":\(version),\"label\":null}}",
            "{\"blueprint\":{\"version\":\(version),\"entities\":{}}}",
            "{\"blueprint\":{\"version\":\(version),\"entities\":[{\"name\":\"chest\",\"position\":{\"x\":1e9999,\"y\":0}}]}}",
            "{\"blueprint\":{\"version\":\(version)},\"upgrade_planner\":{\"version\":\(version)}}",
            "{\"blueprint_book\":{\"version\":\(version),\"blueprints\":[{\"index\":2,\"blueprint\":{\"version\":\(version)}},{\"index\":2.0,\"blueprint\":{\"version\":\(version)}}]}}",
        ] {
            #expect(throws: BlueprintCodecError.self) { try BlueprintCodec.decode(source(json)) }
        }
    }

    @Test("The JSON grammar rejects invalid escapes, duplicate keys, and trailing content")
    func invalidJSON() throws {
        for json in [
            #"{"blueprint":{"version":1,"version":2}}"#,
            #"{"blueprint":{"version":1,"\u0076ersion":2}}"#,
            #"{"blueprint":{"version":01}}"#,
            #"{"blueprint":{"version":1.}}"#,
            #"{"blueprint":{"version":1e}}"#,
            #"{"blueprint":{"version":+1}}"#,
            #"{"blueprint":{"version":1,}}"#,
            #"{"blueprint":{"version":1,"future":[0,]}}"#,
            #"{"blueprint":{"version":1,"label":"\q"}}"#,
            #"{"blueprint":{"version":1,"label":"\uD800"}}"#,
            #"{"blueprint":{"version":1}} true"#,
        ] {
            #expect(throws: BlueprintCodecError.self) { try BlueprintCodec.decode(source(json)) }
        }
    }

    @Test("Known safe integers support exact exponent notation and negative zero")
    func numericForms() throws {
        for (literal, expected) in [("1.0e2", 100), ("-0", 0), ("9007199254740991", 9_007_199_254_740_991)] {
            let document = try BlueprintCodec.decode(source("{\"blueprint\":{\"version\":\(literal)}}"))
            #expect(document.root.version == expected)
        }
        var limits = BlueprintCodecLimits()
        limits.jsonDepth = -1
        #expect(throws: BlueprintCodecError.invalidLimits) { try BlueprintCodec.decode(source(minimal), limits: limits) }
        limits = BlueprintCodecLimits()
        limits.sourceBytes += 1
        #expect(throws: BlueprintCodecError.invalidLimits) { try BlueprintCodec.decode(source(minimal), limits: limits) }
    }
}
