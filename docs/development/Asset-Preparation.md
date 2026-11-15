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

First run (2026-11-15, Factorio 2.1.24): 143 entities, 23 tiles, 1395 icons, 6809 frames per tier. Compared with the
copied 2.1.23 assets, the render databases gained only `utility/indication-line` and the inserter
`pickupPosition`/`insertPosition` data; the prototype map and every statistics golden result were identical apart
from the game version.
