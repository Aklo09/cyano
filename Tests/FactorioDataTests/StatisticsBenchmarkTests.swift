import Foundation
import LibraryCore
import Testing

@testable import FactorioData

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
private let release = repository.appendingPathComponent(".cache/renderer-assets")
private let book = repository.appendingPathComponent("Tests/LibraryCoreTests/Fixtures/Blueprints/v0.59.0.txt")

/// Milliseconds for the median of `runs` executions.
private func median(_ runs: Int = 5, _ body: () throws -> Void) rethrows -> Double {
    var samples: [Double] = []
    for _ in 0..<runs {
        let start = ContinuousClock.now
        try body()
        let elapsed = ContinuousClock.now - start
        samples.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    return samples.sorted()[runs / 2]
}

/// Every blueprint leaf in a book, addressed by actual stored indices.
private func leaves(_ entry: BlueprintEntry) throws -> [BlueprintEntry] {
    guard entry.kind == .book else { return entry.kind == .blueprint ? [entry] : [] }
    return try (entry.body["blueprints"]?.array ?? []).flatMap { child in
        try leaves(BlueprintEntry(value: child, path: entry.path + [child["index"]?.safeInteger ?? -1]))
    }
}

@Suite("Statistics performance")
struct StatisticsBenchmarkTests {
    /// Run with `just statistics-benchmark`: a release build, the private release, and FB_NATIVE_BENCHMARK=1.
    @Test(
        "Statistics timings for the large leaf and every leaf of the large book",
        .enabled(
            if: ProcessInfo.processInfo.environment["FB_NATIVE_BENCHMARK"] == "1"
                && FileManager.default.fileExists(atPath: release.path),
            "Benchmark: set FB_NATIVE_BENCHMARK=1 with the private release present"))
    func timings() throws {
        let mapBytes = try Data(contentsOf: release.appendingPathComponent(PrototypeMap.path))
        var map: PrototypeMap?
        let load = try median(3) { map = try PrototypeMap.load(release: release) }
        let parse = try median {
            _ = try PrototypeMap.parse(mapBytes, assetIdentity: String(repeating: "0", count: 64))
        }
        let document = try BlueprintCodec.decode(Data(contentsOf: book))
        let large = try document.entry(at: [1, 1])
        let all = try leaves(document.root)
        let loaded = try #require(map)
        let decode = try median { _ = try BlueprintCodec.decode(Data(contentsOf: book)) }
        let largeLeaf = try median { _ = try BlueprintStatisticsCalculator.calculate(large, map: loaded) }
        let every = try median {
            for leaf in all { _ = try BlueprintStatisticsCalculator.calculate(leaf, map: loaded) }
        }
        let report = String(
            format: """
                STATISTICS-BENCHMARK map load with release verification %.0f ms; map parse alone %.1f ms;
                STATISTICS-BENCHMARK book decode %.1f ms; 6,814-entity leaf %.2f ms; all %d leaves %.1f ms (%.3f ms each)
                """, load, parse, decode, largeLeaf, all.count, every, every / Double(all.count))
        print(report)
        #expect(all.count > 100)
    }
}
