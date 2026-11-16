# Local asset and planner tooling

Prepare private assets without depending on the original web repository.
Native builds consume committed planner resources and require no Node runtime.

## Pinned sources

The vendored fpsr source uses revision `2f7dc70f2681de530402556f757006e904e692d5`.
Its renderer sources, pipeline sources, owned placeholder artwork, and required fixtures are included.
Its license remains alongside those files.

The copied web-project source uses revision `bf80a5e3c5a3db942d1ab872462f157912883650`.
Its calculator and preparation helpers now resolve local dependencies and fixtures.

[The inventory](../../tools/provenance.json) records original paths, revisions, byte counts, and hashes.
Adapted files retain their original hashes alongside their current hashes.
Unmodified supplied blueprint strings are packaged as test resources.

## Local fpsr patches

Local changes to the vendored fpsr live as ordered patches in `tools/vendor/fpsr-patches/`, with paths relative to
the fpsr root so they also apply to a fresh upstream checkout:

| Patch | Change |
|---|---|
| `0001-inserter-indications.patch` | Alt-mode inserter pickup/drop markers: pipeline exports `pickup_position`/`insert_position` and `utility/indication-line`; `alt-mode.ts` draws them |
| `0002-planet-icons.patch` | Pipeline exports the `planet` prototypes' icons as `space-location/<planet>`, so planet signals and tags find them (milestone 4, R3) |

`tools/vendor/fpsr-patches/BASE` names the commit of this repository whose `tools/vendor/fpsr` is the pristine
upstream copy. `just tools-check` runs `tools/check-fpsr-patches.sh`, which extracts that tree, applies the patches
in order, and fails unless the result matches `tools/vendor/fpsr` exactly.

Keep the patches current whenever you change anything under `tools/vendor/fpsr`:

1. Make and commit the change as usual (`just planner-build` when renderer or planner inputs change; record the new
   hashes in `tools/provenance.json`, keeping each file's `sourceSha256`/`sourceBytes` and setting `adapted`).
2. Write the change as the next patch, from the commit before it to the commit with it:

   ```sh
   git diff --relative=tools/vendor/fpsr <commit before> <commit with change> -- tools/vendor/fpsr \
     > tools/vendor/fpsr-patches/0002-<short-name>.patch
   ```

   To amend an existing patch instead, regenerate that patch over its own range, or fold the change into it.
3. Add the patch to the table above and run `just tools-check`. Commit the patch with the change, or right after it.

Never edit `BASE` except during an upgrade.

## Upgrade fpsr

1. Replace `tools/vendor/fpsr` with the new upstream revision's renderer and pipeline sources, owned placeholder
   artwork, required fixtures, and license (the same subset as now; compare with `git ls-files tools/vendor/fpsr`).
2. Update the pinned revision everywhere it appears: `tools/planner-entry.ts`, `tools/build-planner.mjs`,
   `Sources/PreviewRenderer/PreviewProcess.swift`, `Sources/PreviewRenderer/PreviewWorker.swift`,
   `Tests/PreviewRendererTests/PlannerRuntimeTests.swift`, `tools/provenance.json` (`sources.fpsr.revision` and every
   fpsr file's revision, hashes, and byte counts, with no `adapted` entries yet), and the revision at the top of this
   guide. `git grep <old revision>` finds them.
3. Run `just planner-build`, `just tools-install` if dependencies changed, then commit this pristine import on its
   own and write its full hash to `tools/vendor/fpsr-patches/BASE` in the next step.
4. Apply the patches in order from the repository root:

   ```sh
   git apply --3way --directory=tools/vendor/fpsr tools/vendor/fpsr-patches/0001-inserter-indications.patch
   ```

   Resolve conflicts by hand. Drop a patch that upstream now covers, and remove its row above. Regenerate each
   remaining patch from the pristine import (step 2 of the previous section), so it applies cleanly again.
5. Run `just planner-build`, mark the patched files `adapted` in `tools/provenance.json`, and run `just tools-check`,
   `just planner-check`, `just assets-check`, `just lint`, and `just test`.
6. If the pipeline output changed, regenerate the private assets ([Regenerate](#regenerate)), reassemble the release,
   run `just statistics-golden`, and compare render databases as in the
   [2.1.24 validation](../validation/Renderer.md#inserter-indications-2026-11-15). Run the independence check.

## Install and verify

Use the Node version in the root `.nvmrc`.
Run these commands from the repository root:

```sh
just tools-install
just tools-check
just planner-check
just assets-check
```

The toolchain pins fpsr 0.0.3, esbuild 0.28.1, and tsx 4.23.0.
It pins sharp 0.35.5 and fflate 0.8.3.
The lockfile records transitive dependencies and integrity hashes.
These dependencies belong to development tooling, outside the Swift package.

The planner check rebuilds in memory and compares committed resources.
The generated metadata identifies all 42 bundled source inputs by hash.
The native resource includes fpsr's license.

The asset check imports the vendored pipeline through tsx's Node loader.
It neither launches the game nor regenerates assets.

## Private inputs

The current profile is Factorio 2.1.24, regenerated in this port (see [Regenerate](#regenerate)):

```text
private-assets/
  2.1.24/                       sprites, moved from the builder's <output>/2.1.24
  build-2.1.24/                 builder output: data-raw-dump.json, isolated game work directory
  statistics-reference/         game reference run: reference.json, cases.json, report.json
    prototype-map.json
```

The earlier copied 2.1.23 inputs remain as `private-assets/2.1.23/` and `private-assets/statistics-reference-2.1.23/`
for comparison; the tools no longer accept them.

These files are ignored by Git and excluded from native package resources.
Native build and planner-loading checks do not require them.
`just test` enforces this with `tools/check-artwork.py` (milestone 4, spec GEN-9): it fails when Git-tracked files,
package resources, or a built app bundle under `.cache/xcode` hold a file named like release data (atlas images,
render databases, `release.json`, `prototype-map.json`) or with the same bytes as a file in `private-assets/`. The
staging folders `profile/` and `game-work/` hold an isolated game configuration with project-written mods, not
artwork, and are not compared. `python3 tools/check-artwork.py --self-test` plants copies in a scratch tree and
expects both to be found.
For native image rendering, assemble these inputs into a new private release using the
[preview harness guide](Preview.md#prepare-a-private-release).
Run the retained statistics cases when the map is present:

```sh
just statistics-test
```

Generate the reference outputs for the native statistics parity test (milestone 2, S5):

```sh
just statistics-golden
```

It runs the reference calculator over all 348 cases the original evaluation used: 234 blueprint leaves from the
supplied fixtures and vendored fpsr fixtures, plus 114 synthetic cases. It writes `.cache/statistics-golden.json`,
which records each case's standalone blueprint string, its expected result, the input hashes, and the hashes of the
reference calculator and prototype map. Identical inputs produce identical bytes. The file is derived from the
private map, so it stays in the ignored `.cache/` directory.

## Regenerate

The asset builder uses the vendored pipeline and project-local Node dependencies.
Both steps need Factorio 2.1.24, stage an isolated game configuration and mods beneath a new private output,
and never use the normal game profile:

```sh
factorio="$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents"
node tools/asset-preparation/build-assets.mjs --factorio "$factorio" --output private-assets/build-2.1.24
mv private-assets/build-2.1.24/2.1.24 private-assets/2.1.24
node tools/asset-preparation/game-statistics-reference.mjs --factorio "$factorio" --output private-assets/statistics-reference-new
node tools/asset-preparation/evaluate-statistics.mjs --reference private-assets/statistics-reference-new --report private-assets/statistics-reference-new/report.json
```

Then move the previous `statistics-reference/` aside and rename `statistics-reference-new/` to it, the path the
assembly and statistics tools read. The builder refuses an existing output directory. It dumps prototype data, then distills and packs both tiers.
The game reference imports all 348 statistics cases in game; `evaluate-statistics.mjs` writes
`prototype-map.json` and exits 1 for the one expected failure, the modded `ee-infinity-loader` leaf of `v0.59.0.txt`.
Then assemble a release ([preview guide](Preview.md#prepare-a-private-release)) and run `just statistics-golden`.

First run (2026-11-15, Factorio 2.1.24): 143 entities, 23 tiles, 1395 icons, 6809 frames per tier. A second run the
same day added the planet icons (1400 icons, 6814 frames per tier; see the
[renderer validation](../validation/Renderer.md#planet-icons-2026-11-15)); it needed only the asset build, because the
prototype map does not depend on icons. Compared with the
copied 2.1.23 assets, the render databases gained only `utility/indication-line` and the inserter
`pickupPosition`/`insertPosition` data; the prototype map and every statistics golden result were identical apart
from the game version.

2026-11-16: the game reference moved to schema 2 to export the inventory order (each item's subgroup and order, and
every item group and subgroup), so the prototype map is now schema 2 and releases holding a schema 1 map are refused.
Only the statistics reference was regenerated; the previous one is kept as
`private-assets/statistics-reference-before-groups`. Evaluation gave the same 347 passes and one expected failure.
Apart from `schema` and the new fields the map is identical, and all 348 statistics golden results are identical;
only the map and reference calculator hashes changed. Reassemble any release from `private-assets/2.1.24` and the
new `private-assets/statistics-reference`.
