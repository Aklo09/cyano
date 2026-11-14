# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENT.md

## Project

Native macOS (Swift 6.4, macOS 27+, Apple Silicon) port of a Factorio blueprint library web app.
It stores original blueprint strings in an ordinary local directory, with no authoritative database.
Current state and next steps are in `docs/Session-Notes.md`. The roadmap is in `docs/planning/macOS-Plan.md`.
Read the session notes before you start milestone work.

## Commands

All Swift commands go through `tools/swift.sh`, which keeps compiler and SwiftPM caches under `.cache/` and passes `--disable-sandbox`.
Do not call `swift` directly. Shortcuts are in `justfile` (`just --list`).

```sh
just build                 # all targets; no Node or private assets needed
just lint                  # swift-format --strict on Package.swift, Sources, Tests, App/Sources; must pass before committing
just format                # apply .swift-format (4 spaces, 120 cols); fix leftovers by hand
just test                  # main suites + python3 tools/test-asset-release.py
just codec-test | storage-test | asset-test | renderer-test   # focused suites
just planner-test          # JavaScriptCore planner self-test (no painting)
just library <args>        # run the fb-native CLI (just library --help)
just preview <args>        # run preview-probe; real images need verified private assets
just app-build [Release]   # build the macOS app via tools/xcode.sh (derived data in .cache/xcode)
just app-run               # build the Debug app and open it
just app-test              # app model suites: session, messages, selection, browsing, books, import, export (also in just test)
```

The app bundle comes from the thin Xcode project `App/FactorioBlueprintLibrary.xcodeproj`; build it through
`tools/xcode.sh` (or `just app-build`), not bare `xcodebuild`, so caches stay under `.cache/`.

Tests delete items; `tools/swift.sh test` redirects their removed originals to `.cache/test-trash` through
`FB_NATIVE_TRASH_DIRECTORY`. Running `swift test` directly would send them to the real Trash.

Run a single test (Swift Testing; suites are `struct`s):

```sh
sh tools/swift.sh test --filter BlueprintCodecTests
sh tools/swift.sh test --filter 'BlueprintCodecTests/<test function name>'
```

Node tooling (`tools/`, Node 24.22.1 per `.nvmrc`) is for development only, never for native builds:
`just tools-install` (npm ci, lifecycle scripts disabled), `just tools-check`, `just planner-check`, `just assets-check`.
`just statistics-test` and `just statistics-golden` need the private prototype map; the statistics parity test in
`just test` runs only when the map and `.cache/statistics-golden.json` exist. `just statistics-benchmark` times an
optimized build with the private release.

Independence check (builds a relocated copy in a sandbox, with the original web checkout denied):
`python3 tools/check-independence.py --deny-path ../fb`. Run it only when a change touches dependencies or resources,
build tooling (`tools/*.sh`, the Xcode project), bundle contents, or network access, and at milestone acceptance;
ordinary UI work is verified with `just lint`, `just test`, and `just app-build`.

## Architecture

SwiftPM targets (`Package.swift`):

- `CLibraryPlatform`: C shims for POSIX primitives (flock and descriptor handling, spawn).
- `LibraryCore`: the bounded blueprint codec (`BlueprintCodec`, `BoundedJSONParser`, `ZlibCodec`) and the library store
  (`NativeLibrary*`, `LibraryTransactions`, `LibraryMaintenance`, `LibraryPreviewCache`).
- `FactorioData`: verification of private asset releases (`AssetRelease`, `FactorioProfile`) and the strict prototype map
  for statistics (`PrototypeMap`), loaded only through a verified release, and the pure statistics calculator
  (`BlueprintStatisticsCalculator`).
- `PreviewRenderer`: runs the bundled fpsr planner (`Resources/planner.js`) in system JavaScriptCore, then paints with Core Graphics (`NativePainter`).
  Rendering happens in a supervised child process (`PreviewProcess`, `PreviewChild`). `LibraryPreviewService` connects it to library ownership.
- `LibraryApp`: the macOS app's SwiftUI scenes, views, and models. All interface code goes here; the Xcode target in
  `App/` only holds the `@main` entry point and bundle settings (`local.fb.library`, ad-hoc signed, no sandbox).
- Executables: `fb-native` (CLI), `preview-worker` (helper process), `preview-probe` (standalone render harness).
- `Tests/Support/*`: helper executables that tests launch as real processes for crash, interruption and worker-lifecycle scenarios.

Cross-cutting invariants (full contracts in `docs/contracts/`):

- **Preserve original bytes.** Each item is a pair of `.txt` (exact imported bytes) and `.json` (metadata v1, `sourceSha256`) files.
  Never normalize whitespace or line endings, and keep unknown blueprint fields and sparse book entry indices.
  Fixtures are marked `-text -diff` in `.gitattributes`. `OriginalSourceTests` checks their hashes.
- **Single owner.** A kernel flock on `.owner.lock` excludes competing app and CLI sessions. All operations are serialized on the library queue.
  Preview workers get no lease, descriptors or environment: they receive request bytes and only the owner publishes.
  Never force-unlock the lease or replace its inode.
- **Recoverable writes.** Mutations stage hashed intents under `operations/<uuid>/` before publishing.
  Only `staging-cleanup` removes uncommitted staging; refused operations are quarantined, never deleted.
  Deleted and replaced originals go to the Trash.
- **Derived cache only.** `cache/` holds previews keyed by `LibraryCacheIdentity` and `source-index.json` (source hash to kind);
  neither changes source metadata. Cleanup is scoped to known formats.
- **Independence.** Builds and runtime must not depend on the original web checkout, Node or game files.
  `planner.js` is generated: after changing `tools/planner-entry.ts` or the vendored fpsr, run `just planner-build` and commit the resource and metadata together.
  Record copied or adapted files in `tools/provenance.json`.
- **Private artwork.** Factorio assets live in the gitignored `private-assets/`. Never commit them or add them to package resources.

## Docs convention

Each feature has a guide in `docs/development/`, a contract in `docs/contracts/` when it defines storage formats, and evidence in `docs/validation/`.
When behavior changes, update the matching docs and `docs/Session-Notes.md`. `docs/README.md` is the documentation map.
