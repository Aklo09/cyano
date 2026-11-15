import Foundation
import LibraryCore

/// A book opened in the item list like a folder: a saved item and the stored indices of the (nested) book shown.
public struct OpenBook: Sendable {
    public let itemId: String
    public let itemName: String
    /// The source hash the entries were decoded from; a replaced source reloads them.
    public let sourceSha256: String
    public let path: [Int]
    /// Names of the books from the root book down to the shown one, for the path bar.
    public let trail: [String]
    /// The shown book entry once decoded.
    public var entry: BlueprintEntry?
    public var failure: LibraryMessage?
}

/// What the inspector shows for an item or entry (BOOK-5, BOOK-5a, BOOK-6).
public struct EntryDetail: Equatable, Sendable {
    public let name: String
    public let kind: ItemKind
    /// "major.minor.patch", or nil when the stored version is invalid.
    public let version: String?
    public let description: String
    /// Planner settings as text lines; empty for blueprints and books.
    public let settings: [String]
    /// For entries inside a book: "Entry 5.0 in Rail Book".
    public let location: String?
    public let entryCount: Int?
    /// The entry's icons in slot order (ICN-2).
    public let icons: [EntryIcon]
}

/// Reads books, entries, versions, and planner settings from decoded blueprint JSON.
public enum BlueprintEntryReader {
    /// A book's immediate children in stored order, each with its actual stored index (BOOK-1, BOOK-2).
    public static func children(of book: BlueprintEntry) -> [BlueprintEntry] {
        guard book.kind == .book, let members = book.body["blueprints"]?.array else { return [] }
        return members.compactMap { member in
            guard let index = member["index"]?.safeInteger else { return nil }
            return try? BlueprintEntry(value: member, path: book.path + [index])
        }
    }

    public static func kind(_ entry: BlueprintEntry) -> ItemKind {
        ItemKind(stored: entry.kind.rawValue)
    }

    /// The entry's label as stored, rich-text tags included (shown as icons, ICN-5), or a kind-specific untitled name
    /// when it has none.
    public static func name(_ entry: BlueprintEntry) -> String {
        let label = (entry.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Untitled " + kind(entry).label : label
    }

    /// Factorio packs versions as four 16-bit parts; the first three are shown (BOOK-5a).
    public static func version(_ packed: Int) -> String? {
        guard packed > 0 else { return nil }
        let major = packed >> 48
        let minor = (packed >> 32) & 0xFFFF
        let patch = (packed >> 16) & 0xFFFF
        guard major <= 0xFFFF else { return nil }
        return "\(major).\(minor).\(patch)"
    }

    /// Stored indices as shown to the owner, for example "5.0".
    public static func pathText(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: ".")
    }

    public static func detail(_ entry: BlueprintEntry, bookName: String? = nil) -> EntryDetail {
        let kind = kind(entry)
        return EntryDetail(
            name: name(entry), kind: kind, version: version(entry.version), description: entry.description,
            settings: kind == .upgradePlanner || kind == .deconstructionPlanner ? settings(entry) : [],
            location: entry.path.isEmpty
                ? nil : "Entry \(pathText(entry.path)) in \(bookName.map { RichTextName($0).textForm } ?? "the book")",
            entryCount: entry.kind == .book ? children(of: entry).count : nil, icons: entry.icons)
    }

    /// Planner settings as readable lines (BOOK-6): mappings, filters, then every other setting as compact JSON.
    public static func settings(_ entry: BlueprintEntry) -> [String] {
        guard case .object(let members) = entry.body["settings"] ?? .null else { return [] }
        var lines: [String] = []
        for member in members where member.key != "description" {
            switch member.key {
            case "mappers":
                lines.append("Mappings:")
                for mapper in member.value.array ?? [] {
                    let from = mapper["from"].map(signal) ?? "nothing"
                    let to = mapper["to"].map(signal) ?? "nothing"
                    let index = mapper["index"]?.safeInteger.map { "\($0): " } ?? ""
                    lines.append("  \(index)\(from) → \(to)")
                }
            case "entity_filters", "tile_filters":
                let title = member.key == "entity_filters" ? "Entity filters:" : "Tile filters:"
                let names = (member.value.array ?? []).map(signal)
                lines.append(title + (names.isEmpty ? " none" : " " + names.joined(separator: ", ")))
            default:
                lines.append("\(member.key.replacingOccurrences(of: "_", with: " ")): \(compact(member.value))")
            }
        }
        return lines
    }

    /// A signal or filter as text: its name, with type and quality when present.
    static func signal(_ value: JSONValue) -> String {
        guard let name = value["name"]?.string else { return compact(value) }
        var extras: [String] = []
        if let type = value["type"]?.string, type != "item" { extras.append(type) }
        if let quality = value["quality"]?.string, quality != "normal" { extras.append(quality) }
        return extras.isEmpty ? name : "\(name) (\(extras.joined(separator: ", ")))"
    }

    static func compact(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        case .bool(let flag): return flag ? "yes" : "no"
        case .number(let number): return number.literal
        case .null: return "none"
        default:
            guard let data = try? value.encoded(maximum: 64 * 1024) else { return "…" }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
