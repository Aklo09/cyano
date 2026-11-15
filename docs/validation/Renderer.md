# Native renderer feasibility checkpoint

The standalone harness produces real PNG previews through JavaScriptCore, Core Graphics, Core Text, and Image I/O.
The completed library-command checkpoint was committed as `ee564db` before this work began.
Recorded: 2026-11-13, in the [foundation environment](Foundation.md#environment).
This completes the standalone painter/worker checkpoint; the whole application and milestone 1 acceptance remain in progress.

## Verified implementation

The pinned fpsr planner receives one JSON transfer per job, without filesystem/network callbacks.
It returns ordered commands and explicit unsupported-content warnings.
The native painter implements sprites, clipping/slices, flips/clockwise rotation, multiply tint,
rail pixel snapping/seam bleed, grouped shadows, icons/backings/alpha halos, wires,
train-chain overlays, snap grids, rectangles, and embedded-font Core Text labels.
Unknown commands, invalid frame references, nonfinite geometry, and exceeded limits cause refusal.

The owner launches a separate worker with one active job, a 60-second deadline,
a sampled 1 GiB resident-memory ceiling, bounded pipes, and cancellation.
The child has no library mutation interface and writes only stdout/stderr.
The owner reaps it before independently decoding the returned PNG and exclusively creating the requested output file.
Output paths inside the selected asset release are refused.
An stdin pipe lifeline ends the worker when its parent dies.
The worker is not an OS sandbox boundary; no claim of hostile-native-code containment is made.

Native sources adapted from fpsr are attributed in source headers and `tools/provenance.json`.
The MIT license remains in the planner resources and vendored source.
No external runtime dependency or licensed artwork was added to package resources.

## Automated verification

| Check | Result |
| --- | --- |
| `just test` | 69 native tests across nine suites and four Python assembly tests pass |
| `just renderer-test` | Planner, composition, process lifecycle, complete-job, and assembly coverage |
| Relocated isolation check | Fresh native build and all 69 native tests pass with both original checkouts unreadable, networking denied, and no Node on PATH |
| `just planner-check` | Regenerated bundle matches 42 local pinned inputs; no external imports |
| `just tools-check` | All 153 copied files and five pinned development dependencies remain valid; Python sources included in reference checks |
| CLI guide examples | Assembly, release verification, RS, large-leaf, and elevated-rail render workflows pass |
| `git diff --check` | Pass |

The isolation command is `python3 tools/check-independence.py --deny-path /Users/aklo/Projects/fb`.
It must run outside an enclosing sandbox to install its own restrictive policy.
The native tests generate their own valid atlas/release data and need no private artwork.
They exercise real worker planning/painting/encoding plus independent host decoding.
Python preparation tests cover exact inventories, existing-destination preservation, symlinks, shared files, and oversized inputs.

Pixel tests establish orientation, flips, clockwise rotation, draw ordering, transparent gutters,
canonical source slicing, clipping, tint, and shadow overlap at one half-opacity application.
Other composition tests exercise wires, chain joints, grids, icon backings/halos, and text.
Worker tests cover timeout/reaping, cancellation, one-active-job refusal, crash/malformed/oversized responses,
bad request framing, sampled memory enforcement, and parent death after the lifeline is installed.
A renderer-loading regression test rejects even valid-JSON manifest bytes changed after release verification.

## Private representative images

The same verified release contains 451 files and 211,964,616 bytes, with both 1x and 2x tiers.
Native Image I/O successfully decodes its WebP atlases. Rendering uses copied private assets only.
Measurements below are local debug-build observations, not release-performance guarantees.

| Input / actual entry path | Output | Commands | Observed wall time | Worker peak RSS |
| --- | --- | --- | --- | --- |
| `RS.txt`, root, 2x | 256 × 256 | 20 sprites, 12 icons, 12 wires | ~1.7 s | ~80 MiB |
| `bp.txt`, `1.1`, 2x | 1664 × 1568 | 2,093 sprites, 1,017 icons, 54 wires | ~3.6 s | ~214 MiB |
| `v0.59.0.txt`, `2.0` upgrade planner | 608 × 224 | 6 icons | ~3.0 s | ~119 MiB |
| `v0.59.0.txt`, `29.12` deconstruction planner | 512 × 192 | 5 icons, 1 text label | ~3.0 s | ~122 MiB |
| `v0.59.0.txt`, `1.1`, 6,814-entity leaf | 2048 × 810 | 15,173 sprites, 1,787 icons, 763 wires | ~5.5–5.7 s | ~341 MiB |
| `RS.txt`, root, 1x | 256 × 256 | 20 sprites, 12 icons, 12 wires | ~1.4 s | ~79 MiB |
| Pinned elevated-rail fixture, `0`, checkerboard | 1103 × 2048 | 532 sprites | ~3.2 s | ~265 MiB |

The large leaf reports `Unsupported entity: ee-infinity-loader (8)` under the official-only asset profile.
The other listed probes have no unsupported-content warnings.
The elevated-rail fixture contains 44 actual straight, half-diagonal, curved, ramp, and support entities.
The `bp.txt` example is useful for dense overlays and connections; name-based counts of “rail” in that book also include railgun entities.

Reports separate source decode, asset verification/loading, runtime startup, JavaScript parse/planning,
bridge/result decode, painting/atlas decode, PNG encoding, parent launch/validation, and supervised wall time.
For the dedicated elevated-rail run, painting/decoding is ~1.70 s, asset verification/loading ~1.29 s,
runtime startup ~10 ms, planning ~4 ms, bridge/result decoding ~7 ms, and PNG encoding ~22 ms.
Cancellation/reaping is tested separately with a stalled helper; the complete cancellation test completes in tens of milliseconds locally.
The memory-limit path is tested with a deliberately lowered test-only threshold, without allocating a gigabyte.

## Visual inspection

The assistant separately inspected RS, dense overlays, both planners, the large leaf, and the dedicated elevated-rail output.
Observed images have upright sprites/text, expected ordering, visible connections/icons, complete outer padding,
and coherent rail/ramp/support shadows. The checkerboard makes transparency and shadow separation directly visible.
These are visual smoke checks rather than the owner's approval or pixel parity with a game/reference renderer.
Connected-rail seam comparisons and full-corpus visual qualification remain outstanding.

Private images/reports are in ignored `.cache/renderer-review/`.
The guide runs also produced `.cache/preview-rs.png`, `.cache/preview-large.png`, and `.cache/preview-elevated.png`.
They are review artifacts, not distributable artwork or committed fixtures.

## Inserter indications (2026-11-15)

Previews lacked the yellow pickup and drop markers that alt mode shows for inserters. The vendored pipeline now
exports each inserter's `pickup_position`/`insert_position` and the `utility/indication-line` sprite, and the
planner's alt mode draws them (`inserterIndicationCommands` in `alt-mode.ts`). The assets were regenerated from
Factorio 2.1.24, the first full regeneration in this port; the asset profile moved from 2.1.23 to 2.1.24.

| Check | Result |
|---|---|
| Render databases, 2.1.24 vs copied 2.1.23 | Same 143 entities, 23 tiles, 5 terrain backgrounds, 103 fluid recipes; icons 1394 → 1395 (`utility/indication-line`) |
| Prototype map, 2.1.24 vs 2.1.23 | Same 146 entities, 342 items, 23 tiles, 6 qualities, 17 equipment items; only versions differ |
| Game statistics reference | 347 of 348 cases pass; the known modded `ee-infinity-loader` leaf fails as before |
| Statistics golden | All 348 expected results identical apart from `gameVersion` |
| `PlannerRuntimeTests` | Markers for the four directions and the long-handed inserter; none without the line sprite |
| `2i_Assembler.txt` | Lines on pickup tiles, arrows pointing into the drop tiles, as in the owner's reference screenshot |
| `v0.59.0.txt` leaf `1.1` | East- and west-facing inserters: vertical lines on the belts, arrows pointing into the machines |
| `RS.txt` | Visually unchanged |

Placement is calibrated on the owner's reference screenshot (84.96 px per tile): pickup lines sit 0.8 tiles and drop
arrows about 0.75 tiles from the inserter. The preview puts each marker at its target tile's centre, 0.2 tiles toward
the inserter, rather than at the raw prototype vectors (1 and 1.2 tiles), where facing drop arrows on a shared belt
crossed. The long-handed inserter's 1.8 tiles extrapolates the same rule; the screenshot has none.

## Review and remaining work

Manual review covered bounded codec/IR/image input, frame geometry, asset hash binding,
noninterpolated JavaScript calls, process framing, cancellation/termination, sampled memory limits,
independent PNG validation, exclusive publication, and source/asset preservation.
The attempted delegated review could not run because of a workspace credit limit; it supplied no review evidence.
No additional scanner was installed or run. Existing tests, provenance checks, and the manual review provide this checkpoint's evidence.

An early lifecycle assertion tried to read a PID file written by child user code after a 100 ms timeout.
The worker can be killed during dynamic-loader startup, before that write.
The test now observes the PID immediately after process launch and retains the same timeout and no-surviving-child assertion.

This is a standalone-source harness. Library-bound helper lease retention, owner-controlled cache publication,
render scheduling, retry/progress UI, and integration with library close are still pending.
The subsequent [library preview checkpoint](Library-Previews.md) implements the helper lease, cache, and close integration.
No helper receives a library path/lease or authoritative write interface in this checkpoint.
Terrain/space backgrounds and coordinate overlays remain outside the native painter's current options.
Source operations continue to work without assets.
Native statistics, the 1,000-root workload, power-loss qualification, owner visual approval, and the macOS UI remain separate work.
