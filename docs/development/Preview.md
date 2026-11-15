# Native preview harness

Render a standalone TXT source or selected book leaf with the system JavaScriptCore planner,
Core Graphics composition, Core Text labels, and Image I/O atlas decoding and PNG encoding.
The harness works offline without Node or a running game.

## Prepare a private release

Build first, then assemble the already prepared private sprites and prototype map:

```sh
just build
python3 tools/assemble-asset-release.py --sprites private-assets/2.1.24 --prototype-map private-assets/statistics-reference/prototype-map.json --destination .cache/renderer-assets --id native-renderer
just library assets-verify .cache/renderer-assets
```

Assembly requires Python 3 and an existing destination parent. It refuses an existing destination.
If the release already exists and verifies, reuse it and skip assembly.
Failures can leave a partial build directory for inspection; the tool never replaces a previous release.
The renderer verifies the release again before using it.
Assembly copies existing licensed inputs; it does not regenerate Factorio artwork.
Both private inputs and `.cache/` outputs remain ignored by Git.

## Render an image

```sh
just preview render Tests/LibraryCoreTests/Fixtures/Blueprints/RS.txt --assets .cache/renderer-assets --output .cache/preview-rs.png
```

The output parent must exist and the PNG filename must be new.
Publication uses exclusive creation, refuses paths inside the asset release, and never overwrites a file.
The caller writes the image only after the worker exits successfully and its PNG independently decodes.
Successful stdout contains a JSON report; failures go to stderr.
The source file remains unchanged.

Select a book leaf by actual stored indices:

```sh
just preview render Tests/LibraryCoreTests/Fixtures/Blueprints/v0.59.0.txt --entry 1.1 --assets .cache/renderer-assets --output .cache/preview-large.png
```

This selects the supplied 6,814-entity leaf. A book container itself cannot be painted.
Upgrade and deconstruction planner leaves use the same selection syntax.
Missing entity/tile definitions produce explicit warnings in the report.

Render the dedicated elevated-rail fixture with a visible checkerboard:

```sh
just preview render tools/vendor/fpsr/fixtures/visual-tests/official-mods/elevated-rails.bp.txt --entry 0 --assets .cache/renderer-assets --output .cache/preview-elevated.png --checkerboard
```

By default PNGs retain transparency. `--checkerboard` paints an opaque checkerboard.
`--tier 1x` selects the lower-density prepared assets; the default is `2x`.
`--max-dimension` accepts 64 through 4096 pixels and defaults to 2048.
The painter fits the entire planned bounds, adding one tile of padding and capping scale at 32 pixels per tile.

## Execution and limits

`preview-probe` starts the adjacent `preview-worker` executable, with one active job per owner.
The worker receives framed source bytes and asset selection through stdin and returns a bounded JSON/PNG result through stdout.
No filesystem or network bridge is installed in JavaScriptCore.
The worker has no library mutation interface and writes no image or cache files.
It is a separate process, not an OS sandbox security boundary.

The owner enforces a 60-second deadline, observes a 1 GiB resident-memory ceiling at approximately 10 ms intervals,
and terminates/reaps the child on timeout, cancellation, or invalid oversized output.
The worker's pipe lifeline causes it to exit when its parent dies.
`PreviewProcess.cancel()` supports cancellation by an application caller; the probe has no interactive cancellation UI.

| Resource | Limit |
| --- | --- |
| Source bytes | Existing 16 MiB codec bound |
| Framed request | 24 MiB |
| Planner commands | 250,000 |
| Draw-list JSON transfer | 64 MiB |
| Output pixels | 4096 × 4096 maximum |
| Single atlas pixels | 16,777,216 |
| Decoded atlas cache | 128 MiB |
| Cropped/tinted/halo image cache | 64 MiB |
| Encoded PNG | 64 MiB |
| Worker response / diagnostics | 96 MiB / 64 KiB |

Consecutive shadow sprites flatten into a bounded output-sized transparency group before applying half opacity.
Packed atlas sizes remain separate from canonical sprite geometry, including the 1x tier.
The report separates source decoding, asset verification/loading, JavaScriptCore startup,
JavaScript parsing/planning, bridge/result decoding, painting/atlas decoding, PNG encoding,
process launch, parent validation, and total supervised wall time. Peak RSS comes from the worker.

## Alt-mode overlays

Previews always plan in alt mode. Besides recipe, filter and quality icons, splitter priorities, combinator flow,
and fluid ports, each inserter shows Factorio's yellow `indication_line` at its pickup position and
`indication_arrow`, pointing along the transfer, on its drop tile. The tiles come from the prototype's
`pickup_position` and `insert_position` (stored as `pickupPosition`/`insertPosition` in the render database),
rotated by the entity's direction. Each marker sits at its tile's centre, pulled 0.2 tiles toward the inserter, so
a line and a facing arrow on one belt stay apart: 0.8 tiles out for most inserters, 1.8 for the long-handed one.
A release without these fields or the `utility/indication-line` sprite renders inserters without markers.

## Qualification status

```sh
just renderer-test
just planner-check
```

Renderer tests generate their own tiny assets and need no private artwork.
They exercise successful subprocess rendering, pixel composition, bounds, crash/oversize rejection,
timeout, memory-limit enforcement, cancellation, parent death, and exclusive publication.
See [validation and image coverage](../validation/Renderer.md) for measurements and remaining work.

This harness operates on standalone source files. The separate [library preview command](Library-Previews.md)
implements saved-item ownership and derived caching.
Full-corpus visual approval is milestone 4 work (below).
Terrain/space backgrounds and coordinate overlays are not part of this painter checkpoint.

## Qualify the corpus

```sh
just qualify-corpus
just qualify-corpus --assets <release> --output <parent directory>
```

`tools/qualify-corpus.py` builds the release executables, imports the full supplied corpus (the nine fixtures in
`Tests/LibraryCoreTests/Fixtures/Blueprints` and the vendored `tools/vendor/fpsr/fixtures/visual-tests`) into a
scratch library, and renders every blueprint and planner leaf by stored indices with `fb-native preview`, one at a
time. The release defaults to `.cache/renderer-assets` and must verify first. Each run gets its own directory,
`.cache/qualification/<time>/`, holding:

- `report.json`: per leaf, the outcome or error code, dimensions, render time, peak memory, warnings, command kinds,
  and the number of rail entities, plus a summary;
- `index.html`: the contact sheet. Open it in a browser; filter by failures, warnings, rails, or planners, or by text;
  click a card for the viewer, which shows Fit, 100% (one image pixel per screen pixel), and 400% with pixelated
  scaling for rail seams, and lists the leaf's warnings. Arrow keys step through leaves, Esc closes;
- `images/` and `library/`: rendered PNGs and the scratch library with its cache.

Everything stays in `.cache/` because the images are derived from private artwork. The script decodes the
supplied strings only to enumerate leaves; the library imports and renders the exact bytes. It exits with status 1
when any leaf fails. The plan's review steps are in [milestone 4](../planning/Milestone-4.md), decision 2.
