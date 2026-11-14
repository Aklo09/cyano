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

Rows show their kind symbol. Cached thumbnails (BRW-9) need the asset release identity, so they appear once Settings
(A14) and previews (A12) exist; no row ever starts a render.

The app registers `ApplePersistenceIgnoreState`: AppKit's saved application state is keyed by bundle identifier,
and after a quit with no windows open it made later launches, even with separate preferences, open no window.

## Library selection and windows

`LibrarySelectionModel` outlives both windows and decides which one shows through `windowGoal`:

- **Two windows:** the selection window (`library-selection`) and the library window (`library`). Each mirrors
  `windowGoal`, opening the other and dismissing itself, so a failed open from either window lands in selection
  with its message. Windows are never restored from a previous run.
- **Launch:** when the library open at the last quit is still reachable, only the library window is presented and
  it reopens that library (LIB-11); otherwise only selection. A failed reopen ends in selection.
- **Closing:** Close Library (⇧⌘W) or closing the library window releases the library and forgets it for the next
  launch; quitting keeps it.
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
network access, and at milestone acceptance (owner decision, 2026-11-14). The app launch it performs moves to the
scripted smoke runs of A17.

## Independence

`python3 tools/check-independence.py --deny-path ../fb` copies `App/` and both wrappers into a relocated tree,
builds the Debug app there with the original checkout and the given paths unreadable and networking denied, then
launches it with a scratch preferences domain and requires a window within 10 seconds. It counts windows on any
Space: a directly launched app is not activated, so its window may open on another Space. The launch denies IP networking only: a blanket
`deny network*` also blocks the local connections a GUI app needs, and the app then shows no window.

## Pending work

- **Preview worker:** the app must carry `preview-worker` inside its bundle before rendering (A12); embedding a
  SwiftPM executable in the Xcode target is not set up yet.
