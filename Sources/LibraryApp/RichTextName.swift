import CoreGraphics
import PreviewRenderer
import SwiftUI

/// A name split into plain text and Factorio rich-text tags (spec "Icon tag", ICN-5 to ICN-7). Names are shown as
/// stored: icon tags become icons when the release has them, and every other tag stays as written.
public struct RichTextName: Equatable, Sendable {
    public enum Token: Equatable, Sendable {
        case text(String)
        /// A well-formed icon tag such as `[item=iron-plate,quality=rare]`, with its exact original text.
        case icon(IconReference, quality: String?, raw: String)
        /// Any other bracketed tag (`[color=red]`, `[/color]`, `[gps=1,2]`, unknown kinds), kept as written.
        case tag(String)
    }

    public let tokens: [Token]

    public init(_ name: String) {
        var tokens: [Token] = []
        var text = ""
        var rest = Substring(name)
        while let open = rest.firstIndex(of: "[") {
            text += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(where: { $0 == "]" || $0 == "[" }), rest[close] == "]"
            else {
                // A "[" with no closing "]" before the next "[" is plain text.
                text += "["
                rest = rest[afterOpen...]
                continue
            }
            let raw = String(rest[open...close])
            let token = Self.token(inner: rest[afterOpen..<close], raw: raw)
            if case .text(let plain) = token {
                text += plain
            } else {
                if !text.isEmpty { tokens.append(.text(text)) }
                text = ""
                tokens.append(token)
            }
            rest = rest[rest.index(after: close)...]
        }
        text += rest
        if !text.isEmpty { tokens.append(.text(text)) }
        self.tokens = tokens
    }

    /// `kind=payload` makes a tag; `kind` is lowercase letters and hyphens, as Factorio's tag names are.
    private static func token(inner: Substring, raw: String) -> Token {
        guard let equals = inner.firstIndex(of: "=") else {
            return inner.first == "/" && inner.dropFirst().allSatisfy(isKindCharacter) && inner.count > 1
                ? .tag(raw) : .text(raw)
        }
        let kind = String(inner[..<equals])
        let payload = inner[inner.index(after: equals)...]
        guard !kind.isEmpty, kind.allSatisfy(isKindCharacter), !payload.isEmpty else { return .text(raw) }
        let parts = payload.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var quality: String?
        for part in parts.dropFirst() {
            if part.hasPrefix("quality="), part.count > 8 { quality = String(part.dropFirst(8)) }
        }
        let reference =
            kind == "img"
            ? IconReference(imagePath: parts[0]) : IconReference(tagKind: kind, name: parts[0])
        guard let reference else { return .tag(raw) }
        return .icon(reference, quality: quality, raw: raw)
    }

    private static func isKindCharacter(_ character: Character) -> Bool {
        character == "-" || ("a"..."z").contains(character)
    }

    /// The name where icons cannot be drawn (window titles, suggested file names, sort order): icon tags removed
    /// whatever the release, other tags kept; a name of icons only becomes their spoken names (ICN-7).
    public var textForm: String {
        guard tokens.contains(where: { if case .icon = $0 { true } else { false } }) else {
            return tokens.map { token -> String in
                switch token {
                case .text(let text): text
                case .tag(let raw), .icon(_, _, let raw): raw
                }
            }
            .joined()
        }
        var kept = ""
        var afterIcon = false
        for token in tokens {
            switch token {
            case .icon:
                afterIcon = true
            case .text(let piece), .tag(let piece):
                // Removing an icon between two spaces leaves one space, not two.
                kept += afterIcon && kept.hasSuffix(" ") && piece.hasPrefix(" ") ? String(piece.dropFirst()) : piece
                afterIcon = false
            }
        }
        let trimmed = kept.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return tokens.compactMap { token -> String? in
            guard case .icon(let reference, let quality, _) = token else { return nil }
            return Self.spoken(reference, quality: quality)
        }
        .joined(separator: " ")
    }

    /// What VoiceOver reads: icons by name in place, everything else as shown (ICN-7).
    public func spoken(showing catalog: IconCatalog?) -> String {
        tokens.map { token -> String in
            switch token {
            case .text(let text): text
            case .tag(let raw): raw
            case .icon(let reference, let quality, let raw):
                catalog?.contains(reference) == true ? " " + Self.spoken(reference, quality: quality) + " " : raw
            }
        }
        .joined()
        .split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
    }

    static func spoken(_ reference: IconReference, quality: String?) -> String {
        var words = reference.name.replacingOccurrences(of: "-", with: " ")
        if let quality, quality != "normal" { words += ", " + quality }
        return words
    }

    /// The name as SwiftUI text, with each icon the release has drawn in place at `pointSize` (ICN-5, ICN-6).
    func text(catalog: IconCatalog?, pointSize: CGFloat) -> Text {
        tokens.reduce(Text(verbatim: "")) { result, token in
            switch token {
            case .text(let text): return result + Text(verbatim: text)
            case .tag(let raw): return result + Text(verbatim: raw)
            case .icon(let reference, let quality, let raw):
                guard let image = catalog?.badgedImage(for: reference, quality: quality) else {
                    return result + Text(verbatim: raw)
                }
                let icon = Image(decorative: image, scale: CGFloat(image.width) / pointSize)
                return result + Text(icon).baselineOffset(-pointSize * 0.2)
            }
        }
    }
}

/// A name with its rich-text icons, read by VoiceOver with icon names in place (ICN-5 to ICN-7).
struct RichNameText: View {
    let name: String
    var pointSize: CGFloat = 16
    @Environment(\.iconCatalog) private var catalog

    var body: some View {
        let rich = RichTextName(name)
        rich.text(catalog: catalog, pointSize: pointSize)
            .accessibilityLabel(rich.spoken(showing: catalog))
    }
}
