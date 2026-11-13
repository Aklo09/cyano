import CryptoKit
import Foundation
import LibraryCore
import Testing

private struct Inventory: Decodable {
    struct File: Decodable {
        let file: String
        let sha256: String
        let bytes: Int
    }
    let files: [File]
}

@Suite("Preserved source fixtures")
struct OriginalSourceTests {
    @Test("Supplied blueprint bytes match the frozen source inventory")
    func preservedFixtures() throws {
        let root = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
        let inventory = try JSONDecoder().decode(
            Inventory.self,
            from: Data(contentsOf: root.appendingPathComponent("inventory.json"))
        )
        #expect(inventory.files.count == 9)
        for file in inventory.files {
            let bytes = try Data(contentsOf: root.appendingPathComponent("Blueprints/\(file.file)"))
            let source = OriginalSource(bytes: bytes)
            #expect(source.bytes.count == file.bytes, Comment(rawValue: file.file))
            #expect(source.sha256 == file.sha256, Comment(rawValue: file.file))
            #expect(source.bytes == bytes)
        }
    }

    @Test("Whitespace and line endings remain part of the original")
    func whitespaceIsPreserved() {
        let bytes = Data("\r\n  0e30= \r\n".utf8)
        let source = OriginalSource(bytes: bytes)
        #expect(source.bytes == bytes)
        #expect(source.sha256 != OriginalSource(bytes: Data("0e30=".utf8)).sha256)
    }

    @Test("SHA-256 uses the standard lowercase representation")
    func knownHash() {
        #expect(
            OriginalSource(bytes: Data("abc".utf8)).sha256
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
