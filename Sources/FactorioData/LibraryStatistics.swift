import Foundation
import LibraryCore

extension NativeLibrary {
    /// Construction statistics for one saved entry. The entry is read under ownership; calculation runs off the
    /// library queue. Load the map once with `PrototypeMap.load(release:)` and reuse it across calls.
    public func statistics(id: String, entryPath: [Int] = [], map: PrototypeMap) throws -> StatisticsResult {
        try BlueprintStatisticsCalculator.calculate(entry(id: id, entryPath: entryPath), map: map)
    }
}
