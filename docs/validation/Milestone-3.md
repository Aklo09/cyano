# Milestone 3 acceptance

Milestone 3 (the native macOS application) is **accepted**: the owner did the walkthrough below on their own library
and release on 2026-11-15, reported that everything works, and approved it.
Its exit condition, from the [milestone 3 plan](../planning/Milestone-3.md#scope), is that everyday workflows work
offline, including without renderer assets. The checks below ran on 2026-11-15 on the A18 tree (parent commit
`36cad92`). Per-subtask evidence is in the [app validation](App.md); the criteria are in the
[app spec](../specs/Native-App.md) and the [screen specs](../specs/Native-App-Screens.md). People using the app
start from the [user guide](../User-Guide.md).

## Checks

| Check | Result |
| --- | --- |
| `just build` | Pass |
| `just lint` | Strict swift-format lint reports no findings |
| `just test` | Four Swift test runs (33, 66, 81, and 33 tests) and 4 Python assembly tests pass, including the statistics parity tests, the private-map test, and the 15 app suites |
| `just statistics-test` | The retained JavaScript reference tests pass |
| `just tools-check` | 153 copied files, 42 planner inputs, 5 pinned development dependencies; the fpsr patch reproduces the vendored tree |
| `just planner-check`, `just planner-test`, `just assets-check` | Pass |
| `just app-build Release` | Pass |
| `python3 tools/check-independence.py --deny-path ../fb` | Relocated build, tests, executables, and Debug app build pass with the original checkout unreadable, networking denied, and no Node on PATH |
| `just app-smoke`, Release app, with and without assets | See the exit condition below |

## Exit condition: offline, with and without assets

`tools/smoke-app.py` ran the **Release** app (`--app` the Release product) under `sandbox-exec` with IP networking
denied and the original web checkout unreadable, on a scratch library built from committed fixtures, with fresh
preferences and a scratch trash. Captures and reports are in the ignored `.cache/smoke/`.

| Workflow | Without assets (`20261115-112502`) | With the private 2.1.24 release (`20261115-112152`) |
| --- | --- | --- |
| Launch offline, library selection, clean quit | Pass | Pass |
| Relaunch reopens the last library (LIB-11) | Pass | Pass |
| Preview and statistics say what they need (PRV-9, STA-4) | Pass | — (renders instead) |
| Copy String gives the exact bytes, CRLF included (EXP) | Pass | Pass |
| Import from Clipboard adds and selects the item (IMP) | Pass | Pass |
| Add Comment (COM) | Pass | Pass |
| New Folder, Move To, Move to Trash after confirmation (ORG) | Pass | Pass |
| Open a book's entries with ⌘↓ (BOOK) | Pass | Pass |
| Space opens a preview window; opening again reuses it (PRV-3, PRV-4) | Pass | Pass |
| Three uncached renders with at most one worker (decision 4) | Skipped | Pass (peak 1) |
| Background change keeps zoom, starts no render (PRV-8a) | Skipped | Pass |
| Rename and replace reach the open window (PRV-11) | Pass | Pass (new image) |
| Clearing the release reaches open windows (SET-6) | Skipped | Pass |
| Quit with windows open; they are not restored (PRV-13) | Pass | Pass |
| Closing the library closes its windows (LIFE-1) | Pass | Pass |
| After quit: no worker, owner idle (LIFE-2) | Pass | Pass |
| `fb-native list` agrees: imported, moved, renamed, deleted; originals in the scratch trash | Pass | Pass |
| Total | 25 pass, 3 skipped | 27 of 27 pass |

## Acceptance criteria

The app spec has 115 criteria. 96 name themselves in a test (`@Test("BRW-10: …")`); the others are covered as listed.

| Area | Criteria | Named in tests | Other evidence |
| --- | --- | --- | --- |
| General (GEN) | 10 | GEN-5 (`LibraryBrowserModelTests`) | GEN-1, GEN-2: the smoke runs above. GEN-3, GEN-3b: `LibraryMessageTests` (every error code, `LIBRARY_LIMIT` names `staging-cleanup`). GEN-3a: `PreviewCenterTests` (cancelled renders show no error). GEN-4: the core suites' original, metadata, and comment preservation. GEN-6, GEN-7: `LibraryNameTests`. GEN-8: `LibraryFinderMetadataTests` |
| Library selection (LIB) | 11 | All (`LibrarySelectionModelTests`) | |
| Recovery (REC) | 6 | 4, including REC-1a added in A18 | REC-1, REC-5: `LibrarySessionTests` ("Opening reports a completed interrupted change once; a failed change blocks the session until Recover") |
| Browsing (BRW) | 10 | 9 | BRW-9 (cached row thumbnails) dropped by the owner on 2026-11-15 |
| Books and planners (BOOK) | 9 | 8 | BOOK-7: `OrganizeActionsTests` (entries are never organizable) |
| Import (IMP) | 12 | All (`ImportModelTests`) | |
| Export (EXP) | 6 | All (`ExportActionsTests`) | |
| Comments (COM) | 7 | All (`LibraryCommentsTests`) | |
| Organization (ORG) | 13 | All (`OrganizeActionsTests`) | |
| Previews (PRV) | 14 | 9 (`PreviewCenterTests`) | PRV-1, PRV-3, PRV-4, PRV-8a, PRV-13: the smoke runs |
| Statistics (STA) | 6 | All | STA-2 parity with `fb-native statistics` needs the private release and ran in `just test` |
| Settings and assets (SET) | 7 | All | |
| Menus and lifecycle (LIFE) | 4 | 3 (`LifecycleTests`) | LIFE-4: the A15 menu-bar check, re-diffed in A17 |

Accessibility (A16): the screen specs' keyboard walkthrough, labels, announcements, and contrast in dark, light, and
Increase Contrast are recorded in the [app validation](App.md#accessibility-2026-11-15); VoiceOver itself was not run
(owner's choice), and the labels were read through the accessibility API.

## Decisions

The seven milestone decisions hold: one package UI target with a thin Xcode app target; no App Sandbox; one library
per app with preview windows for comparison; on-demand previews, one render at a time (the smoke run's worker peak);
statistics with item names as text; Recover as the only in-app maintenance; session tests, scripted smoke runs with
captures, and an owner walkthrough instead of XCUITest. Decision 4's cached row thumbnails were dropped with BRW-9.

## Deferred and open

- **Out of scope (plan):** thumbnail grids and scheduling (milestone 4), copying or saving a preview image (later
  milestone), rich-text icons in names (milestone 4), installation and workload qualification (milestone 5).
- **Changed during milestone 3 (owner decisions):** the asset profile moved to Factorio 2.1.24; previews draw inserter
  pickup and drop markers; View ▸ Sort By and the A16 focus rules were added to the screen specs; BRW-9 was dropped.
- **Watched:** LIFE-2 failed once in 15 full `just test` runs (its worker never started within 30 s, only alongside
  the other suites); its message now reports the preview state.
- **Not checked:** Full Keyboard Access turned off; focus after deleting the last comment falls back to the window;
  after a keyboard-confirmed item deletion a second ⌘⌫ may target the newly selected first row (behind the
  confirmation).

## Owner walkthrough

Done by the owner on 2026-11-15 on their own library and asset release; the owner reported that every step works and
approved the milestone. The steps were:

| # | Step | Result |
| --- | --- | --- |
| 1 | Launch: the last library reopens | Works |
| 2 | Browse: open a folder and a book (⌘↓ or double-click), ⌘↑ back, search with ⌘F | Works |
| 3 | Select a blueprint: the preview renders; the Statistics tab (⌘1) fills in | Works |
| 4 | Open two or three items in preview windows (⌘Y or Space); compare, zoom (⌘+, ⌘9), change the background | Works |
| 5 | In a scratch folder: import a string from the clipboard (⇧⌘V, ⌘↩), then Copy String (⌘C) it back | Works |
| 6 | Add a comment (⌥⌘K, ⌘↩), then delete it | Works |
| 7 | In the scratch folder: new folder, rename, move, Move to Trash | Works |
| 8 | Settings (⌘,) shows the release as verified | Works |
| 9 | Optional: turn Wi-Fi off and repeat steps 2–4 | Reported with the rest; the owner did not say whether it was done separately |
| 10 | Quit and relaunch | Works |
