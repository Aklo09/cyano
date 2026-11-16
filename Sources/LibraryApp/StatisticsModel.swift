import FactorioData
import Foundation
import LibraryCore
import Observation

/// The entry whose statistics the inspector shows: a saved item's root or a book entry, with its kind and the source
/// hash it was listed with, so a replaced source calculates again.
public struct StatisticsTarget: Equatable, Hashable, Sendable {
    public let itemId: String
    public let entryPath: [Int]
    public let kind: ItemKind
    public let sourceSha256: String
}

extension LibraryBrowserModel {
    /// The inspector's item or entry (the same scope as comments), or nil when nothing single is inspected.
    public var statisticsTarget: StatisticsTarget? {
        guard let scope = commentScope, let item = listing?.items.first(where: { $0.id == scope.itemId }) else {
            return nil
        }
        let kind: ItemKind
        if book != nil, !isFiltering {
            // The open book itself when nothing inside it is selected, otherwise the selected entry.
            kind = selection.isEmpty ? .book : (selectedRows.first?.kind ?? .blueprint)
        } else {
            kind = ItemKind(stored: item.kind)
        }
        return StatisticsTarget(
            itemId: scope.itemId, entryPath: scope.entryPath, kind: kind, sourceSha256: item.metadata.sourceSha256)
    }
}

/// Statistics for the inspector (STA-1 to STA-6). Calculations take milliseconds, so there is no queue: each new
/// target replaces the previous request, and a late result for an earlier one is dropped.
@MainActor @Observable
public final class StatisticsModel {
    public enum State: Equatable, Sendable {
        /// Nothing inspected, or the release is still being checked (shown again when it is).
        case none
        /// Books and planners (STA-5).
        case notApplicable(ItemKind)
        /// No asset release is configured (STA-4).
        case noAssets
        /// The release is missing, changed, unverifiable, or overlaps the library (SET-3, SET-4).
        case assetsUnusable(LibraryMessage)
        /// The release verifies but its prototype map can't be used (STA-6).
        case mapUnsuitable(LibraryMessage)
        case calculating
        /// A result, with the map's inventory order for listing its items as the game does.
        case ready(BlueprintStatistics, ItemInventory)
        case failed(LibraryMessage)
    }

    public private(set) var state: State = .none
    private let session: LibrarySession
    private let assets: AssetSettings
    @ObservationIgnored private var request = 0

    public init(session: LibrarySession, assets: AssetSettings) {
        self.session = session
        self.assets = assets
    }

    /// Shows statistics for `target`. The owner calls it again when the target, its source, or the release changes.
    public func show(_ target: StatisticsTarget?) async {
        request += 1
        let current = request
        guard let target else {
            state = .none
            return
        }
        guard target.kind == .blueprint else {
            state = .notApplicable(target.kind)
            return
        }
        switch assets.state {
        case .none:
            state = .noAssets
            return
        case .checking:
            state = .none
            return
        case .problem(_, let message):
            state = .assetsUnusable(message)
            return
        case .verified:
            if case .failure(let message) = assets.availability(for: session.libraryURL) {
                state = .assetsUnusable(message)
                return
            }
        }
        state = .calculating
        let map: PrototypeMap
        switch await assets.prototypeMap() {
        case .success(let loaded): map = loaded
        case .failure(let message):
            guard current == request else { return }
            state = .mapUnsuitable(message)
            return
        }
        guard current == request else { return }
        let outcome = await session.perform(.statistics, refreshing: false) {
            try $0.statistics(id: target.itemId, entryPath: target.entryPath, map: map)
        }
        guard current == request else { return }
        switch outcome {
        case .success(.applicable(let statistics)): state = .ready(statistics, map.inventory)
        case .success(.notApplicable(let result)): state = .notApplicable(ItemKind(stored: result.entryKind))
        case .failure(let message): state = .failed(message)
        case .ignored: break
        }
    }
}

/// What the Statistics tab shows for one result (screen specs, "Statistics tab"): counts stay integers and
/// measurements stay numbers, so the view formats them for the Mac's locale and tests compare values.
public struct StatisticsPresentation: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        /// Shown only when not normal.
        public let quality: String?
        public let count: Int
    }

    /// One of the game's inventory tabs, or the equipment requests.
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        /// "reported, not included above" for equipment requests.
        public let note: String?
        public let rows: [Row]
    }

    public struct Warning: Identifiable, Equatable, Sendable {
        public let id: String
        public let count: Int
        /// The sentence after the count, for example "ee-infinity-loader: not in the game data; requirements and
        /// footprint are incomplete."
        public let text: String
    }

    public enum Footprint: Equatable, Sendable {
        case complete(width: Double, height: Double)
        case incomplete(atLeastWidth: Double, height: Double)
        case unknown
    }

    public let entities: Int
    public let tiles: Int
    public let footprint: Footprint
    public let requirementsComplete: Bool
    public let groups: [Group]
    public let warnings: [Warning]

    /// An empty blueprint: "This blueprint has no entities or tiles." with a 0 × 0 footprint.
    public var isEmpty: Bool { entities == 0 && tiles == 0 }

    /// Construction items appear once, split into the game's inventory tabs (Logistics, Production, and so on) in the
    /// game's order, with equipment requests last because they are not part of the total.
    public init(_ statistics: BlueprintStatistics, inventory: ItemInventory) {
        entities = statistics.entities
        tiles = statistics.tiles
        let print = statistics.footprint
        if print.complete, let width = print.width, let height = print.height {
            footprint = .complete(width: width, height: height)
        } else if let known = print.knownBounds {
            footprint = .incomplete(atLeastWidth: known.maxX - known.minX, height: known.maxY - known.minY)
        } else if print.complete {
            footprint = .complete(width: 0, height: 0)
        } else {
            footprint = .unknown
        }
        requirementsComplete = statistics.requirementsComplete
        // Items the map has no position for (none in practice: unknown items are left out with a warning) join the
        // game's own catch-all tab, which sorts last.
        let tabs = Dictionary(grouping: statistics.constructionItems) {
            inventory.positions[$0.name]?.group ?? "other"
        }
        func order(_ tab: String) -> [UInt8] {
            let known = tabs[tab]?.lazy.compactMap { inventory.positions[$0.name]?.groupOrder }.first
            return Array((known ?? "\u{10FFFF}").utf8) + [0] + Array(tab.utf8)
        }
        var named: [(String, String, String?, [StatisticsItem])] = tabs.keys
            .sorted { order($0).lexicographicallyPrecedes(order($1)) }
            .map { tab in
                let items = tabs[tab]!.sorted { left, right in
                    if left.name != right.name { return inventory.precedes(left.name, right.name) }
                    return Array(left.quality.utf8).lexicographicallyPrecedes(Array(right.quality.utf8))
                }
                return ("tab:\(tab)", Self.title(tab: tab), nil, items)
            }
        named.append(("requests", "Equipment requests", "reported, not included above", statistics.equipmentRequests))
        groups = named.filter { !$0.3.isEmpty }.map { id, title, note, items in
            Group(
                id: id, title: title, note: note,
                rows: items.map { item in
                    Row(
                        id: "\(id):\(item.name):\(item.quality)", name: item.name,
                        quality: item.quality == "normal" ? nil : item.quality, count: item.count)
                })
        }
        warnings = statistics.warnings.enumerated().map { index, warning in
            Warning(id: "warning:\(index)", count: warning.count, text: Self.text(for: warning))
        }
    }

    /// The game's English name for an inventory tab; tabs the game data adds later read as their internal name.
    static func title(tab: String) -> String {
        switch tab {
        case "logistics": "Logistics"
        case "production": "Production"
        case "intermediate-products": "Intermediate products"
        case "space": "Space"
        case "combat": "Combat"
        case "fluids": "Fluids"
        case "signals": "Signals"
        case "enemies": "Enemies"
        case "tiles": "Tiles"
        case "environment": "Environment"
        case "effects": "Effects"
        case "other": "Unsorted"
        default: tab.prefix(1).uppercased() + tab.dropFirst().replacingOccurrences(of: "-", with: " ")
        }
    }

    /// One warning worded from its code, naming what it involves; never the raw code (STA-3).
    static func text(for warning: StatisticsWarning) -> String {
        let subject = warning.name ?? warning.quality.map { "quality \($0)" } ?? "unnamed"
        let effect =
            switch warning.affects {
            case "requirements": "requirements are incomplete"
            case "footprint": "the footprint is incomplete"
            default: "requirements and footprint are incomplete"
            }
        let reason =
            switch warning.code {
            case "UNKNOWN_ENTITY": "not in the game data"
            case "UNMEASURED_GEOMETRY":
                "no collision geometry" + (warning.direction.map { " for direction \($0)" } ?? "")
            case "UNKNOWN_ITEM": "item not in the game data"
            case "UNKNOWN_QUALITY": "not in the game data"
            case "NO_PLACEMENT_ITEM": "no item places it"
            case "NOT_BLUEPRINT_BUILDABLE": "construction robots can't build it"
            case "LEGACY_ITEM_FORMAT": "inserted items use the pre-2.0 format and aren't counted"
            case "UNKNOWN_EQUIPMENT": "installed equipment with no single matching item"
            case "UNKNOWN_TILE": "tile not in the game data"
            default: "not understood"
            }
        return "\(subject): \(reason); \(effect)."
    }

    /// Selected rows as tab-separated text for ⌘C: name, quality when not normal, and count.
    public func copyText(rows ids: Set<String>) -> String {
        var lines: [String] = []
        for group in groups {
            for row in group.rows where ids.contains(row.id) {
                lines.append(
                    ([row.name] + (row.quality.map { [$0] } ?? []) + [String(row.count)]).joined(separator: "\t"))
            }
        }
        for warning in warnings where ids.contains(warning.id) {
            lines.append("\(warning.count) × \(warning.text)")
        }
        return lines.joined(separator: "\n")
    }
}
