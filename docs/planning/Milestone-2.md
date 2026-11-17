# Milestone 2: complete library core

Date: 2026-11-13. Status: accepted ([acceptance record](../validation/Milestone-2.md)).
Roadmap entry: [plan](macOS-Plan.md#delivery-roadmap), milestone 2.

## Scope

Replacement, folder and item organization, unpacked-book import, deletion, and maintenance were delivered during
milestone 1 ([command validation](../validation/Library-Commands.md)) and hardened by the
[core revisions](Core-Revisions.md). The remaining work is construction statistics and milestone acceptance.

Statistics port the pure reference calculator in `tools/reference/blueprint-statistics.mjs` to Swift:

- They apply only to blueprint entries; books and upgrade/deconstruction planners have no statistics.
- Construction requirements group items by name and quality: placement, modules, installed equipment, and other
  inserted contents such as fuel. Bare equipment requests are reported separately and excluded from totals.
- The footprint is the axis-aligned building and tile rectangle in game tiles, from collision geometry,
  never from renderer sprites.
- Unknown entities, items, or qualities produce warnings and incomplete results.
  Invalid counts, directions, or positions are errors, not misleading totals.
- Prototype data comes from the private Factorio 2.1.23 map (146 entities, 342 items, 23 tiles, 6 qualities).

Exit condition: shared operations preserve identities, comments, originals, and recovery guarantees.

## Decisions

| # | Question | Decision |
| --- | --- | --- |
| 1 | Where the golden outputs derived from the private map live | Outside git, under `.cache/`. The parity test runs only where private assets exist; committed unit tests use a small hand-written map and run everywhere |
| 2 | Item ordering | Output uses UTF-8 byte order of name, then quality. Parity compares item sets independently of order |
| 3 | Re-validation against the running game | Not part of milestone 2. Rely on the original project's `cost_to_build` comparisons and exact parity with the JS reference |
| 4 | Prototype map source | Only from a verified asset release (`statistics/prototype-map.json`), binding statistics to that release identity |

## Subtasks

| # | Subtask | Delivers | Done when | Depends on |
| --- | --- | --- | --- | --- |
| S1 | Done: statistics contract | `docs/contracts/Statistics.md`: scope, requirement groups, footprint rules, completeness, result schema | Owner approves | — |
| S2 | Done: golden reference outputs | Node script running the JS calculator over all synthetic cases and every blueprint leaf in the fixtures and vendored visual tests, writing one JSON file under `.cache/` | Generation is reproducible; `just statistics-test` still passes | — |
| S3 | Done: prototype map in `FactorioData` | Strict `PrototypeMap` model loaded from a verified release and bound to its identity | Tests cover valid, malformed, wrong-version, unknown-field, and oversized maps | — |
| S4 | Done: calculator port | `BlueprintStatistics.calculate(entry, map)`, a pure function over codec `JSONValue`s | Unit tests with a committed synthetic map cover every rule exercised by the Node tests | S1, S3 |
| S5 | Done: parity with the JS reference | Swift test comparing S4 with S2 case by case: items, warnings, completeness, footprint within 1e-9 | Every case matches; any intended difference is listed in the contract | S2, S4 |
| S6 | Done: library and CLI integration | Library API taking item, entry path, and assets; `fb-native statistics <library> <item-id> [--entry <stored.indices>] --assets <release>`; books and planners report "not applicable"; missing assets give a clear error; versioned JSON results | CLI tests cover a blueprint, a book leaf, a planner, missing assets, and an unknown entity; source operations still need no assets | S4 |
| S7 | Done: performance check | Release-build timings for the 6,814-entity leaf and all 149 blueprint leaves of the large book | Recorded; caching decided only if measurements require it | S6 |
| S8 | Done: documentation | CLI guide, development guide, plan progress, session notes | Links checked | S6 |
| S9 | Done: milestone 2 acceptance | `docs/validation/Milestone-2.md`: exit condition per operation, statistics evidence, full checks, independence check | All checks pass; owner signs off on statistics for representative fixtures | S1–S8 |

## Reference behaviors the port must reproduce

The reference is a starting point: where the [contract](../contracts/Statistics.md) records a better app behavior,
that wins. Otherwise reproduce these details, each of which a careless port would silently change:

- **Rounding:** JavaScript `Math.round` rounds halves toward +∞, including negatives; Swift's default rounds away
  from zero. Mirror the reference with `(x × 10⁹ + 0.5).rounded(.down) / 10⁹`.
- **Numbers:** the codec keeps numbers as text; convert with correctly rounded parsing matching JavaScript,
  and treat 2⁵³ − 1 as the safe-integer limit.
- **Defaults:** direction `0`; quality `normal`; one item per inserted slot when the count is omitted;
  orientation `direction / 16`, applied only when the prototype says orientation affects collision;
  off-grid entities always use direction `0` geometry.
- **Footprint snapping:** a 1e-9 epsilon, snapping in the placement phase given by tile-width and tile-height parity.
- **Rails:** secondary collision boxes contribute to the footprint; placement follows the first placement choice
  (curved rail 3 rail items, half-diagonal 2).
- **Equipment and items:** `grid` equipment may be a string or an object; a legacy non-array `items` format warns.
- **Warnings:** natively they are grouped and coded (see the contract); parity maps reference strings to codes and counts.
