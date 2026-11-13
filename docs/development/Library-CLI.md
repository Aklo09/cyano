# Native library CLI

Manage saved sources and comments without the GUI, artwork, network, or a running game.
Run commands from this repository using `just library`.
Use `just library --help` for the complete implemented command list.

## Start a library

Select a new or empty local APFS directory outside synchronization services.
The parent directory must already exist.
The following shell example uses an example library path:

```sh
library=/private/tmp/My-Blueprint-Library
just library owner "$library"
just library init "$library"
just library list "$library"
```

The owner probe leaves a nonexistent target untouched.
Initialization creates the native marker and managed directories.
An initialized library can be reopened without importing any renderer assets.
Unknown nonempty stores are refused.

## Import, comment, and export

Import an ordinary TXT file:

```sh
just library import "$library" Tests/LibraryCoreTests/Fixtures/Blueprints/RS.txt --name Example
```

Read `result.id` from the returned JSON and assign it to the shell variable `item_id`.
Use that variable for comments and exports:

```sh
just library comment "$library" "$item_id" "A plain-text note"
just library export "$library" "$item_id"
```

Export stdout contains only original bytes, without JSON or an added newline.
Use `--output <new-file.txt>` to create a file exclusively; an existing file is refused.
Output beneath the active library root is refused, including through directory aliases.
Build messages and recipe diagnostics stay on stderr.

Book entry comments and standalone exports accept `--entry 5.0`.
Numbers are actual stored indices, not displayed row numbers.
The path must exist in the saved book.
Omit `--entry` for the root.

Import can select an existing real folder with `--folder "Smelting"`.
Use the commands below to organize directories under ownership.
Close all library owners before making changes in Finder.

## Organize and replace

The empty string addresses the root folder. Paths are relative to `library/`:

```sh
just library folder-create "$library" "" Smelting
just library move "$library" "$item_id" Smelting
just library rename "$library" "$item_id" "Example renamed"
just library folder-move "$library" Smelting "" Production
just library update "$library" "$item_id" Tests/LibraryCoreTests/Fixtures/Blueprints/RS.txt
```

Moving keeps item identity, metadata bytes, comments, dates, and original TXT bytes.
Renaming changes the display override, portable filenames, and update date.
Folder moves also rename when the optional final name is supplied.
Case-only names are supported; collisions and moving a folder into itself are refused.

Replacement keeps the item UUID, creation time, chosen name, and comment identities.
Comments on missing book entries become root comments prefixed with `[Former book entry 5.0]` and two newlines.
Replacement refuses invalid input before changing stored content and invalidates that item's derived cache.
The replaced TXT and JSON move to the Trash as a folder named `<name> (replaced <date> UTC)`.

Read a comment's `id` from the item metadata and pass it to `comment-delete`.
`comment-add` is an alias for `comment`.
Delete an item and then its empty parent with:

```sh
just library delete "$library" "$item_id"
just library folder-delete "$library" Production
```

Item deletion removes both TXT and JSON plus that item's derived cache.
The exact TXT and JSON move to the Trash as a folder named `<name> (deleted <date> UTC)`.
To restore one, close the library and move both files back into a library folder with Finder.
If the Trash cannot accept the folder, it is kept in `operations-quarantine/` inside the library instead.
Folder deletion accepts only an empty folder, allowing a validated folder-description sidecar and `.DS_Store`.
It never recursively deletes library items.

## Unpack a book

```sh
just library import-unpacked "$library" Tests/LibraryCoreTests/Fixtures/Blueprints/v0.59.0.txt
```

Unpacking creates real folders for books, named TXT/JSON pairs for leaves, and fresh UUIDs for every leaf.
Each leaf is saved as a newly encoded standalone string; the original book string is not kept.
To keep the book's exact bytes as well, also import it with `import`.
Stored indices prefix child names, such as `5 - Nested/0 - Leaf`.
Book descriptions become `.folder.json` comments shown in `list.result.folderComments`.
Leaf source fields, including unknown wrapper fields, are retained except the enclosing `index`.
Book container settings such as icons and the active entry are not represented by the resulting folders.
The complete prepared tree becomes visible after the recovery intent commits; a duplicate root name receives a suffix.
Use ordinary `import` to preserve a whole book exactly.

## Saved-item previews

`preview <library> <item-id> --assets <release>` renders under ownership and reuses validated images.
Use `--entry` for selected book leaves and `--refresh` for explicit regeneration.
Results include a library-relative cache path rather than raw image bytes.
See the [library preview guide](Library-Previews.md) for the complete workflow and lifetime rules.

## Maintenance

```sh
just library usage "$library"
just library cache-cleanup "$library"
just library cache-cleanup "$library" all --apply
```

Cache cleanup defaults to the `abandoned` scope and a dry run.
`--apply` recomputes its selection under ownership; it does not accept a saved deletion plan.
Scoped cleanup recognizes native cache identity manifests, orphaned item results, and `.tmp-<UUID>` files.
Unknown or damaged manifest formats remain protected; `all` explicitly selects all safe derived files.
No cache cleanup scope deletes operations staging or authoritative library content.
Unsafe links, shared file inodes, cross-device descendants, and overlapping selected assets cause refusal before deletion.

`obsolete` additionally compares source hash, stored entry path, generator, and selected asset identity.
It requires `--assets <release-directory>` and optionally accepts `--generator <identity>`.
The default generator is `native-preview-v1`, selecting 2x/2048/transparent previews.
Use the preview result's `generator` with `--generator` when comparing a different rendering variant.
The native manifest format is intentionally separate from historical web caches.

`usage` reports originals, metadata, other library members, cache, operations, controls, and optional assets.
Supply `--assets <release-directory>` to include assets; without it, `complete` is false and an `ASSETS_NOT_SELECTED` issue is explicit.
Logical bytes count every file path; unique logical and allocated bytes deduplicate device/inode pairs.
Allocated bytes use `st_blocks × 512`, including directories, and are not an APFS clone-sharing or guaranteed-reclaim estimate.
Scans stop after 100,000 entries, 64 directory levels, or five seconds; usage reports incomplete categories and issues.

`assets-verify <release-directory>` runs independently of library ownership.
It requires `release.json`, the full `sprites/` inventory, and `statistics/prototype-map.json`.
It verifies canonical release identity, hashes, sizes, supported 2.1.23 profiles, schemas, tiers, and declared packed frame bounds.
It accepts up to 10,000 files and 2 GiB, with bounded JSON reads.
It does not decode images or validate rendering; a raw sprite directory alone is not an assembled release.

## Construction statistics

Report what a saved blueprint needs to be built and its footprint in game tiles:

```sh
just library statistics "$library" "$item_id" --assets .cache/renderer-assets
just library statistics "$library" "$book_id" --entry 1.1 --assets .cache/renderer-assets
```

`--assets` names a verified asset release; its prototype map supplies placement items and collision geometry,
and the result records the release identity. Without `--assets` the command fails with `ASSETS_REQUIRED`;
a release whose map is unsuitable fails with `INVALID_PROTOTYPE_MAP`.
Select a book leaf by stored indices with `--entry`, as for export and previews. A book itself or an
upgrade/deconstruction planner returns `applicable: false` instead of statistics.

The result follows the [statistics contract](../contracts/Statistics.md): five requirement groups and their total,
the footprint, completeness flags, and warnings grouped by code with an occurrence count.
The command verifies the release before opening the library, then reads the entry and releases ownership.
Applications should load the map once with `PrototypeMap.load(release:)` and call `NativeLibrary.statistics`.

## Ownership and recovery

Every ordinary library command owns the store, including listing and export.
Close the application's library before invoking a separate store command.
The owner probe can run while another process owns it:

```sh
just library owner "$library"
```

After all owners close, run `just library recover "$library"` when explicit replay is needed.
Recovery replays committed operations before normal access.
It preserves conflicting live bytes and staged originals instead of overwriting them.
The command does not discard evidence or force an unlock.

If recovery refuses an operation, the library cannot open until that operation is moved aside.
List pending operations without replaying them, then quarantine the refused one by its ID:

```sh
just library operations "$library"
just library recover "$library" --quarantine <operation-id>
```

Quarantine moves the operation directory unchanged to `operations-quarantine/` and the library opens again.
A quarantined committed operation may have published part of its change; remaining inconsistencies appear as listing issues.
Inspect the quarantined intent and staged copies before deleting them; the CLI never deletes quarantined evidence.

Interrupted operations that never committed leave staging that replay ignores but that counts toward the 128-operation limit.
`staging-cleanup` lists them, and `--apply` removes them; committed and quarantined operations are never selected:

```sh
just library staging-cleanup "$library"
just library staging-cleanup "$library" --apply
```

See the [storage contract](../contracts/Storage.md) before investigating interrupted operations.

## Structured results

Successful commands, except help and stdout export, return one JSON object on stdout.
The envelope fields are `schema: 1`, `ok: true`, `command`, and `result`.
Lists include `folders`, `folderComments`, usable `items`, and `issues` for excluded malformed content.
Inspect issues even when listing succeeds.

Failures emit JSON on stderr and leave stdout empty before output begins.
Their envelope has `ok: false`, optional `command`, and an `error` object.
The error includes `category`, `code`, `message`, and `exitCode`.

| Exit | Category |
| --- | --- |
| 0 | Success |
| 1 | Internal codec failure |
| 2 | Invalid command arguments |
| 3 | Ownership or unsupported library filesystem |
| 4 | Integrity conflict or recovery required |
| 5 | Unsupported or malformed native format/metadata |
| 6 | Filesystem or output failure |
| 7 | Invalid content, names, paths, identifiers, or resource limits |
| 8 | Preview execution, cancellation, timeout, or worker-result failure |

`release` reports the available capabilities and native format version without opening a library.
Raw exports preserve their separate byte-oriented protocol.

## Verification

Run focused storage checks:

```sh
just storage-test
```

The test driver is package test support, with no failure-injection flags in the ordinary CLI.
See [storage validation](../validation/Storage.md) for completed checks and limitations.
The [complete-command validation](../validation/Library-Commands.md) covers organization, maintenance, and asset verification.
