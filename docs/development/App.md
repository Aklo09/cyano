# Native macOS app

Build and run the Factorio Blueprint Library app from this repository.
Behavior is specified in the [app spec](../specs/Native-App.md) and the [screen specs](../specs/Native-App-Screens.md);
the delivery plan is [milestone 3](../planning/Milestone-3.md).

## Structure

| Part | Location | Contents |
| --- | --- | --- |
| Interface and logic | `Sources/LibraryApp` (SwiftPM target and product `LibraryApp`) | Scenes, views, and their models; builds and tests with SwiftPM like the other targets |
| App bundle | `App/FactorioBlueprintLibrary.xcodeproj`, `App/Sources` | One app target whose only source is the `@main` entry point, linking the local package product `LibraryApp` |
| Build wrapper | `tools/xcode.sh` | Runs `xcodebuild` for the shared scheme with derived data and package caches under `.cache/` |

Put new interface code in `Sources/LibraryApp`, not in `App/Sources`, so it stays testable under `just test`.
The Xcode project holds only bundle settings: change them in Xcode or in `project.pbxproj`, and keep the shared
scheme `FactorioBlueprintLibrary` committed.

## Library session

`LibrarySession` (main actor, `@Observable`) owns the open library for every window. It runs each library call on
one serial worker queue off the main thread, in submission order, because `NativeLibrary` methods block.

- **Lifecycle:** `open(_:create:)`, `close()`, and `retryOpen()` run one after another; opening another library
  closes the current one and releases its ownership first (LIB-9).
- **State:** `phase` is closed, opening, open, open failed (with a message), or recovery required. Recovery
  required is chosen when a failed open leaves committed operations pending, whatever the error code. It lists them
  with a quarantine command for the CLI (REC-2).
- **Data:** `listing` holds the latest successful listing and `revision` increases with each one. Every change made
  through `perform(_:refreshing:_:)` refreshes it, so windows observe one snapshot instead of change events. A
  failed refresh keeps the previous listing and sets `listingFailure`.
- **Recovery:** `completedNotice` reports interrupted changes that opening completed (REC-1);
  `requiresRecovery` and `recover()` handle a change that failed mid-session (REC-5).
- **Late results:** every open and close starts a new generation; results from an earlier one return `.ignored`.

`close()` with no library open leaves a failed open's state visible; `reset()` (Back) dismisses it.

`LibraryMessage.describing(_:activity:libraryName:)` turns any error into a title, guidance, and Details (code and
technical text), worded for what the app was doing; it returns nil for renders the owner cancelled.
`LibraryMessage.listingIssue(code:)` words listing issues.

## Browsing

`LibraryBrowserModel` derives everything the library window shows from the session's listing:

- **Location:** the current folder ("" is the library root), kept valid when the listing changes (a removed folder
  falls back to its nearest existing ancestor) and reset to the root for a newly opened library.
- **Rows:** subfolders first by name, then the folder's items sorted by name, kind, updated date, or size. The
  filter matches item names in every folder, ignoring case and accents, and adds each result's folder.
- **States:** `content` is loading, rows, library empty, folder empty, no matches, or too large to list (a failed
  first listing never shows a partial list).
- **Sidebar and path bar:** `folderTree` and `pathComponents`; listing issues are worded with
  `LibraryMessage.listingIssue(code:)`.

**Books** open like folders (double-click or ⌘↓). `book` holds the saved item and the stored indices of the book
shown; its entries come from one `NativeLibrary.entry(id:entryPath:)` call and are listed in stored order with their
stored index, in a table with #, Name, and Kind and no sorting. The path bar continues through the book and nested
books, and ⌘↑ goes back one level, selecting the entry just left. A moved book stays open in its new folder, a
replaced source reopens at the root book, and a deleted item closes the book. `BlueprintEntryReader` reads children,
names (rich-text tags such as `[item=iron-plate]` removed, as item names are), packed versions (`major.minor.patch`),
and planner settings as text; `selectedDetail` feeds the inspector.

**Import** (toolbar, ⇧⌘I, ⇧⌘V or ⌘V in the item list, the empty states, or dropping files on the list or a sidebar
folder) opens `ImportModel` in a sheet. Pasted text is saved as its exact UTF-8 bytes; files are read with
`NativeLibrary.readSourceFile(at:)`, so their bytes, line endings, and whitespace are kept. Each source is decoded off
the main thread first, which names the kind or the problem before saving and refuses unpacking non-books. Several
files import one by one; failures are listed in a summary while the others stay imported. The destination defaults to
the current folder, or the open book's folder; afterwards the new items, or the unpacked top folder, are selected.

**Export** acts on `exportTarget`: the selected item's root, or the selected entry in an open book. Copy String
(⌘C in the item list, the row menu, or the inspector) puts the exact exported bytes on the clipboard; Save As TXT
(⇧⌘E) uses a save panel. A destination inside the library is refused before anything changes, and the panel
reopens; a file the panel agreed to replace goes to the Trash first (honoring `FB_NATIVE_TRASH_DIRECTORY`) and comes
back if the write fails. Both show a two-second confirmation at the bottom of the window, also announced to
VoiceOver.

**Inspector and comments.** The inspector shows a header (name, kind, version, position or dates and size, export
buttons) and Statistics, Details, and Comments tabs (⌘1–⌘3). `commentScope` is the selected item's root, the selected
entry in an open book, or the open book itself; its comments come from the listing, oldest first. Drafts are kept per
scope, so text typed for one item never goes to another. Add Comment (⌥⌘K, then ⌘↩) refuses empty, whitespace-only,
and over-64 KB text and keeps it; deleting asks first. The Statistics tab is described under Statistics.

**Organization** acts on `organizableSelection`: saved items and folders, never entries inside a book. New Folder
(⇧⌘N) creates the next free "New Folder" name and starts renaming it; Return renames the selected row in place
(Return commits, Esc cancels, a refused name keeps the field open with the reason). Move To (⌃⌘M) offers only valid
targets; rows can also be dragged onto a sidebar folder, where TXT files instead open Import. Move to Trash (⌘⌫ as a
menu shortcut that keeps its text meaning in text fields) asks first; a non-empty folder is explained instead.
Replace Source reports comments moved to the root. Originals the Trash refused are reported as kept in
`operations-quarantine/`. SwiftUI clears an alert's presented value before its button runs, so the delete alert
passes its value to `confirmDelete(_:)`.

**Settings** (⌘,) holds the asset release. `AssetSettings` verifies a chosen folder off the main thread with
`AssetRelease.verify` and makes it active only if it verifies and does not overlap the open library; a refused folder
keeps the previous release. The path is saved in the app's preferences (`assetReleasePath`) and re-verified when the
app starts, so a missing or changed release shows its problem while everything else works. `availability(for:)`
gives previews and statistics the release or the reason there is none, and `prototypeMap()` loads the map once per
release. `revision` increases whenever the active release changes.
Choose an assembled release (a folder with `release.json`, `sprites/`, and `statistics/prototype-map.json`), such as
`.cache/renderer-assets` from the [preview guide](Preview.md#prepare-a-private-release); the raw
`private-assets/2.1.24` folder is refused. For everyday use, assemble a copy outside the repository's `.cache/`.

Rows show their kind symbol; no row ever starts a render. Cached row thumbnails (BRW-9) were dropped by the owner in
A18.

## Statistics

`StatisticsModel` (owned by `LibrarySelectionModel` as `statistics`) fills the Statistics tab (STA-1 to STA-6). The
tab calls `show(_:)` with `LibraryBrowserModel.statisticsTarget` (the inspector's scope: a root item, the selected
book entry, or the open book itself, with its kind and source hash) whenever the target or `AssetSettings.revision`
changes. Books and planners are not applicable without touching the release. Then the release state decides: none
asks for one (STA-4), a checking release shows nothing until its revision changes, a problem or a library overlap
says the release can't be used, and only a `prototypeMap()` failure after that is "can't provide statistics"
(STA-6). The map loads once per release (SET-5); the calculation itself (`NativeLibrary.statistics`, the same call
as `fb-native statistics`) runs through the library worker, because it takes milliseconds. A later request drops
an earlier result.

`StatisticsPresentation` turns a result into what the tab shows: entity and tile counts, the footprint (complete,
incomplete with the known bounds as "at least", or incomplete with none), whether requirements are complete, the
non-empty groups (Construction items, Placement, Modules, Equipment, Other inserted, and Equipment requests, noted as
not included in the total), and warnings worded from their codes with the entity, item, tile, or quality named and
the incomplete part stated (STA-3). Counts stay integers and sizes stay numbers, so the view formats them for the
Mac's locale and tests compare values. Selected rows copy as tab-separated text with ⌘C (`copyText(rows:)`).

`StatisticsParityAppTests` checks STA-2: for the seven approved blueprints it compares the presentation with
`fb-native statistics` output for the private release in `.cache/renderer-assets`, and is skipped without it.

In short windows the inspector caps its header and the preview at a quarter of its height each (header 80–260 pt,
preview 100–200 pt), so the tabs keep room at the 500 pt minimum window height.

## Previews

`PreviewCenter` (owned by `LibrarySelectionModel` as `previews`) schedules previews for the inspector and preview
windows (PRV-1 to PRV-12). Each preview area owns a `PreviewDisplay`, whose `PreviewViewer` it passes to
`show(_:in:)` whenever the `PreviewSubject` (library path, item ID, stored entry path), the item's source hash, or
`AssetSettings.revision` changes, and to `release(_:)` when it goes away.

- **Lookup first:** a cache-only lookup (`LibraryPreviewService.cached`) uses the identity `AssetSettings` already
  verified, so a hit neither re-verifies the release (about 0.5 s for the private release) nor waits for a running
  render (PRV-2). A miss decodes the entry: a blueprint without entities and tiles is "nothing to draw" and starts no
  worker (PRV-12; the renderer itself would paint a blank 64×64 image). A cached image with no drawing commands is
  checked the same way, in case the CLI cached an empty blueprint.
- **One render at a time:** misses queue in request order; one render runs at a time on its own serial queue
  (`LibrarySession.previewCall`), never on the library worker, so library calls proceed and `close()` cancels the
  render through the library (PRV-5). Viewers asking for an entry that is waiting or rendering join that job (PRV-7).
  Leaving drops a waiting viewer; a render is cancelled, through its own `PreviewCancellation`, only when no viewer
  still wants it (PRV-6).
- **Results:** a missing item or entry is the deleted state (PRV-11); `SOURCE_CHANGED` and a cancellation with
  viewers left (a release change) ask again; other failures show their `LibraryMessage` with Retry (PRV-10).
- **Backend seam:** `PreviewBackend` holds the lookup and render calls; tests use a gated fake that never starts a
  worker (`PreviewCenterTests`).
- **Images:** previews always use the default options (2x tier, transparent, at most 2048 pixels), so the cache key
  never depends on the view. The background (checkerboard, transparent, or a solid color from the color panel) is
  drawn by the view and not saved (PRV-8a). Two image pixels make one point at Actual Size (100%).
- **Zoom and pan:** `PreviewViewport` holds the math (tested in `PreviewViewportTests`): Fit is capped at 400% so tiny
  planner images stay sharp, zoom ranges from 5% to 1,600%, and resizing keeps the fit until the owner zooms or pans.
  `PreviewCanvasView` maps scroll and pinch (zoom around the pointer), drag (pan), double-click (Fit/Actual Size), and
  arrow keys (10% of the view, a screen with ⌥).
- **Windows:** `WindowGroup(id: "preview", for: PreviewSubject.self)`; opening a subject that already has a window
  brings it forward (PRV-4), and windows are not restored (PRV-13). The title follows renames; a window dismisses
  itself when its library closes or another one opens (LIFE-1). Open with Open in Window (inspector), ⌘Y, or Space in the list. The View
  menu acts on the focused preview: Zoom In/Out (⌘+/⌘−), Actual Size (⌘0), Zoom to Fit (⌘9), Background, Retry
  Preview (⌘R).
- **Worker:** the Xcode target embeds the package's `preview-worker` product with a Copy Files phase into
  `Contents/MacOS` (signed on copy); `PreviewBackend.bundledWorker` finds it with
  `Bundle.main.url(forAuxiliaryExecutable:)`. The worker target adds an `@executable_path/../Frameworks` rpath
  (`Package.swift`), because Xcode links it against the package frameworks the app embeds; without it, it would load
  them only through Xcode's absolute build-folder rpath. Its resource bundle is found through the app's
  `Contents/Resources`. A missing worker shows a failure that asks to reinstall the app.

The app registers `ApplePersistenceIgnoreState`: AppKit's saved application state is keyed by bundle identifier,
and after a quit with no windows open it made later launches, even with separate preferences, open no window.

## Icons

`IconCatalog` (`Sources/PreviewRenderer/IconCatalog.swift`, milestone 4 R4) reads Factorio icons at runtime from the
verified release, never from the bundle (spec GEN-9). `AssetSettings.iconCatalog()` loads it at most once per
release, off the main thread, like the prototype map, and drops it when the release changes or is cleared (ICN-10).

- **Loading:** `IconCatalog.load(release:)` verifies the release and reads the 2x tier's icon table from the render
  database (`<category>/<name>` to frame). A malformed table is refused. Fonts are not loaded.
- **Lookups:** `image(for:)` decodes the icon's atlas on first use (Image I/O, at most 32 MiB of atlases kept) and
  returns the icon at its logical size, 64 × 64 for game icons, with the trimmed frame at its offset; composed icons
  stay in memory (at most 2,048), never on disk. An unknown icon, or an atlas that changed after verification, gives
  nil, so callers show text (ICN-4, ICN-6). `qualityBadge(_:)` gives the badge for qualities other than normal.
- **References:** `IconReference(signalType:name:)` maps entry-icon signals (no type means `item`, `virtual` means
  `virtual-signal`); `IconReference(tagKind:name:)` maps rich-text tags (`planet` means `space-location`);
  `IconReference(imagePath:)` reads `[img=category/name]` and `[img=category.name]`.
- **Entry icons (R5):** `LibraryItem.entryIcons` (from the source index) and `BlueprintEntry.icons` reach
  `BrowserRow.icons` and `EntryDetail.icons`. `LibraryWindowView` loads the catalog whenever
  `AssetSettings.revision` changes and passes it down as the `iconCatalog` environment value. `EntryIconStrip`
  draws a row's kind symbol, then the icons at text height (16 points at the default size) with quality badges at
  half size in the bottom-left corner, leaving out icons the release lacks; `EntryIconTile` draws the inspector's
  48-point tile in the game's layout (`EntryIconLayout.frames`) or the kind symbol. Row VoiceOver labels end with
  "icons: …" (`EntryIconLayout.spokenNames`).
- **Names (R6):** `RichTextName` splits a name into text, icon tags (kinds the catalog maps, `planet`, and
  `img=category/name`), and other tags. `RichNameText` draws icon tags the release has as inline images at the text
  size (`IconCatalog.badgedImage` adds the quality badge) and leaves every other tag as written; it is used in rows,
  the sidebar, the path bar, and the inspector header. `textForm` (icon tags removed, other tags kept, icon names
  when nothing else is left) gives window titles, Save As names, the entry location line, and the name sort key
  (`BrowserRow.sortName`); `spoken(showing:)` gives VoiceOver labels. Entry names are the labels as stored.
- **Statistics (R7):** Statistics rows draw the item's icon before its name and the quality icon beside the
  quality, at text height; names stay the prototype names as text, so ⌘C and parity with `fb-native statistics`
  are unchanged. Without an icon the name stands alone.
- **Tests:** `IconCatalogTests` use a generated release with a PNG atlas; `PrivateIconCatalogTests` decode the real
  WebP atlases when `.cache/renderer-assets` exists, and `PrivateStatisticsIconTests` check that every item and
  quality in its prototype map has an icon; `EntryIconTests` cover rows, details, layout, and spoken names; `RichTextNameTests` cover tags, text forms,
  sorting, and file names.

## Library selection and windows

`LibrarySelectionModel` outlives both windows and decides which one shows through `windowGoal`:

- **Two windows:** the selection window (`library-selection`) and the library window (`library`). Each mirrors
  `windowGoal`, opening the other and dismissing itself, so a failed open from either window lands in selection
  with its message. Windows are never restored from a previous run.
- **Launch:** when the library open at the last quit is still reachable, only the library window is presented and
  it reopens that library (LIB-11); otherwise only selection. A failed reopen ends in selection.
- **Closing:** Close Library (⇧⌘W) or closing the library window releases the library and forgets it for the next
  launch; quitting keeps it. Closing cancels a render in progress and reaps its worker before ownership is released
  (LIFE-1), and preview windows of that library dismiss themselves.
- **Quitting:** on `willTerminateNotification`, `prepareForTermination()` calls `LibrarySession.closeForTermination()`,
  which closes the library synchronously on the main thread: a change already running on the library's queue
  finishes first (mutations check for closing only when they start), renders are cancelled and their workers
  reaped, and later calls are refused (LIFE-2, LIFE-3). The reopen path is kept for the next launch. An open or
  close still in flight is left to process exit, which also releases the lease; workers exit through their
  parent-death lifeline.
- **Menus:** every command is in the menu bar (LIFE-4). Edit holds Rename… and Move to Trash (Delete Folder when one
  folder is selected) after the pasteboard items, and Find; Library adds Recover, enabled while a failed change
  blocks the library. Commands on the selection are enabled only while the library window is key
  (`libraryWindowActive`, a focused scene value), so ⌘⌫ or Rename in a preview window or Settings never acts on a
  selection out of sight. `LifecycleTests` covers LIFE-1 to LIFE-3 with a real child process: a shell-script worker
  that records its ID and blocks.
- **Choosing folders:** Open Library on an empty (or `.DS_Store`-only) folder asks before creating a library there;
  New Library on a folder that already holds a library opens it.
- **Recents:** `RecentLibraryStore` keeps up to ten libraries, newest first, one entry per folder (standardized,
  symlinks resolved); folders that are missing or on an unmounted volume are marked unavailable.

### Preferences and scripted launches

Recents and the library to reopen live in the app's preferences (`local.fb.library`). Launch with
`-FBNativeDefaultsSuite <name>` to use a separate domain instead; every scripted launch must, so it never reads the
owner's recents or reopens their library, and should delete the domain afterwards
(`defaults delete <name>`). `just app-run` uses the owner's real preferences.

## Commands

```sh
just app-build            # Debug app
just app-build Release    # Release app
just app-run              # build the Debug app and open it
just app-test             # session and message tests (also part of just test)
```

The app is written to `.cache/xcode/Build/Products/<configuration>/Factorio Blueprint Library.app`.
Open `App/FactorioBlueprintLibrary.xcodeproj` in Xcode for SwiftUI previews and debugging; Xcode then uses its own
derived data location instead of `.cache/`.

`tools/xcode.sh` passes `-IDEPackageSupportDisableManifestSandbox=YES` and the Swift flag `-disable-sandbox`, the
Xcode counterparts of `tools/swift.sh --disable-sandbox`: neither Xcode's manifest sandbox nor the compiler's sandbox
for macro plugins (`@State`, `@Observable`) can run inside the `sandbox-exec` profile used by the independence check. If `xcodebuild` reports that a required plug-in failed to load, run
`sudo xcodebuild -runFirstLaunch` once to install Xcode's system components.

## Accessibility

Rules the views follow (screen specs, "Accessibility"; checks in the
[validation](../validation/App.md#accessibility-2026-11-15)):

- **Keyboard focus in the item list.** A SwiftUI `Table` draws no focus ring, so when focus arrives by anything but
  a mouse event, `ItemList` calls `itemListFocusedByKeyboard()` on the next turn (after the table has pushed its own
  selection back), which selects the first row when no shown row is selected. Do not test for `.keyDown`: by the time
  focus changes, the current event can already be the Tab's key-up (scripted input misses it about one time in ten).
  Opening a folder keeps the table and its focus; opening or leaving a book replaces the table after a loading
  state, so a `locationKey` change marks focus to restore, and the next table to appear takes it back only if focus
  went nowhere meanwhile. `requestListFocus()` moves focus to the list from elsewhere (Escape in the comment field).
- **Labels.** Form captions are not linked to their controls on macOS, so pickers and fields in forms and sheets get
  an explicit `accessibilityLabel`. Combining children drops selectable text (`.textSelection`), so rows with such
  text use `.ignore` and a label. Containers with an action (`Banner`) use `.contain` so the button stays one.
- **Announcements.** Transient text (confirmations, preview states, banners) is posted with an announcement.
- **Text.** No `.secondary` or lighter styles on text the app draws; hierarchy comes from weight and size.
- **Window menu.** Each `Window` scene adds a Window-menu item named after the app. The library scene uses
  `.commandsRemoved()` and `ListedInWindowMenu` lists its window through AppKit as "Library" (the library's name).
  Don't apply `.commandsRemoved()` to the selection scene: it also removes the standard Edit commands (Cut, Copy,
  Paste, Delete, Select All), and with them ⌘C in the list.
- **Checking.** System Events reports some SwiftUI button titles as empty; read labels with the native accessibility
  API (`AXUIElementCopyAttributeValue`) instead.

## Bundle identity and signing

| Setting | Value |
| --- | --- |
| Name | Factorio Blueprint Library |
| Bundle identifier | `local.fb.library` |
| Version | 0.1.0 (build 1), a placeholder until the owner sets a versioning scheme |
| Minimum system | macOS 27.0, Apple Silicon (`arm64`), matching `Package.swift` |
| Signing | Ad-hoc ("Sign to Run Locally", identity `-`), no team |
| App Sandbox | Off (milestone 3 decision 2); hardened runtime off |
| Entitlements | Debug: `get-task-allow` only, for debugging; Release: none |

Developer ID signing and notarization belong to distribution, which is outside v1.

## Verification rule

Ordinary UI subtasks are verified with `just lint`, `just test`, and `just app-build`. The independence check runs
when a change touches dependencies or resources (`Package.swift`, new packages, files read from outside the
repository), build tooling (`tools/swift.sh`, `tools/xcode.sh`, the Xcode project), what goes into the bundle, or
network access, and at milestone acceptance (owner decision, 2026-11-14).
During milestone 4, subtasks run only the focused suites for what they changed, with `just lint` and `just app-build`;
the full `just test` runs at the end (owner decision, 2026-11-15; see the
[milestone 4 plan](../planning/Milestone-4.md#verification)). Launching the app is the smoke run's job
(below), run for changes to windows, menus, or previews and at acceptance.

## Independence

`python3 tools/check-independence.py --deny-path ../fb` copies `App/` and both wrappers into a relocated tree and
builds the Debug app there with the original checkout and the given paths unreadable and networking denied. It no
longer launches the app (A17 moved that to the smoke run).

## Smoke run

```sh
just app-smoke --assets .cache/renderer-assets --deny-path ../fb
```

`tools/smoke-app.py` (after `just build` and `just app-build`, which the recipe runs) copies the Debug app into a new
`.cache/smoke/<time>/`, makes a scratch library there from committed fixtures with the CLI, and launches the copy under
`sandbox-exec` with IP networking denied (a blanket `deny network*` also blocks the local connections a GUI app needs),
the given paths unreadable, a fresh `-FBNativeDefaultsSuite`, and `FB_NATIVE_TRASH_DIRECTORY` pointing into the run,
so replaced originals never reach the owner's Trash. It drives the app with System Events keystrokes and menu clicks,
saves window captures (`NN-<screen>.png`), `report.md`, and `results.json` there, and exits 1 if a check fails.
Without `--assets` the worker and release-change checks are skipped.

Checks, in order: the first launch shows library selection (the window check the independence check used to make,
counting windows on any Space because a directly launched app is not activated) and quits cleanly; the relaunch
reopens the library; three previews opened before anything is cached run with at most one worker (`pgrep`, sampled
every 50 ms; selecting an item renders it for the inspector, so this runs first); without assets, the preview and
Statistics say what they need; Copy String gives the fixture's exact bytes; Import from Clipboard, Add Comment, New
Folder, Move To, Move to Trash, and opening a book work; Space opens a preview window and opening it again reuses it;
a background change keeps the zoom and starts no worker; renaming and replacing reach the open window (title, new
image); clearing the release in Settings reaches the window; quitting with windows open does not restore them;
closing the library closes its windows; after quit no worker remains, `fb-native owner` reports idle, and
`fb-native list` shows the imported, moved, renamed, and deleted items as expected, with removed originals in the
run's `trash/`.

The tool presses Escape before each step's search, so a sheet a failed step left open does not take the following
keystrokes. Rows in sheets are selected with a real click (SwiftUI ignores setting a row's selected attribute), and
the helper looks in an open sheet before the window behind it.

It takes the keyboard and brings the app forward for a few minutes: the owner keeps hands off, and the terminal
needs Accessibility and Screen Recording access. The clipboard text is saved and restored. A small native helper,
compiled into the run directory, reads windows: the window-server list for the launch and captures (it also lists
hidden windows, so captures prefer on-screen ones), and the accessibility API for visible titles, button presses, and
static text (System Events reports some SwiftUI button labels as empty).

## Pending work

- **Copying or saving preview images:** assigned to milestone 4, subtask R9 ([plan](../planning/Milestone-4.md)).
