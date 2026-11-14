# Resume native implementation

The owner approved the [native plan](planning/macOS-Plan.md) on 2026-11-13.
Milestone 1 is [accepted](validation/Milestone-1.md): all criteria re-verified on `8daa40e` and the representative
images approved by the owner. The approved [core revisions](planning/Core-Revisions.md) that followed are implemented.
Milestone 2 is [accepted](validation/Milestone-2.md), including native construction statistics approved by the owner.

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
The macOS app scaffold builds and launches offline; application scheduling and the UI remain pending.

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
Open finding for A16: Tab never visibly reaches the item list. A8 is done: Import (paste, TXT files, drag and drop; one book or
unpacked) keeps exact bytes and selects the result. A9 is done: Copy String and Save As TXT
for items and book entries, refusing destinations inside the library. Capture only app windows
(`screencapture -l<window>`), never the whole screen. Resume with A10 (comments: list, add, delete).
Asset-release verification still counts a `.DS_Store` as an unexpected member; that is outside A0 and unscheduled.
Copying or saving preview images is required but deferred to a later milestone.

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
