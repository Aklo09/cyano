# Statistics validation

Evidence for construction statistics ([contract](../contracts/Statistics.md),
[milestone 2](../planning/Milestone-2.md)). Recorded: 2026-11-13 in the [foundation environment](Foundation.md#environment).

## Unit tests (S4)

`BlueprintStatisticsTests`: 18 tests with a committed hand-written prototype map, so they run without private data.
They cover every rule of the 13 reference Node tests (game-tile footprints, cardinal rotation, gaps and tiles,
translation invariance, rail costs and oriented diagonal geometry, secondary collision boxes, qualities and modules,
installed and requested equipment, fuel and logistics, off-grid vehicles, unknown prototypes, invalid data, robots)
and the app behaviors: grouped warnings, byte-order sorting, not-applicable books and planners,
JavaScript-compatible rounding, and the result JSON shape.

Deliberately removing secondary collision boxes failed the rail test; removing tile snapping failed six tests.

## Library and CLI integration (S6)

`LibraryStatisticsTests` runs the real `fb-native` against a synthetic library and release: a blueprint with
unknown entities (one grouped warning with count 2, bound to the release identity), a book leaf by stored index,
the book root and a planner (`applicable: false` with only the four contract fields), an invalid entry,
a missing `--assets` (`ASSETS_REQUIRED`), and a release map too thin for statistics (`INVALID_PROTOTYPE_MAP`).
Listing and export still work without assets. The library API test reuses one loaded map and shows that an
entry snapshot stays usable after its item is deleted.

With the private release, the 6,814-entity `v0.59.0.txt` leaf `1.1` reports its 8 `ee-infinity-loader`
entities as one `UNKNOWN_ENTITY` warning with count 8, and the book root reports not applicable.

## Parity with the reference calculator (S5)

`StatisticsParityTests` compares the calculator with `.cache/statistics-golden.json`
(`just statistics-golden`) on all 348 reference cases: 234 blueprint leaves from the supplied and vendored fpsr
fixtures, and 114 synthetic cases. It first requires that the outputs were generated from the same prototype map.

Each case is decoded from its standalone blueprint string and compared on the contract's semantics:
every requirement group as an order-independent set, warnings mapped to codes and grouped with counts in
first-occurrence order, completeness flags, entity and tile counts, game version, and footprint bounds, width,
and height within 10⁻⁹ with nulls in the same places.

| Result | Value |
| --- | --- |
| Cases compared | 348 |
| Differences | 0 |
| Footprint values | bit-identical in every case (checked once with the tolerance set to exact equality) |
| Reference cases that are incomplete | 2: construction and logistic robots, and the modded `ee-infinity-loader` |

Mutation checks: increasing one expected count in a copy of the reference outputs produced exactly one reported
difference; removing footprint rounding produced 1,041.

The parity test runs only where the private map and generated reference outputs exist; elsewhere it is reported
as disabled. Comparison with the game's own `cost_to_build` was done in the original project and is not repeated
in milestone 2.

## Performance (S7)

Optimized build on this machine (`just statistics-benchmark`, a release build with testing enabled, median of 5 runs;
it runs only with `FB_NATIVE_BENCHMARK=1` and the private release present):

| Work | Time |
| --- | --- |
| Load the map through full release verification | 304 ms |
| Parse the 1.4 MB map alone | 20 ms |
| Decode the 696 KB `v0.59.0.txt` book | 323 ms |
| Statistics for the 6,814-entity leaf `1.1` | 5.3 ms |
| Statistics for all 149 blueprint leaves of that book | 50.5 ms (0.34 ms each) |

Release CLI end to end (median of 5 processes):

| Command | Time |
| --- | --- |
| `assets-verify` | 284 ms |
| `statistics` on a small root | 316 ms |
| `statistics` on the 6,814-entity leaf | 642 ms |
| `export` of the same leaf, for comparison | 369 ms |

The calculation itself is negligible. A CLI call is dominated by release verification, which applications pay once by
loading the map with `PrototypeMap.load(release:)` and reusing it, and by source decoding, which every operation on
that item already pays. Statistics results are therefore not cached.
