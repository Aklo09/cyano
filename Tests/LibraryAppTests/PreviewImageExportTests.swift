import AppKit
import Foundation
import Testing

@testable import LibraryApp

@MainActor
@Suite("Preview images", .serialized)
struct PreviewImageExportTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cyano-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test("IMG-2: the suggested name is the name's text form with separators replaced, plus .png")
    func fileNames() {
        #expect(PreviewImageExport.fileName("[item=iron-plate]Smelter 480/s") == "Smelter 480-s.png")
        #expect(PreviewImageExport.fileName("Rail Book — Entry 5.0") == "Rail Book — Entry 5.0.png")
        #expect(PreviewImageExport.fileName("") == "Preview.png")
    }

    @Test("IMG-2, IMG-3: saving writes the exact bytes; replacing moves the old file to the Trash first")
    func save() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Smelter.png")
        #expect(PreviewImageExport.save(png, to: url, library: nil) == .saved(bytes: png.count))
        #expect(try Data(contentsOf: url) == png)
        let newer = png + Data([4])
        #expect(PreviewImageExport.save(newer, to: url, library: nil) == .saved(bytes: newer.count))
        #expect(try Data(contentsOf: url) == newer)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Smelter.png"])
    }

    @Test("IMG-4, IMG-5: a destination inside the library is refused, and a failed write leaves no file")
    func refusals() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = folder.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: false)
        let inside = library.appendingPathComponent("Preview.png")
        #expect(PreviewImageExport.save(png, to: inside, library: library) == .insideLibrary)
        #expect(!FileManager.default.fileExists(atPath: inside.path))
        let missing = folder.appendingPathComponent("No Such Folder/Preview.png")
        guard case .failed(let message) = PreviewImageExport.save(png, to: missing, library: library) else {
            Issue.record("a write into a missing folder succeeded")
            return
        }
        #expect(message.title == "The image wasn't saved")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("IMG-1: Copy Image puts the exact PNG bytes on the clipboard as an image")
    func copy() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cyano-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("before", forType: .string)
        PreviewImageExport.copy(png, to: pasteboard)
        #expect(pasteboard.data(forType: .png) == png && pasteboard.string(forType: .string) == nil)
    }
}
