# Milestone 2 acceptance

Milestone 2 (complete library core) is accepted.
Its exit condition, from the [plan](../planning/macOS-Plan.md#delivery-roadmap), is that shared operations
preserve identities, comments, originals, and recovery guarantees. It was re-verified on commit `9cf4980`,
and the owner approved construction statistics for representative fixtures on 2026-11-13.
Work items and decisions: [milestone 2 plan](../planning/Milestone-2.md). Recorded in the
[foundation environment](Foundation.md#environment).

## Checks on `9cf4980`

| Check | Result |
| --- | --- |
| `just build` | Pass |
| `just lint` | Strict swift-format lint reports no findings |
| `just test` | 116 tests and 4 Python assembly tests pass, including the 348-case statistics parity test and the private-map test |
| `just statistics-golden` | 348 cases, 0 reference errors; byte-identical to the S2 output (`sha256 893197c7…`) |
| `just statistics-test` | 13 of 13 retained JavaScript reference tests pass |
| `just tools-check` | 153 copied files, 42 planner inputs, and 5 pinned development dependencies remain valid |
| `just planner-check`, `just planner-test`, `just assets-check` | Pass |
| Relocated isolation | Build, tests, and executables pass with the original checkout unreadable, networking denied, and no Node on PATH |

The isolation command is `python3 tools/check-independence.py --deny-path /Users/aklo/Projects/fb`.
Private-data tests (parity, private map) are disabled inside the relocated copy, which holds no private assets.

## Exit condition per operation

Each row names the tests that establish the guarantees. "Recovery" means real process kills at publication
boundaries followed by deterministic replay, or preserved evidence when replay must refuse.

| Operation | Identity, comments, originals | Recovery |
| --- | --- | --- |
| Import, export, comments | Initialize, import, comment, close, reopen, and export exact original bytes; Book entry comments and standalone exports use actual stored paths; Concurrent comments serialize complete read-modify-write operations | Real process kills at import publication boundaries recover deterministically; Comments interrupted before or after their intent preserve identity and exact source |
| Move and rename | Moving and renaming preserve exact originals, identity, comments, and creation dates | All file mutation publication boundaries recover after actual process termination; Conflicting files after a committed rename preserve preimages and block recovery |
| Source replacement | Replacement keeps identity and dates and promotes removed-entry comments; Deleted and replaced originals move to the Trash byte-identical, with a library fallback | All file mutation publication boundaries recover after actual process termination (including the Trash step) |
| Item and comment deletion | Deleted and replaced originals move to the Trash byte-identical, with a library fallback | All file mutation publication boundaries recover after actual process termination |
| Folders | Folder organization, case-only names, collisions, cycles, and empty-only deletion | Folder move, empty deletion, and unpack publication recover after process termination; Folder moves record identity without content hashes and refuse a look-alike folder on replay; Recovery cannot interpret a nonempty folder as an empty-folder deletion |
| Unpacked books | Unpacked imports preserve sparse indices, descriptions, unknown fields and independent leaf identities | Folder move, empty deletion, and unpack publication recover after process termination |
| Listing and ID lookup | Listing uses a derived kind index that is rebuilt when missing or damaged and pruned to live sources; Duplicate item IDs are listed and refused as ambiguous | Damaged live hashes and unsupported metadata are reported without overwriting evidence |
| Maintenance | Scoped cache cleanup protects unknown formats and authoritative originals; Usage separates categories | Quarantining a refused operation reopens the library and keeps its evidence byte-identical; Staging cleanup removes only operations that never committed |
| Previews | Cache hits require no worker and preserve originals, comments, identities, and metadata; A source replaced or deleted during rendering is never published | Process death at every derived-cache publication boundary leaves originals intact and permits reuse or regeneration |
| Statistics | Missing or unsuitable assets give clear errors; source operations still need none | Read-only: statistics never write library files |

Ownership and confinement apply to all operations: Another process and a symlink alias cannot overlap the live owner;
Symlinks, hardlinks, FIFOs, and changed control inodes are refused; An orphaned helper holds no lease, descriptor,
or inherited environment and does not keep ownership.

## Construction statistics

Delivered under the approved [statistics contract](../contracts/Statistics.md);
evidence in the [statistics validation](Statistics.md): 18 unit tests with a committed map, strict map loading,
0 differences from the reference calculator on 348 cases with bit-identical footprints, library and CLI integration,
and optimized-build timings (6,814-entity leaf 5.3 ms) supporting the decision not to cache results.

## Owner approval of representative statistics

Computed with the release CLI against the verified private release; full results were kept in the ignored
`.cache/m2-acceptance/`.

| Blueprint | Entities / tiles | Footprint | Largest requirements | Warnings |
| --- | --- | --- | --- | --- |
| `RS.txt` | 7 / 0 | 4 × 4 | 5 decider combinators, 1 constant combinator, 1 selector combinator | — |
| `4x_Rocket_Silo.txt` | 96 / 0 | 29 × 28 | 64 speed module 3, 32 beacons, 16 express underground belts, 16 productivity module 3 | — |
| `Hazard_Patterns.txt` | 0 / 437 | 21 × 21 | 256 refined hazard concrete, 181 concrete | — |
| `bp.txt` `0.0` | 1,157 / 0 | 83 × 43 | 504 turbo belts, 256 quality module 2, 175 fast inserters, 106 bulk inserters | — |
| `bp.txt` `1.1` | 583 / 0 | 48 × 44.3984 | 216 legendary quality module 3, 204 legendary bulk inserters, 103 turbo belts, 58 turbo underground belts | — |
| Elevated-rail fixture `0` | 44 / 0 | 59.5 × 111.5 | 72 rails, 8 rail supports, 4 rail ramps | — |
| `v0.59.0.txt` `1.1` | 6,814 / 0 | incomplete (known 202 × 79) | 3,197 transport belts, 1,299 inserters, 393 efficiency modules, 345 medium poles | `ee-infinity-loader` × 8 |

Fractional sizes follow the contract: `bp.txt` `1.1` contains 20 off-grid cargo wagons, whose exact collision extents
are kept; the elevated-rail fixture stores 3 × 3 rail supports at whole-number positions, and saved positions are
never normalized. The owner approved these results on 2026-11-13.

## Carried forward

- The macOS application (milestone 3).
- Visible-item preview scheduling and full-corpus visual qualification, including connected-rail seams (milestone 4).
- The 1,000-root workload targets and power-loss durability (milestone 5 and separate acceptance work).
- Comparison of statistics with the game's own `cost_to_build`, decided out of milestone 2.
