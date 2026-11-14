# Manage a blueprint library in a native macOS app

Date: 2026-11-14. Status: approved by the owner on 2026-11-14 (milestone 3, subtask A1).
Plan: [milestone 3](../planning/Milestone-3.md). Screen layout, focus order, and shortcuts belong to the A2 screen specs.

## Problem

The owner keeps Factorio blueprint strings in a native library that only the `fb-native` CLI can operate today.
Every everyday task (finding a blueprint, reading a book's contents, importing a string from the clipboard, copying
one back into the game, writing a note, comparing two designs) needs a terminal command, an item UUID copied from
JSON output, and stored entry indices typed by hand.
Previews exist only as PNG files written into the library cache, and two blueprints cannot be viewed side by side.
No usage data exists beyond the owner's own workflow; nothing in this spec rests on measured user numbers.

## User

One person, the owner, on their own Mac (macOS 27 or later, Apple Silicon).
They want the app for browsing, importing, exporting, commenting, organizing, and visual comparison, and keep the
CLI for maintenance (milestone 3 decision 6).
Assumptions, not measured: the library holds hundreds of saved strings (the plan's workload target is 1,000 roots),
and the private renderer assets may be missing, for example on a fresh machine.

## Terms

- **Library:** a native library directory ([storage contract](../contracts/Storage.md)). The app opens one at a time.
- **Item:** one saved root string (blueprint, book, or planner) with its comments.
- **Entry:** the root or any blueprint, planner, or book inside a book, addressed by its actual stored indices
  (for example `5.0`); indices can be sparse.
- **Assets:** a verified private asset release; previews and statistics need it, nothing else does.
- **Preview window:** a separate window showing one entry's image, so several can be compared.

## Acceptance criteria

Criteria are numbered per workflow; the subtask that implements each group is in its heading.
Every user-facing date is shown in the Mac's time zone and date format; stored timestamps remain UTC.

### General (all subtasks)

- **GEN-1** Given no network connection, when the owner performs any workflow in this spec, then it works the same
  as with a connection.
- **GEN-2** Given no asset release is configured, when the owner uses library selection, browsing, books, import,
  export, comments, organization, and settings, then each works; previews and statistics show their
  "no assets configured" state (PRV-9, STA-4) instead of an error.
- **GEN-3** Given any case of `NativeLibraryError`, `BlueprintCodecError`, `PreviewError`, `StatisticsError`, or
  `AssetReleaseError`, when it reaches the app, then the owner sees a message that says what happened and what they
  can do, with the error code in the message details where the type defines one; no failure is shown as only a code
  or raw errno.
- **GEN-3a** Given a render cancelled by the owner's own action (selection change, window close, quit), when it ends,
  then no error is shown.
- **GEN-3b** Given an action refused because the library holds the maximum number of pending operations
  (`LIBRARY_LIMIT`), when the message is shown, then it names `fb-native staging-cleanup <library>` as the remedy.
- **GEN-4** Given any failed action, when its message is dismissed, then stored originals, metadata, and comments are
  unchanged unless the message says otherwise.
- **GEN-6** Given a library on any volume, case-sensitive or case-insensitive, when the owner creates, imports,
  unpacks, renames, or moves an item or folder, then the library's own check, made before anything is written,
  treats two names as the same when they differ only by letter case under full Unicode case folding (for example
  `File`/`file`, `Straße`/`STRASSE`, `σ`/`ς`) or by Unicode normalization; the result (refusal or ` (2)` suffix) is
  identical on both kinds of volume and never depends on the filesystem reporting a collision.
  Verified on a case-sensitive APFS volume as well as a case-insensitive one.
- **GEN-7** Given a library already containing two names in one folder that are the same under GEN-6 (possible only
  if created outside the app on a case-sensitive volume), when it is listed, then both appear as listing issues
  (BRW-8) and neither is usable until one is renamed outside the library session.
- **GEN-8** Given `.DS_Store` files anywhere in the library directory (its root, library folders, `operations/` and
  each operation directory, `cache/`, `operations-quarantine/`), created, changed, or removed at any time, including
  while an operation runs or between an interrupted operation and its recovery, when the library is opened, listed,
  recovered, or changed, then they never cause a refusal, listing issue, recovery requirement, or integrity conflict,
  and they are never treated as library content; a folder containing only `.DS_Store` (and a folder description)
  counts as empty (ORG-10). (Needs LibraryCore changes: a `.DS_Store` in `operations/` or in an operation directory
  currently blocks opening with `RECOVERY_REQUIRED`, and folder move/delete inventories include `.DS_Store` files.)
- **GEN-5** Given the main window, when the owner uses only the keyboard, then every workflow in this spec can be
  completed. (Detailed checks: A16.)

### Library selection (A5)

- **LIB-1** Given no library has been opened before, when the app launches, then it offers Open Library and
  New Library and lists no recent libraries.
- **LIB-2** Given an empty folder on local storage, when the owner chooses New Library and selects it, then a
  library is created there, opened, and shown with an empty root folder; choosing an empty folder with Open Library
  offers to create a library there in the same way.
- **LIB-3** Given an existing native library, when the owner opens it, then its root folder is listed and it is added
  to the recent libraries list.
- **LIB-4** Given a recent library whose folder no longer exists or is unreachable, when the list is shown, then that
  entry is marked unavailable, cannot be opened, and can be removed from the list.
- **LIB-5** Given a non-empty folder that is not a native library, when the owner tries to open or create a library in
  it, then the app refuses, explains that the folder is not a library and not empty, and writes nothing there.
- **LIB-6** Given a folder in iCloud Drive or another FileProvider location, when the owner tries to open or create a
  library in it, then the app refuses and asks for local storage outside synchronized locations.
- **LIB-7** Given a library with an unsupported format version or malformed control files, when the owner opens it,
  then the app refuses with a message naming the problem and leaves the files unchanged.
- **LIB-8** Given the library is owned by a CLI command or another app instance, when the owner opens it, then the app
  says another process is using it, offers Try Again, and does not wait or retry by itself.
- **LIB-9** Given a library is open, when the owner opens a different library, then the current library and all of
  its preview windows close and its ownership is released before the new one is opened; if the new one fails to
  open, the owner is back at library selection.
- **LIB-10** Given a library is open in the app, when `fb-native owner <library>` runs, then it reports the library as
  owned; after the owner closes the library, it reports it as free.
- **LIB-11** Given a library was open when the app last quit, when the app launches and that library is still
  available, then it reopens automatically (recovery and in-use states apply as on any open); when it is unavailable,
  library selection is shown with that entry marked unavailable.

### Recovery (A4, A5)

- **REC-1** Given a library with a committed interrupted operation (the app or CLI quit or crashed during a change),
  when the owner opens it, then the operation is completed and the library opens normally, and a non-blocking warning
  says that a change was interrupted and has now been completed, naming the kind of change where its record
  identifies it; the warning can be dismissed and does not reappear on the next open. (Needs a LibraryCore addition:
  opening currently replays without reporting which operations it completed.)
- **REC-1a** Given only uncommitted staging is left from an interrupted change (it never altered the library), when the
  owner opens it, then no warning is shown; that staging stays a CLI `staging-cleanup` matter (decision 6).
- **REC-2** Given replay refuses an operation, when the owner opens the library, then the app shows that recovery is
  required, lists the pending committed operations by ID and kind (as `fb-native operations` does), and offers
  Recover and, for each listed operation, a copyable `fb-native recover <library> --quarantine <operation-id>`
  command with the library path filled in. (The core reports pending operations, not which one replay refused.)
- **REC-3** Given REC-2, when the owner chooses Recover and replay still refuses, then the library stays closed, the
  same explanation and command remain available, and nothing in the library is moved or deleted by the app.
- **REC-4** Given REC-2, when the operation is quarantined with the CLI and the owner chooses Try Again, then the
  library opens.
- **REC-5** Given an open library, when a mutation fails in a way that blocks the session, then every further library
  action is unavailable, the app shows that recovery is required with Recover, and a successful Recover restores
  normal use without reopening.

### Browsing (A6)

- **BRW-1** Given an open library, when it is shown, then the folder hierarchy, including empty folders, is browsable,
  and the selected folder lists its items with name, kind (blueprint, book, upgrade planner, deconstruction planner),
  updated date, and size in decimal B/KB/MB with the exact byte count available.
- **BRW-2** Given a folder with no items or subfolders, when it is selected, then an empty state says so and offers
  import.
- **BRW-3** Given a library with no items at all, when it opens, then the empty state offers import.
- **BRW-4** Given a selected nested folder, when it is shown, then its path from the library root is visible and each
  ancestor can be selected from that path.
- **BRW-5** Given text in the name filter, when it is applied, then items in every folder whose names contain the text
  (case- and diacritic-insensitive) are listed, each with its folder; clearing the filter returns to the selected
  folder.
- **BRW-6** Given the filter matches nothing, when it is applied, then an empty state says no items match.
- **BRW-7** Given a folder with a stored description (from an unpacked book), when it is selected, then the description
  is shown as plain text with its line breaks.
- **BRW-8** Given the library contains invalid items (malformed metadata, hash mismatch, duplicate IDs), when it is
  listed, then the valid items are usable, and a visible notice gives the number of issues with each issue's path and
  a message; invalid items cannot be selected for actions.
- **BRW-9** Given an item with a cached preview for the current assets, when its row is shown, then the row shows that
  thumbnail; given no cached preview, the row shows its kind instead; no row ever starts a render (decision 4).
- **BRW-10** Given the library exceeds a listing bound, when it is listed, then the app says the library is too large
  to list rather than showing a partial list as complete.

### Books and planners (A7)

- **BOOK-1** Given a selected book item, when it is shown, then its immediate children (blueprints, planners, nested
  books) appear in stored order, each with its stored index, name, and kind.
- **BOOK-2** Given a book with sparse stored indices (for example 0, 3, 7), when it is shown, then the displayed
  indices are 0, 3, and 7, and actions on an entry address that entry.
- **BOOK-3** Given a nested book, when the owner opens it, then its immediate children are shown with their full
  stored path, and the owner can return to each containing book.
- **BOOK-4** Given an empty book, when it is shown, then an empty state says the book has no entries.
- **BOOK-5** Given any entry with a description, when it is shown, then the description appears as plain text with
  its line breaks; planners use `settings.description`, falling back to the top-level description.
- **BOOK-5a** Given a selected entry, when it is shown, then its saved Factorio version appears as
  `major.minor.patch`, decoded from that entry; an invalid stored version is shown as unknown rather than as a
  malformed number.
- **BOOK-6** Given an upgrade or deconstruction planner, when it is shown, then its mappings or filters and settings
  appear as text; no statistics are offered.
- **BOOK-7** Given an entry inside a book, when it is shown, then rename, move, replace, and delete are not offered for
  it; they apply to the whole item.
- **BOOK-8** Given an entry whose blueprint fields are unknown to the app, when it is shown or exported, then the
  stored source is unchanged and exports still contain those fields.

### Import (A8)

- **IMP-1** Given a blueprint, book, or planner string on the clipboard, when the owner pastes it into Import and
  saves, then a new item is created in the target folder whose stored bytes equal the pasted text, including
  surrounding whitespace and line endings, and the new item is selected.
- **IMP-2** Given a TXT file, when the owner imports it through an open panel or by dragging it onto the item list or
  a folder, then the stored bytes equal the file's bytes exactly, including CRLF and trailing whitespace.
- **IMP-3** Given several TXT files, when they are imported together, then each becomes its own item, and a summary
  lists any file that failed with its reason; files that succeeded stay imported.
- **IMP-4** Given no target is chosen, when the owner imports, then the target is the selected folder (the library
  root when none is selected); dropping onto a folder targets that folder.
- **IMP-5** Given an optional name, when the item is saved, then it uses that name; without one, it uses the string's
  label, or a kind-specific untitled name when there is none.
- **IMP-6** Given an item whose name collides under GEN-6 already exists in the target folder, when the import is saved,
  then the new item gets the next ` (2)`, ` (3)` suffix and the existing item is unchanged.
- **IMP-7** Given an invalid string (not a blueprint string, corrupt data, over a codec limit), when the owner saves,
  then nothing is created and the message says the string is invalid or which limit it exceeds.
- **IMP-8** Given an empty paste or empty file, when the owner tries to save, then saving is refused with a message
  and nothing is created.
- **IMP-9** Given a book string and "Unpack book into folders", when the owner saves, then a folder tree is created
  with one item per leaf, stored-index name prefixes (for example `5 - Nested/0 - Leaf`), and book descriptions as
  folder descriptions, and the new top folder is selected.
- **IMP-10** Given IMP-9, when the owner chooses unpacking, then the app states before saving that each leaf is saved
  as a newly encoded string and the book's original string is not kept unless it is also saved as one book.
- **IMP-11** Given a non-book string with "Unpack book into folders", when the owner saves, then nothing is created and
  the message says only books can be unpacked.
- **IMP-12** Given a book unpacked into a folder where its top folder name collides under GEN-6, when it is saved, then
  the new top folder gets a suffix and the existing folder is unchanged.

### Export (A9)

- **EXP-1** Given a selected item, when the owner copies its string, then the clipboard text equals the stored root
  bytes exactly, the same bytes `fb-native export` writes.
- **EXP-2** Given a selected entry inside a book, when the owner copies the entry, then the clipboard holds the
  standalone entry string that `fb-native export --entry <indices>` writes for that entry.
- **EXP-3** Given a selected item or entry, when the owner saves it as TXT to a new file, then the file's bytes equal
  the corresponding `fb-native export` output (with `--entry` for an entry), with no added newline.
- **EXP-4** Given the chosen file already exists, when the owner confirms replacing it, then the new file contains
  exactly the exported bytes and the previous file is moved to the Trash rather than overwritten in place; when the
  owner declines, nothing changes.
- **EXP-5** Given a destination inside the open library's folder, when the owner saves there, then the app refuses,
  explains that exports cannot be written inside the library, and writes nothing.
- **EXP-6** Given a write failure (no permission, disk full), when the owner saves, then the message says the file was
  not saved and no partial file remains at the chosen path.

### Comments (A10)

- **COM-1** Given a selected item or entry, when it is shown, then the comments for that scope (root or the entry's
  stored path) are listed oldest first with their local date and plain text, line breaks kept.
- **COM-2** Given no comments for the scope, when it is shown, then an empty state invites adding one.
- **COM-3** Given comment text, when the owner adds it to the root or to an entry, then it appears in that scope and is
  still present after the library is closed and reopened; the item's source bytes are unchanged.
- **COM-4** Given empty or whitespace-only text, when the owner tries to add it, then adding is refused and nothing is
  saved.
- **COM-5** Given text over 64 KiB (UTF-8), when the owner tries to add it, then adding is refused with the limit.
- **COM-6** Given an existing comment, when the owner deletes it and confirms, then it disappears and stays deleted
  after reopening; when the owner cancels, it remains.
- **COM-7** Given a comment promoted to the root by a replacement (prefixed `[Former book entry <indices>]`), when the
  root comments are shown, then it appears with that prefix as ordinary text.

### Organization (A11)

- **ORG-1** Given a selected folder, when the owner creates a subfolder with a valid name, then it appears and is
  selected; a name that collides under GEN-6 with an existing folder or item is refused with a collision message.
- **ORG-2** Given a selected item, when the owner renames it, then the new name is shown, its ID, creation date,
  comments, and source bytes are unchanged, and its updated date changes.
- **ORG-3** Given a selected folder, when the owner renames it, then its contents are unchanged and remain in it.
- **ORG-4** Given a new name that differs from the item's or folder's own current name only under GEN-6 (for example
  `smelter` to `Smelter`), when the owner renames it, then the rename succeeds on both kinds of volume.
- **ORG-5** Given an invalid name (empty, hidden, with path separators or control characters, reserved), when the owner
  renames or creates with it, then the action is refused with a message and nothing changes.
- **ORG-6** Given a selected item or folder, when the owner moves it to another folder by menu or drag and drop, then
  it appears there with its metadata, comments, and dates unchanged.
- **ORG-7** Given a move whose destination already has a name that collides under GEN-6, or a folder moved into itself
  or a descendant, when the owner moves it, then the move is refused with a message and nothing changes.
- **ORG-8** Given a selected item, when the owner deletes it, then a confirmation names the item; on confirmation the
  item disappears and its original TXT and JSON go to the Trash in a folder named
  `<name> (deleted <date> UTC)`; on cancel nothing changes.
- **ORG-9** Given the Trash refuses the deleted or replaced originals, when the deletion or replacement completes, then
  the app says they were kept in `operations-quarantine/` inside the library instead.
- **ORG-10** Given an empty folder (a folder description and `.DS_Store` allowed), when the owner deletes it and
  confirms, then it disappears; a folder with any other content cannot be deleted and the app says it must be empty.
- **ORG-11** Given a selected item, when the owner replaces its source with a pasted string or TXT file and confirms,
  then its ID, creation date, name, and comment identities are unchanged, the new bytes are stored exactly, the
  previous TXT and JSON go to the Trash as `<name> (replaced <date> UTC)`, and its previews are regenerated on demand.
- **ORG-12** Given a replacement where commented book entries no longer exist, when it completes, then those comments
  become root comments prefixed `[Former book entry <indices>]`, and the app reports how many were moved.
- **ORG-13** Given an invalid replacement string, when the owner confirms, then nothing changes and the message says
  why.

### Previews (A12)

- **PRV-1** Given assets are configured and a blueprint or planner entry is selected, when it is shown, then its preview
  is rendered on demand and displayed; books show no rendered preview.
- **PRV-2** Given a cached preview exists for the entry and the current assets, when it is shown, then the image
  appears without starting a preview worker.
- **PRV-3** Given a selected item or book entry, when the owner opens it in a preview window, then a new window shows
  that entry's image titled with its name (and stored indices for an entry); several windows can be open at once.
- **PRV-4** Given the entry is already open in a preview window, when the owner opens it again, then the existing
  window comes to the front instead of a second window.
- **PRV-5** Given several previews need rendering, when they are requested, then at most one preview worker runs at a
  time, renders start in request order, and each waiting view says it is waiting.
- **PRV-6** Given a preview is waiting, when its window closes or the selection changes, then its request is dropped
  without affecting the render in progress; given a preview is rendering, when its window closes or the selection
  changes, then that render is cancelled and the next waiting request starts.
- **PRV-7** Given the same entry is requested by the inspector and a preview window, when both are served, then only
  one worker renders it and the second is served from the cache.
- **PRV-8** Given a displayed preview, when the owner zooms in, zooms out, pans, fits, or shows actual size, then the
  view changes accordingly; resizing the window keeps the image fitted until the owner zooms or pans.
- **PRV-8a** Given a displayed preview, when the owner chooses Checkerboard (the default), Transparent, or a solid
  color, then only that view's background changes, zoom and pan are kept, no render starts, and cached images are
  unchanged; the choice is not saved.
- **PRV-9** Given no asset release is configured, when a preview would be shown, then the view says no assets are
  configured and offers to open Settings; no worker starts.
- **PRV-10** Given a render fails (timeout, memory limit, worker failure, invalid result, asset problem), when the
  failure is shown, then the message gives the reason and offers Retry; other library actions remain available.
- **PRV-11** Given an open preview window, when its item is renamed, then the window title updates; when its source is
  replaced, then the window renders the new source; when the item or the entry no longer exists, then the window says
  so and stays open until closed.
- **PRV-12** Given a blueprint with no entities or tiles, when its preview would be shown, then the view says there is
  nothing to draw, no worker starts, and no Retry is offered (the web application reported a retryable painting
  failure).
- **PRV-13** Given preview windows were open when the app quit, when it relaunches, then they are not restored.

### Statistics (A13)

- **STA-1** Given assets are configured and a blueprint entry is selected, when statistics are shown, then the five
  requirement groups, their total, and the footprint in tiles appear with item names as text and quality where not
  normal.
- **STA-2** Given the seven blueprints approved in [milestone 2](../validation/Milestone-2.md) (`RS.txt`,
  `4x_Rocket_Silo.txt`, `Hazard_Patterns.txt`, `bp.txt` `0.0` and `1.1`, and `v0.59.0.txt` `1.1` from
  `Tests/LibraryCoreTests/Fixtures/Blueprints/`, plus
  `tools/vendor/fpsr/fixtures/visual-tests/official-mods/elevated-rails.bp.txt` `0`), when their statistics are shown, then every count,
  footprint, completeness flag, and warning matches `fb-native statistics` for the same release.
- **STA-3** Given a result with warnings or incomplete parts, when it is shown, then each warning appears once with its
  count, worded from its code and naming the entity, item, tile, or quality involved, and incomplete requirements or
  footprint are marked as incomplete (with known bounds when given).
- **STA-4** Given no asset release is configured, when statistics would be shown, then the panel says assets are needed
  and offers to open Settings.
- **STA-5** Given a book or planner is selected, when the inspector is shown, then statistics are marked not
  applicable rather than failing.
- **STA-6** Given a release whose prototype map is unsuitable, when statistics are requested, then the panel says the
  release cannot provide statistics; previews and other workflows are unaffected.

### Settings and assets (A14)

- **SET-1** Given Settings, when the owner chooses an asset release folder, then it is verified before being accepted,
  and the release name and Factorio version are shown.
- **SET-2** Given a folder that fails verification (missing files, wrong hashes, unsupported profile, raw sprites
  only), when the owner chooses it, then it is refused with the reason and the previous setting is kept.
- **SET-3** Given a release folder that overlaps the library (inside it, or containing it), when the owner chooses
  the release or opens such a library, then previews and statistics refuse to use that release and say why; the
  library itself still opens.
- **SET-4** Given a configured release, when the app is relaunched, then the setting is kept; if the folder is gone or
  no longer verifies, previews and statistics show the problem and every other workflow works.
- **SET-5** Given a configured release, when statistics are shown for several entries, then its prototype map is
  loaded once, not per entry.
- **SET-5a** Given previews or statistics are shown, when the owner selects a different release, then renders in
  progress are cancelled, and every open preview and statistics view is shown again from the new release (from its
  cache when one exists).
- **SET-6** Given Settings, when the owner clears the asset release, then previews and statistics show their
  "no assets configured" state.

### Menus and lifecycle (A15)

- **LIFE-1** Given an open library, when the owner closes the main window, then its preview windows close, renders are
  cancelled, and ownership is released (`fb-native owner` reports it free).
- **LIFE-2** Given renders in progress, when the owner quits, then the app exits, no preview worker process remains, and
  the library is released.
- **LIFE-3** Given a mutation in progress, when the owner quits, then the mutation completes or is recoverable on the
  next open; quitting does not leave the library refusing to open without a recovery path.
- **LIFE-4** Given every workflow above, when the owner looks for it, then it is reachable from the menu bar as well as
  from the window. (Menu structure and shortcuts: A2.)

## Out of scope

- **Several libraries open at once:** decision 3 chose one library per app.
- **Thumbnail grids, cards, and thumbnails for uncached rows:** milestone 4 (decision 4); list rows show a thumbnail
  only when one is already cached.
- **Icons:** blueprint and book name icons and item icons in statistics need the private sprite atlases; milestone 4.
- **Saved Factorio versions in list rows:** listing hashes sources without decoding them, so it has no version.
- **Maintenance screens:** cache and staging cleanup, quarantine, operations listing, and disk usage stay in the CLI
  (decision 6); so does the web app's information page.
- **Copying or saving a preview image:** required by the owner but deferred to a later milestone (not yet
  assigned); cached images and the viewer must not prevent it.
- **Reveal in Finder:** dropped by the owner; Finder edits to an owned library are unsafe.
- **Editing entries inside a book:** only whole-item replacement, as in the web application.
- **Undo:** deleted and replaced originals go to the Trash; restoring one means closing the library and moving the
  files back in Finder, as the CLI guide describes.
- **Backup, restore, App Store, sandboxing, installation, and public distribution:** excluded from v1 or milestone 5.
- **Performance targets:** the 1,000-root workload targets belong to milestone 5.
- **Watching for external edits:** external changes to an owned library are unsupported by the storage contract.

## Open questions

None. The owner accepted the proposed defaults on 2026-11-14; they are now criteria LIB-2, LIB-11, BOOK-5a,
IMP-3, EXP-4, PRV-4, PRV-8a, PRV-12, PRV-13, COM-6, and ORG-12.
Remarks from the owner's review added REC-1/REC-1a, GEN-6/GEN-7, and GEN-8, and deferred copying or saving
preview images.

## References

- [Storage contract](../contracts/Storage.md), [preview cache contract](../contracts/Preview-Cache.md),
  [statistics contract](../contracts/Statistics.md).
- [CLI guide](../development/Library-CLI.md) for the equivalent commands and exact-byte export behavior.
- The original web application's workflows are a reference, not a specification.
