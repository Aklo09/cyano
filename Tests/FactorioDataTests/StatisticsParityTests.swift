import Foundation
import LibraryCore
import Testing

@testable import FactorioData

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
private let goldenURL = repository.appendingPathComponent(".cache/statistics-golden.json")
private let mapURL = repository.appendingPathComponent("private-assets/statistics-reference/prototype-map.json")

/// Reference warning strings mapped to native codes (statistics contract, "Differences from the web application").
private func nativeWarning(_ message: String) -> String? {
    let patterns: [(String, String)] = [
        ("^Unknown entity (.+)$", "UNKNOWN_ENTITY name=$1"),
        ("^Unmeasured geometry for (.+), direction (\\d+)$", "UNMEASURED_GEOMETRY name=$1 direction=$2"),
        ("^Unknown item (.+)$", "UNKNOWN_ITEM name=$1"),
        ("^Unknown quality (.+)$", "UNKNOWN_QUALITY quality=$1"),
        ("^No placement item for (.+)$", "NO_PLACEMENT_ITEM name=$1"),
        ("^Entity (.+) is not blueprint-buildable$", "NOT_BLUEPRINT_BUILDABLE name=$1"),
        ("^Unsupported legacy item format on (.+)$", "LEGACY_ITEM_FORMAT name=$1"),
        ("^Ambiguous or unknown equipment item for (.+)$", "UNKNOWN_EQUIPMENT name=$1"),
        ("^Unknown tile (.+)$", "UNKNOWN_TILE name=$1"),
    ]
    for (pattern, template) in patterns {
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(message.startIndex..., in: message)
        if let match = regex.firstMatch(in: message, range: range) {
            return regex.replacementString(for: match, in: message, offset: 0, template: template)
        }
    }
    return nil
}

private func describe(_ warning: StatisticsWarning) -> String {
    var text = warning.code
    if let name = warning.name { text += " name=\(name)" }
    if let quality = warning.quality { text += " quality=\(quality)" }
    if let direction = warning.direction { text += " direction=\(direction)" }
    return text
}

private func items(_ value: Any?) -> [String] {
    ((value as? [[String: Any]]) ?? []).map { "\($0["name"]!)/\($0["quality"]!)/\($0["count"]!)" }.sorted()
}

private func items(_ value: [StatisticsItem]) -> [String] {
    value.map { "\($0.name)/\($0.quality)/\($0.count)" }.sorted()
}

private func close(_ expected: Any?, _ actual: Double?) -> Bool {
    switch (expected as? Double, actual) {
    case (nil, nil): return expected == nil || expected is NSNull
    case (let lhs?, let rhs?): return abs(lhs - rhs) <= 1e-9
    default: return false
    }
}

private func close(_ expected: Any?, _ actual: StatisticsBounds?) -> Bool {
    guard let bounds = expected as? [String: Double] else {
        return (expected == nil || expected is NSNull) && actual == nil
    }
    guard let actual else { return false }
    return close(bounds["minX"], actual.minX) && close(bounds["minY"], actual.minY)
        && close(bounds["maxX"], actual.maxX) && close(bounds["maxY"], actual.maxY)
}

/// Every difference between one reference case and the native result, as readable lines.
private func differences(_ expected: [String: Any], _ actual: BlueprintStatistics) -> [String] {
    var found: [String] = []
    func check(_ condition: Bool, _ what: String) { if !condition { found.append(what) } }
    check(expected["gameVersion"] as? String == actual.gameVersion, "gameVersion")
    check(expected["entities"] as? Int == actual.entities, "entities")
    check(expected["tiles"] as? Int == actual.tiles, "tiles")
    check(expected["complete"] as? Bool == actual.complete, "complete")
    check(expected["requirementsComplete"] as? Bool == actual.requirementsComplete, "requirementsComplete")
    for (key, value) in [
        ("constructionItems", actual.constructionItems), ("placement", actual.placement),
        ("modules", actual.modules), ("equipment", actual.equipment), ("otherInserted", actual.otherInserted),
        ("equipmentRequests", actual.equipmentRequests),
    ] {
        check(items(expected[key]) == items(value), "\(key): \(items(expected[key])) vs \(items(value))")
    }
    // Group reference strings by mapped code, keeping first-occurrence order, then compare with native warnings.
    var order: [String] = []
    var counts: [String: Int] = [:]
    for message in (expected["warnings"] as? [String]) ?? [] {
        guard let mapped = nativeWarning(message) else {
            found.append("unmapped reference warning: \(message)")
            continue
        }
        if counts[mapped] == nil { order.append(mapped) }
        counts[mapped, default: 0] += 1
    }
    let reference = order.map { "\($0) count=\(counts[$0]!)" }
    let native = actual.warnings.map { "\(describe($0)) count=\($0.count)" }
    check(reference == native, "warnings: \(reference) vs \(native)")
    let footprint = expected["footprint"] as? [String: Any] ?? [:]
    check(footprint["complete"] as? Bool == actual.footprint.complete, "footprint.complete")
    check(
        close(footprint["width"], actual.footprint.width),
        "width: \(footprint["width"] ?? "nil") vs \(actual.footprint.width as Any)")
    check(
        close(footprint["height"], actual.footprint.height),
        "height: \(footprint["height"] ?? "nil") vs \(actual.footprint.height as Any)")
    check(close(footprint["bounds"], actual.footprint.bounds), "bounds")
    if !actual.footprint.complete {
        check(close(footprint["knownBounds"], actual.footprint.knownBounds), "knownBounds")
    }
    return found
}

@Suite("Statistics parity with the reference calculator")
struct StatisticsParityTests {
    @Test(
        "Every reference case matches the native calculator on the contract's semantics",
        .enabled(
            if: FileManager.default.fileExists(atPath: goldenURL.path)
                && FileManager.default.fileExists(atPath: mapURL.path),
            "Needs the private prototype map and `just statistics-golden`"))
    func parity() throws {
        let mapBytes = try Data(contentsOf: mapURL)
        let golden = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: goldenURL)) as? [String: Any])
        // The reference outputs must come from exactly this map, or a mismatch would mean nothing.
        #expect(golden["prototypeMapSha256"] as? String == OriginalSource(bytes: mapBytes).sha256)
        let map = try PrototypeMap.parse(mapBytes, assetIdentity: String(repeating: "0", count: 64))
        let cases = try #require(golden["cases"] as? [[String: Any]])
        #expect(cases.count == 348)
        var failures: [String] = []
        for row in cases {
            let id = row["id"] as? String ?? "?"
            do {
                let entry = try BlueprintCodec.decode(Data((row["string"] as? String ?? "").utf8)).root
                let result = try BlueprintStatisticsCalculator.calculate(entry, map: map)
                if let message = row["error"] as? String {
                    failures.append("\(id): reference failed (\(message)) but native returned a result")
                    continue
                }
                guard case .applicable(let actual) = result, let expected = row["expected"] as? [String: Any] else {
                    failures.append("\(id): not applicable natively")
                    continue
                }
                failures += differences(expected, actual).map { "\(id): \($0)" }
            } catch {
                if row["error"] == nil { failures.append("\(id): native error \(error)") }
            }
        }
        #expect(
            failures.isEmpty, "\(failures.count) differences, first: \(failures.prefix(10).joined(separator: "\n"))")
    }
}
