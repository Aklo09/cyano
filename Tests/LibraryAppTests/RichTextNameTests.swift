import Foundation
import PreviewRenderer
import Testing

@testable import LibraryApp

@Suite("Rich-text names")
struct RichTextNameTests {
    @Test("ICN-5, ICN-6: icon tags, other tags, closing tags, and malformed markup are told apart")
    func tokens() throws {
        let plate = try #require(IconReference(tagKind: "item", name: "iron-plate"))
        let gleba = try #require(IconReference(tagKind: "planet", name: "gleba"))
        let signal = try #require(IconReference(imagePath: "virtual-signal/signal-A"))
        #expect(
            RichTextName("[item=iron-plate,quality=rare]Smelter [planet=gleba]").tokens == [
                .icon(plate, quality: "rare", raw: "[item=iron-plate,quality=rare]"), .text("Smelter "),
                .icon(gleba, quality: nil, raw: "[planet=gleba]"),
            ])
        #expect(
            RichTextName("[color=red]Hot[/color] [img=virtual-signal/signal-A]").tokens == [
                .tag("[color=red]"), .text("Hot"), .tag("[/color]"), .text(" "),
                .icon(signal, quality: nil, raw: "[img=virtual-signal/signal-A]"),
            ])
        #expect(
            RichTextName("[gps=10,20] [technology=automation]").tokens == [
                .tag("[gps=10,20]"), .text(" "), .tag("[technology=automation]"),
            ])
        for malformed in ["[item=]", "[item]", "[Item=x]", "a [ b", "[[item=iron-plate", "[]", "1/2 [x"] {
            #expect(RichTextName(malformed).tokens.allSatisfy { if case .text = $0 { true } else { false } })
            #expect(RichTextName(malformed).textForm == malformed)
        }
        #expect(
            RichTextName("[[item=iron-plate]").tokens == [
                .text("["), .icon(plate, quality: nil, raw: "[item=iron-plate]"),
            ])
        #expect(RichTextName("").tokens.isEmpty)
    }

    @Test("ICN-7: the text form drops icon tags whatever the release and keeps other tags; icons alone become names")
    func textForm() {
        #expect(RichTextName("[item=iron-plate,quality=rare]Smelter 480/s").textForm == "Smelter 480/s")
        #expect(RichTextName("Belt [item=transport-belt] line").textForm == "Belt line")
        #expect(RichTextName("[color=red]Hot[/color]").textForm == "[color=red]Hot[/color]")
        #expect(RichTextName("[item=fusion-reactor]").textForm == "fusion reactor")
        #expect(RichTextName("[item=fusion-reactor,quality=legendary]").textForm == "fusion reactor, legendary")
        #expect(RichTextName("[planet=nauvis] [planet=gleba]").textForm == "nauvis gleba")
        #expect(RichTextName("Plain").textForm == "Plain")
        #expect(RichTextName("Rail Book  1").textForm == "Rail Book  1")
    }

    @Test("ICN-7: VoiceOver reads icons the release has by name in place, and other tags as written")
    func spoken() {
        let name = RichTextName("[item=iron-plate,quality=rare]Smelter [color=red]x[/color]")
        #expect(name.spoken(showing: nil) == "[item=iron-plate,quality=rare]Smelter [color=red]x[/color]")
    }

    @Test("ICN-7: rows sort by the text form, so a leading tag does not decide the order")
    func sorting() {
        func row(_ name: String) -> BrowserRow {
            BrowserRow(
                id: "item:" + name, name: name, kind: .blueprint, folder: "", folderPath: nil, itemId: name,
                updated: nil, created: nil, sizeBytes: nil)
        }
        let rows = [row("[item=iron-plate]Zinc"), row("Beta"), row("[planet=gleba]Alpha")]
        #expect(
            LibraryBrowserModel.sorted(rows, key: .name, ascending: true).map(\.name) == [
                "[planet=gleba]Alpha", "Beta", "[item=iron-plate]Zinc",
            ])
    }

    @Test("ICN-7: Save As TXT suggests the text form of the name")
    func fileNames() {
        #expect(
            ExportTarget(itemId: "x", entryPath: [], name: "[item=iron-plate]Smelter 480/s").fileName
                == "Smelter 480-s.txt")
        #expect(
            ExportTarget(itemId: "x", entryPath: [], name: "[item=fusion-reactor]").fileName == "fusion reactor.txt")
    }
}
