# Construction statistics

Calculate what a saved blueprint needs to be built and its footprint in game tiles.
The [statistics contract](../contracts/Statistics.md) defines the results; this guide covers using and changing them.

## Use the CLI

Statistics need a verified asset release, whose prototype map supplies placement items and collision geometry:

```sh
just library statistics "$library" "$item_id" --assets .cache/renderer-assets
just library statistics "$library" "$book_id" --entry 1.1 --assets .cache/renderer-assets
```

Select a book leaf by its stored indices, as for export and previews. Books and planners return
`applicable: false`. See the [CLI guide](Library-CLI.md#construction-statistics) for errors.

## Use the library API

Load and verify the map once, then reuse it:

```swift
let map = try PrototypeMap.load(release: assetsURL)   // verifies the release, binds its identity
let result = try library.statistics(id: itemId, entryPath: [1, 1], map: map)
```

`NativeLibrary.statistics` reads a snapshot of the entry under ownership and calculates off the library queue.
For an entry already in hand, call `BlueprintStatisticsCalculator.calculate(entry, map:)` directly; it is a pure
function with no I/O. In an optimized build a 6,814-entity leaf takes about 5 ms
([measurements](../validation/Statistics.md#performance-s7)), so results are not cached.

## Code

- `Sources/FactorioData/PrototypeMap.swift`: strict map model, loaded only from a verified release.
- `Sources/FactorioData/BlueprintStatistics.swift`: the calculator and result types.
- `Sources/FactorioData/LibraryStatistics.swift`: the `NativeLibrary` extension.
- `tools/reference/blueprint-statistics.mjs`: the JavaScript reference calculator the port started from.

The reference is a starting point, not a specification. Where the native behavior differs on purpose,
the contract lists the difference under "Differences from the web application".

## Tests

| Command | What it checks | Needs |
| --- | --- | --- |
| `just test` | Unit tests with a committed synthetic map, map loading, library and CLI integration, and parity | Parity runs only with the private map and generated reference outputs |
| `just statistics-golden` | Writes `.cache/statistics-golden.json`: reference results for 348 cases | Private map |
| `just statistics-test` | The 13 retained JavaScript reference tests | Private map |
| `just statistics-benchmark` | Optimized-build timings | Private release in `.cache/renderer-assets` |

Regenerate the reference outputs whenever the reference calculator, the fixtures, or the prototype map change.
The parity test refuses outputs generated from a different map.

## Changing the calculation

1. Update the contract first, including "Differences from the web application" for any intended departure.
2. Change the calculator and its unit tests in `Tests/FactorioDataTests/BlueprintStatisticsTests.swift`.
3. If the change departs from the reference, update the mapping or comparison in
   `Tests/FactorioDataTests/StatisticsParityTests.swift` so parity still checks everything else.
4. Run `just test`; with private assets, also `just statistics-golden` and the parity test.
