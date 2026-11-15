# Resume native implementation

The owner approved the [native plan](planning/macOS-Plan.md) on 2026-11-13.
Milestone 1 is [accepted](validation/Milestone-1.md): all criteria re-verified on `8daa40e` and the representative
images approved by the owner. The approved [core revisions](planning/Core-Revisions.md) that followed are implemented.
Milestone 2 is [accepted](validation/Milestone-2.md), including native construction statistics approved by the owner.
Milestone 3, the native macOS app, is [accepted](validation/Milestone-3.md) after the owner's walkthrough (2026-11-15).
Milestone 4, rendering integration, is [approved](planning/Milestone-4.md) (2026-11-15).

## Current state

- **Build native targets:** shared libraries, the CLI, the preview worker, and the planner probe compile.
- **Preserve supplied fixtures:** all nine TXT inputs retain their original hashes.
- **Decode native strings:** bounded parsing preserves unknown fields and exact original exports.
- **Own native libraries:** permanent kernel leases exclude competing app/CLI sessions.
- **Publish recoverably:** intents commit behind a drive barrier; replay rolls forward; refused operations can be
  quarantined; uncommitted staging can be cleaned up.
- **Organize sources:** folder/item moves and renames, empty-folder and item deletion, replacement, unpacking, and
  comment deletion are available. Deleted and replaced originals go to the Trash.
- **List quickly:** listing reads metadata and source hashes with a derived kind index; ID lookups use an
  in-session index. 888 roots list in 0.24 s in a release build.
- **Maintain offline:** bounded usage, scoped cache cleanup, and independent asset-release verification are available.
- **Paint previews:** JavaScriptCore runs the bundled fpsr planner; Core Graphics paints and Image I/O encodes PNGs.
- **Supervise helpers:** workers get only stdin/stdout/stderr and an empty environment, never the lease; deadlines,
  cancellation, memory limits, and parent-death lifelines are tested. Rendering runs off the library queue.
- **Reuse derived previews:** cache metadata binds identities, PNG bytes, and reports without changing source metadata.
- **Calculate statistics:** construction requirements and game-tile footprints for one blueprint entry, from a
  strictly loaded prototype map bound to a verified release; 0 differences from the reference on 348 cases.
- **Keep tooling local:** preparation sources, dependency locks, and notices live here.
- **Keep artwork private:** copied sprites, prototype data, and outputs derived from them stay in ignored directories.

The CLI includes all original library command capabilities except deliberately excluded backup/restore.
Native cache identities differ from historical web caches; unknown formats are protected by scoped cleanup.
The macOS app covers milestone 3's workflows offline, with and without assets (see the [user guide](User-Guide.md)).

## Next implementation

Milestone 3, the native macOS application, is [approved](planning/Milestone-3.md) (2026-11-14) with its seven
decisions settled: a package UI target with a thin Xcode app target, no App Sandbox, one library per app with
preview windows for side-by-side comparison, on-demand previews rendered one at a time, a statistics panel with
names as text, Recover as the only in-app maintenance, and session tests plus scripted screenshots instead of
XCUITest.

A1, the [native app spec](specs/Native-App.md), is approved (2026-11-14). A0, the two LibraryCore gaps found in
its review, is done: collision keys now match APFS case-insensitive equivalence on every volume (tested on an
attached case-sensitive image too), and regular `.DS_Store` files are ignored throughout libraries (see the
[storage contract](contracts/Storage.md)). A2, the [screen specs](specs/Native-App-Screens.md), is approved
(2026-11-14): books browse like folders, the inspector keeps the preview above Statistics/Details/Comments tabs, and
dark mode uses a darker content background (`#121212`). A3, the [app scaffold](development/App.md), is done:
`Sources/LibraryApp` holds the interface, `App/` the thin Xcode target (`local.fb.library`, ad-hoc signed, no
sandbox), `just app-build`/`just app-run` build through `tools/xcode.sh`, and the independence check builds and
launches the app offline. A4 is done: `LibrarySession` runs library calls on a serial worker, publishes listing
snapshots, handles recovery states, and `LibraryMessage` words every error; `just app-test` runs its suites (also in
`just test`). A5 is done: `LibrarySelectionModel` drives the selection and library windows, recents, and reopening at
launch; scripted launches must pass `-FBNativeDefaultsSuite <name>` (see the [app guide](development/App.md)).
A6 is done: `LibraryBrowserModel` drives the sidebar, path bar, item list, filter, and empty and issue states.
Verification rule (owner, 2026-11-14): UI subtasks use `just lint`, `just test`, and `just app-build`; the
independence check runs only for dependency, tooling, bundle, or network changes and at acceptance, and its app launch
moves to the A17 smoke runs. The terminal now has Screen Recording and Accessibility access, so real-window captures
(`screencapture -l`) and scripted UI actions (System Events) work for checks and A17; always launch with
`-FBNativeDefaultsSuite`. A7 is done: books open like folders by stored index, with versions, descriptions, and planner settings in the inspector.
A8 is done: Import (paste, TXT files, drag and drop; one book or
unpacked) keeps exact bytes and selects the result. A9 is done: Copy String and Save As TXT
for items and book entries, refusing destinations inside the library. Capture only app windows
(`screencapture -l<window>`), never the whole screen. A10 is done: the inspector has Statistics (placeholder until A13),
Details, and Comments tabs; comments are added and deleted per item or entry. A11 is done: new folder, rename,
move (sheet and drag), delete with confirmation, replace source. A14 is done: Settings (⌘,) verifies and remembers the
asset release, re-verifies it at launch, and loads the prototype map once. A12 is done: `PreviewCenter` serves cache
hits and empty blueprints without a worker, renders one at a time in request order off the library worker, shares a
render between the inspector and windows, and cancels a render only when no viewer wants it; preview windows
(⌘Y, Space) zoom, pan, and change background; the app embeds `preview-worker` in `Contents/MacOS` (see the
[app guide](development/App.md#previews)). Verified with `just lint`, `just test`, `just app-build`, the independence
check, and a smoke run of a relocated app copy with the build's `PackageFrameworks` moved aside (a real uncached
render in the inspector, nothing to draw, a planner window from ⌘Y with View-menu zoom, and after quit no worker and an
idle owner; see [validation](validation/App.md#previews-2026-11-14)). The real-app checks deferred from A12 (Space in
the list, windows closing with the library, rename or replace with a window open, a release change, one worker at
most) are in the A17 smoke run. A13 is done: the Statistics tab shows counts,
footprint, item groups, and worded warnings from `StatisticsModel`/`StatisticsPresentation`; STA-2 parity with
`fb-native statistics` for the seven approved blueprints is a test that needs the private release (see the
[app guide](development/App.md#statistics)). In short windows the inspector now caps its header and preview so the
tabs keep room. A real-app run checked the tab at minimum window size, a nested book entry, a book, a planner, and
⌘C (see [validation](validation/App.md#statistics-2026-11-14)). Scripted runs while the owner uses the Mac: launch
with `open -g`, use accessibility actions and `screencapture -l` only, and send no keystrokes or clicks without the
owner's go-ahead. A15 is done in code and tests: quitting closes the library synchronously (a change in progress
finishes, renders are cancelled and workers reaped, the reopen path is kept), closing the library cancels its render,
the Edit menu holds Rename… and Move to Trash/Delete Folder, Library adds Recover, and selection commands work only
while the library window is key (see the [app guide](development/App.md#library-selection-and-windows)). A
real-app run checked the menu bar against the spec, quitting during a render, the relaunch, and closing the main
window with a preview window open (see [validation](validation/App.md#menus-and-lifecycle-2026-11-14)). A16 is done
(2026-11-15): a scripted keyboard walkthrough of the screen specs' flow, an accessibility-tree audit (labels and
announcements; VoiceOver itself not run, by the owner's choice), and contrast measured in dark, light, and Increase
Contrast. Fixed: Tab into the item list now shows a selected row (it reached the list invisibly), opening a book keeps
focus in the list, the comment field no longer traps Shift-Tab and Escape returns to the list, View ▸ Sort By gives the
column headers a keyboard path, unlabeled comments and sheet controls, two `.secondary` texts below 4.5:1, and the
Window menu listing the app twice (see the [app guide](development/App.md#accessibility) and
[validation](validation/App.md#accessibility-2026-11-15)). One full `just test` run failed LIFE-2 once (its worker never
started within 30 s); alone and in a second full run it passed. A17 is done (2026-11-15): `just app-smoke` runs a
scripted smoke run of a scratch app copy offline on a scratch library (launch, reopen, preview windows, at most one
worker, rename and replace with a window open, release change, close and quit), with captures and a report in
`.cache/smoke/`; the independence check no longer launches the app (see the [app guide](development/App.md#smoke-run)
and [validation](validation/App.md#tests-and-smoke-runs-2026-11-15)). PRV-11's intermittent failure was a test race (it
finished a fake render before it had started) and is fixed; LIFE-2 failed once in 15 full runs and now reports the
viewer state. Test cleanups no longer leave `local.fb.library.tests-*.plist` files in `~/Library/Preferences`. A18 (2026-11-15): the [user guide](User-Guide.md), the
[milestone 3 acceptance record](validation/Milestone-3.md) with every check and the offline Release smoke runs (27 of
27 with assets; 25 and 3 skipped without), REC-1a's test, the smoke run's everyday-workflow checks, and BRW-9 dropped
by the owner. The owner did the walkthrough and accepted milestone 3
on 2026-11-15. Next: milestone 4 (see the [native plan](planning/macOS-Plan.md#delivery-roadmap)).
Cached row thumbnails (BRW-9) were dropped by the owner (2026-11-15).
Alt-mode previews now mark each inserter's pickup (yellow line) and drop (yellow arrow) (2026-11-15). This needed
new render-database fields, so the private assets were regenerated from Factorio 2.1.24 and the supported asset
profile moved from 2.1.23 to 2.1.24 (owner's decision: replace, not both). Releases assembled from 2.1.23 inputs are
now refused: reassemble any everyday release from `private-assets/2.1.24` and `private-assets/statistics-reference`
(see the [asset preparation guide](development/Asset-Preparation.md#regenerate) and
[validation](validation/Renderer.md#inserter-indications-2026-11-15)).
Local fpsr changes are kept as ordered patches in `tools/vendor/fpsr-patches/` against the pristine baseline in
`BASE`; `just tools-check` fails if they drift from `tools/vendor/fpsr`. Patch and upgrade steps are in the
[asset preparation guide](development/Asset-Preparation.md#local-fpsr-patches).
Asset-release verification still counts a `.DS_Store` as an unexpected member; that is outside A0 and unscheduled.
Copying or saving preview images is assigned to milestone 4 (R9).


Milestone 4 is [approved](planning/Milestone-4.md) (2026-11-15) with all decisions settled by the owner: no
thumbnails (visible-item scheduling and bounded queues dropped from the roadmap), entry icons in list rows (a line
before the name, after the kind symbol) and as the game's 2 × 2 arrangement in the inspector, rich-text tags shown as
icons and kept as written when no icon exists, tags kept in filenames for new imports (storage contract change), planet
icons added to the private release by regenerating `private-assets/2.1.24` (profile unchanged), icons read by the app
at runtime from the release and never embedded, render warnings shown, image copy/save, the 239-leaf corpus reviewed
from contact sheets, and a `just test` check that no Factorio artwork reaches git, package resources, or the app
bundle. Milestone 4 verification (owner, 2026-11-15): focused suites per subtask plus `just lint` and `just app-build`, full
`just test` at the end (see the [plan](planning/Milestone-4.md#verification)). R0 is done (2026-11-15): the [app spec](specs/Native-App.md) and [screen specs](specs/Native-App-Screens.md) gained
ICN-1–ICN-11, WRN-1–WRN-3, IMG-1–IMG-6, and GEN-9. The owner also revised decision 3 (a tagged label goes into
`displayNameOverride`; file names unchanged) and added decision 9 (text form in titles, file names, sorting) and
decision 10 (root entry icons in the derived source index, schema 2). R3 is done (2026-11-15): patch
`0002-planet-icons.patch` exports planet icons as `space-location/<planet>`; `private-assets/2.1.24` was regenerated
(the previous copy is kept as `private-assets/2.1.24-before-planets`) with the same profile, and renders are
pixel-identical (see [validation](validation/Renderer.md#planet-icons-2026-11-15)). The owner's everyday release must
be reassembled to get the icons; their script needs no version change. R1 is done (2026-11-15): `just qualify-corpus`
(`tools/qualify-corpus.py`) renders the 239-leaf corpus into `.cache/qualification/<time>/` with `report.json` and an
`index.html` contact sheet; the first run rendered every leaf with one known warning (see
[validation](validation/Renderer.md#corpus-run-2026-11-15)). R4 is done (2026-11-15): `IconCatalog`
reads icons from the verified release and `AssetSettings.iconCatalog()` loads it once per release (see the
[app guide](development/App.md#icons)). The owner reviewed the corpus contact sheet and found no defects
(2026-11-15), so R2 is done with no corrections. R5 is done (2026-11-15; real-app check in
[validation](validation/App.md#entry-icons-2026-11-15)): the source
index is schema 2 with root entry icons, rows show the kind symbol then the icons, and the inspector shows the
game's icon tile (see the [app guide](development/App.md#icons)). Next: R6 and R7.

Keep application scheduling/progress/retry and UI work separate from the completed library commands.
Preserve sticky cancellation, worker isolation, and owner-only cache publication.
Connected-rail/full-corpus review (milestone 4), the 1,000-root workload targets, and power-loss qualification
remain outstanding.

Preserve the [storage contract](contracts/Storage.md) and [statistics contract](contracts/Statistics.md).
Retain original bytes, sparse entry indices, and unknown blueprint fields.
Application-managed backup and restore remain outside v1.
Neither builds nor runtime should depend on the original web checkout.
Strict conformance with the original web application is not required: prefer better native behavior and record the
difference in the relevant contract.

Run `just --list` for available commands.
Use `just build`, `just lint`, and `just test` for native checks.
Use `just codec-test`, `just storage-test`, `just asset-test`, and `just renderer-test` for focused suites.
Use the [preview guide](development/Preview.md) and [library preview guide](development/Library-Previews.md) for rendering,
and the [statistics guide](development/Statistics.md) for statistics and their reference tooling.
