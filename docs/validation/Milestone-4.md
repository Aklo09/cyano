# Milestone 4 acceptance

Milestone 4 (rendering integration) is **ready for the owner's acceptance**: every subtask is done and every check
below passed on commit `fa8d7f8` (2026-11-15). The owner's walkthrough and approval are pending.

Its exit condition, from the [milestone 4 plan](../planning/Milestone-4.md#scope), is that the full supplied corpus
receives native rendering and visual qualification. Per-subtask evidence is in the [renderer validation](Renderer.md)
(R1 to R3) and the [app validation](App.md) (R5 to R10); the criteria are in the [app spec](../specs/Native-App.md) and
the [screen specs](../specs/Native-App-Screens.md). People using the app start from the [user guide](../User-Guide.md).

## Checks

| Check | Result |
| --- | --- |
| `just build` | Pass |
| `just lint` | Strict swift-format lint reports no findings |
| `just test` | Four Swift test runs (43, 69, 98, and 33 tests, none skipped, including the private-release statistics parity, icon, and planet tests), 4 Python asset-release tests, and the artwork check: its self-test finds planted copies by name and by bytes, and 405 files (Git-tracked files, package resources, the Debug and Release app bundles) hold no release data |
| `just statistics-test` | 13 of 13 JavaScript reference tests pass |
| `just tools-check` | 153 copied files, 42 planner inputs, 5 pinned development dependencies; the base fpsr tree plus 2 patches reproduces the vendored tree |
| `just planner-check`, `just planner-test`, `just assets-check` | Pass |
| `just app-build Release` | Pass, no warnings |
| `python3 tools/check-independence.py --deny-path ../fb` | Relocated build, tests, executables, and app build pass with the original checkout unreadable, networking denied, and no Node on PATH; the build from scratch has no warnings |
| `just app-smoke`, Release app, with and without assets | 31 of 31 with assets (`20261115-175916`); 27 pass and 5 skipped for needing a release without (`20261115-180307`) |

## Exit condition: the full corpus, rendered and reviewed

| Evidence | Result |
| --- | --- |
| Corpus (decision 1) | 239 leaves: 198 from the nine supplied fixtures (185 blueprints, 12 upgrade planners, 1 deconstruction planner) and 41 from the vendored fpsr visual tests, including every rail kind |
| Native rendering (R1) | `just qualify-corpus`, release build: 239 of 239 rendered, 0 failed; one warning, the modded `ee-infinity-loader`; median 1.8 s, maximum 5.0 s; peak memory at most 362 MiB ([corpus run](Renderer.md#corpus-run-2026-11-15)) |
| Visual qualification (decision 2) | The owner reviewed the contact sheet, rail leaves included, and found no defects (2026-11-15); R2 needed no corrections |
| Planet icons (R3) | The release gained the five planet icons; renders before and after are pixel-identical ([validation](Renderer.md#planet-icons-2026-11-15)) |

## Acceptance criteria added in milestone 4

The [R0 amendments](../planning/Milestone-4.md#subtasks) added 22 criteria; 19 name themselves in a test.

| Criteria | Named in tests | Other evidence |
| --- | --- | --- |
| GEN-9 (no artwork in Git, resources, or the app) | — | `tools/check-artwork.py` and its self-test in `just test` |
| ICN-1 to ICN-3 (entry icons) | `EntryIconTests`, `NativeLibraryTests` (source index schema 2) | Smoke run: row labels name their icons; real-app captures |
| ICN-4, ICN-6, ICN-9 | `IconCatalogTests` (ICN-9: every item and quality of the private map has an icon), `RichTextNameTests` | Captures of Statistics icons |
| ICN-5, ICN-7 (tags as icons, text forms) | `RichTextNameTests` | Smoke run: `bp.txt`'s tag read by icon name with a release, as text without |
| ICN-8 (tagged labels kept as names) | `NativeLibraryTests` | Smoke run: `bp.txt` imported with its tagged label |
| ICN-10 (release change) | `AssetSettingsTests` | |
| ICN-11 (planets) | — | `PrivateIconCatalogTests` (all five planets decode from the release); [R3 validation](Renderer.md#planet-icons-2026-11-15) |
| WRN-1 to WRN-3 | `PreviewCenterTests` | Smoke run: "1 warning", its popover lists the modded entity |
| WRN-2a (keyboard path) | — | View ▸ Show Render Warnings and the button's place in the focus order; not exercised by keyboard in a scripted run, so part of the owner's walkthrough |
| IMG-1 to IMG-6 | `PreviewImageExportTests`, `PreviewCenterTests` | Smoke run: ⌥⌘C gives exactly the cached PNG |

## Decisions and changes during the milestone

- **Settled by the owner:** no thumbnails; entry icons in rows and the inspector; rich-text tags as icons, kept as
  written without one; planet icons in the release; tagged labels kept in `displayNameOverride`; text forms where icons
  cannot be drawn; root entry icons in the source index (schema 2); render warnings in the planner's words; copying
  and saving preview images; focused tests per subtask with the full suite at the end
  ([plan](../planning/Milestone-4.md#decisions)).
- **Owner's review of the app (2026-11-15):** larger row icons (24 points, with the kind symbol in the same square
  and one row height), a 64-point inspector tile with 28-point title icons, and an inspector header that shows all its
  lines ([app validation](App.md#milestone-4-smoke-runs-2026-11-15)).
- **Defects found and fixed:** rows with tag icons were taller than others (fixed and confirmed in the acceptance
  captures); 5 compiler warnings (a missing import, and the `Text` `+` deprecated in macOS 26). The first Release
  acceptance runs crashed when the Comments tab opened: the larger header let the inspector need more height than the
  window, and AppKit looped on window constraints until it raised an exception. The preview now gives way to the
  header, a fixed reserve keeps the tabs usable, and the inspector reports no minimum height (`fa8d7f8`); the old
  build showed the overflow, the fixed one fits, and both acceptance runs then passed with no crash report.

## Outside this milestone

- **Milestone 5:** the 1,000-root and 149-leaf workload targets, installation, and power-loss qualification.
- **Unscheduled:** asset-release verification counting `.DS_Store` as an unexpected member.
- **Observed, not changed:** right after selecting a large uncached entry, the preview area can show an empty
  checkerboard for a few seconds while the cache is checked; the Waiting and Rendering states appear once a render
  is queued.

## Owner approval

Pending: the owner's walkthrough on their own library and release.
