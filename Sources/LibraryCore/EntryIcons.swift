/// One of the up to four signals an entry stores in its `icons` field, which the game shows as the entry's symbol
/// (spec ICN-1, ICN-2). The type is as stored: absent for items, `virtual` for virtual signals.
public struct EntryIcon: Codable, Sendable, Equatable {
    /// The game's slot, 1 to 4; the game packs filled slots in this order.
    public let index: Int
    public let type: String?
    public let name: String
    public let quality: String?

    public init(index: Int, type: String?, name: String, quality: String?) {
        self.index = index
        self.type = type
        self.name = name
        self.quality = quality
    }

    static let maximumText = 200

    var isValid: Bool {
        (1...4).contains(index) && !name.isEmpty && name.utf8.count <= Self.maximumText
            && (type?.utf8.count ?? 0) <= Self.maximumText && (quality?.utf8.count ?? 0) <= Self.maximumText
    }
}

extension BlueprintEntry {
    /// The entry's icons in slot order. Malformed members and repeated slots are left out, never an error, because
    /// the icons only decorate a name and the source stays as saved.
    public var icons: [EntryIcon] { EntryIcon.read(body["icons"]) }
}

extension EntryIcon {
    static func read(_ value: JSONValue?) -> [EntryIcon] {
        guard let members = value?.array else { return [] }
        var bySlot: [Int: EntryIcon] = [:]
        for member in members.prefix(64) {
            guard let index = member["index"]?.safeInteger, let signal = member["signal"],
                let name = signal["name"]?.string
            else { continue }
            let icon = EntryIcon(
                index: index, type: signal["type"]?.string, name: name, quality: signal["quality"]?.string)
            if icon.isValid, bySlot[index] == nil { bySlot[index] = icon }
        }
        return bySlot.keys.sorted().compactMap { bySlot[$0] }
    }
}
