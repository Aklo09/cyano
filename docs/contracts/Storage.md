# Native library storage and ownership

Preserve original strings and comments through interrupted writes without an authoritative database.
This contract covers native source storage, organization, comments, maintenance, and recovery.

## Library identity and layout

Choose an ordinary directory on local APFS storage.
Known FileProvider/iCloud locations and ubiquitous directories are rejected.
Other background synchronization cannot be detected reliably and remains unsupported.

```text
Chosen Library/
  .library-format.json
  .owner.lock
  library/
    Example.txt
    Example.json
    Empty Folder/
  operations/
    <operation UUID>/
  operations-quarantine/
    <operation UUID>/
  cache/
```

The native marker contains exactly `format`, `schemaVersion`, `id`, and `createdAt`.
The format is `fb-native-library`; its current version is integer `1`.
Identity uses a canonical lowercase UUID; dates use UTC with millisecond precision.
The marker is immutable during ordinary library sessions.

Initialization refuses unknown nonempty directories, including a bare foreign lockfile; a directory holding only
Finder metadata counts as empty.
A strict `.format.pending` record identifies an interrupted native bootstrap.
Only this control record may be created before kernel ownership is acquired.
Publishing the marker and creating managed directories happen under ownership.
An interrupted marker publication can resume without changing its library identity.
Malformed bootstrap evidence is preserved rather than overwritten.

Readers reject unsupported control versions and unexpected fields.
They do not interpret historical web stores or backup formats.

## Original files and metadata

Each root has adjacent TXT and JSON files sharing one basename.
TXT contains exact imported bytes, including whitespace and line endings.
JSON metadata version `1` contains:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Integer `1` |
| `id` | Stable lowercase UUID |
| `createdAt` | Creation timestamp |
| `updatedAt` | Last metadata-change timestamp |
| `sourceSha256` | Lowercase SHA-256 of exact TXT bytes |
| `displayNameOverride` | Optional explicit import or rename name |
| `comments` | Array of scoped comments |

Every comment contains exactly `id`, `entryPath`, `text`, and `createdAt`.
Comment text remains plain text; empty or whitespace-only comments are rejected.
An empty path addresses the root; other paths use actual stored book indices.
All comment paths must resolve in the saved document.
Comment insertion preserves the item UUID, creation time, source hash, and TXT bytes.

Metadata uses strict field, type, UUID, timestamp, and source-hash validation.
Unknown fields and versions are never silently accepted or rewritten.
Invalid items appear as listing issues and are excluded from usable results.
Duplicate item UUIDs are reported as `AMBIGUOUS_ID` listing issues; ID-addressed operations require a unique match
and refuse duplicates with `AMBIGUOUS_ID`.

Listing validates each item's metadata and the SHA-256 of its exact TXT bytes, but does not decode the blueprint.
The entry kind comes from `cache/source-index.json`, a derived map from source hash to kind.
Being keyed by content, an entry cannot become stale; a missing source is decoded once and added,
an unreadable index is rebuilt, and entries for sources no longer in the library are pruned.
Comment entry paths are validated when an item is opened, and when a source is first indexed.

ID-addressed operations use an index of item paths held by the open library. The first lookup or listing
builds it with a full scan; the session's own mutations keep it current, and every hit is re-read and verified.
A stale or missing entry triggers one rescan. Because external edits are unsupported while a library is owned,
the scan at the start of each session preserves duplicate detection.

Folder membership comes from real filesystem directories.
The CLI creates, moves, renames, and deletes empty folders, and lists empty folders.
Unpacked books use `.folder.json` records containing exactly `schemaVersion: 1`, `comment`, and `createdAt`.
Descriptions are plain text, bounded like comments; no folder UUID substitutes for its real path.
An empty folder with a valid description can be deleted; a folder containing other content cannot.

Item moves preserve metadata bytes. Renames preserve identities and creation dates while changing the name and update date.
Source replacement preserves the chosen filename/override and promotes comments whose entry paths disappear to the root.
Item deletion and replacement invalidate the item's derived cache under the same committed intent.
They also retain the removed originals, as described under file and tree mutation publication.

## Portable names and confined access

Initial basenames derive from the source label or explicit import name.
Filename projection examines at most 4,096 UTF-8 bytes before normalization.
It strips rich-text tags and replaces forbidden filename characters.
It preserves source content independently from the resulting name.
Missing or unusable names receive kind-specific untitled names.

The initial basename is capped at 180 UTF-8 bytes.
Duplicate imports receive ` (2)`, ` (3)`, and subsequent suffixes.
Collision keys reproduce APFS case-insensitive name equivalence on every volume, including case-sensitive ones:
NFC normalization, then uppercasing, lowercasing, and Unicode case folding (so `ß`/`SS`, `σ`/`ς`, and U+1C80/`в`
collide). A sweep of every BMP scalar and every case-mapped supplementary scalar against a case-insensitive APFS
volume found no pair that APFS equates and the key distinguishes; the key is stricter only for dotless `ı`, which
it equates with `i`. Collision checks never depend on the filesystem reporting one, and two existing names in one
folder with the same key are listing issues.
Existing physical names are revalidated before publication.
Publication of new files also uses the filesystem's exclusive-rename primitive.

Folder paths are relative, at most 32 components and 4,096 UTF-8 bytes.
Managed components reject traversal, hidden names, control characters, and reserved portable names.
Managed access uses directory descriptors, no-follow opens, and inode/device checks.
Root and source URLs reject remote hosts and decoded NUL characters before filesystem access.
Regular files must have one link; symlinks, hardlinks, and special files are refused.

Finder can create or rewrite a `.DS_Store` file in any directory it displays, and the library cannot prevent it.
A regular file named `.DS_Store` anywhere beneath the chosen root is therefore never library content: listing,
opening, replay, operation and staging validation, folder deletion, cache cleanup, and tree inventories ignore it,
whether it appears, changes, or disappears during an operation or between an interruption and its recovery.
Version 2 tree inventories omit such files; replay also ignores `.DS_Store` members recorded by earlier builds.
Removing a directory also removes its `.DS_Store`. Tree snapshots compare directories by identity, not size or
times, because adding such a file changes both; every file is still compared in full.
Any other filesystem object named `.DS_Store` is refused like other unsafe members.
Disk usage still counts these files, and asset-release verification does not apply this rule.
FIFO rejection does not block waiting for a writer.
Root aliases may resolve to the same directory before ownership acquisition.

External file reads are bounded before allocating the complete input.
Changing file size or modification state during a read causes refusal.
Reads do not authorize concurrent external edits to a live library.

## Kernel ownership and operation serialization

The permanent `.owner.lock` inode carries a nonblocking exclusive `flock` lease.
File existence, PID age, and timeout expiry never establish ownership.
An existing native library must retain its lockfile; a missing lock is not recreated.
Live sessions detect replaced lockfiles and changed directory identities.

One `NativeLibrary` object owns a library until `close()` or deallocation.
All complete operations run synchronously on that object's serial queue.
There are no suspension points inside read-modify-write operations.
Concurrent comments therefore append without losing another accepted comment.
Closing drains earlier queued work, rejects later operations, and releases the lease.
Closing again is harmless.
Closing also cancels every in-flight preview and waits for its worker cleanup before the owner lease closes.
See the [preview lifetime/cache contract](Preview-Cache.md) for the worker process boundary and derived publication.

Separate app/CLI instances cannot open the same live library, including through aliases.
Ordinary reads and exports require ownership too.
Application windows should share their owning `NativeLibrary` object.
The `owner` probe is the read-only exception and reports a point-in-time kernel state.
It creates no directories, replays no operations, and writes no diagnostics.

There is no force-unlock operation.
Do not edit files or copy a library while another owner is active.
A closed-library copy must include the entire chosen root, including hidden controls and operations.
Application-managed snapshots, verification, and restoration remain outside v1.

## Import and comment publication

Every operation receives a fresh UUID directory beneath `operations/`.
Staged source and metadata bytes remain separate from temporary publication copies.
The original intent schema contains exactly:

`schemaVersion`, `operationId`, `kind`, `folder`, `basename`, `itemId`,
`sourceSha256`, `metadataSha256`, and optional `beforeMetadataSha256`.

Version is `1`; supported kinds are `import` and `comment`.
Comments require the previous metadata hash; imports omit it.
Hashes describe exact stored bytes, without relying on JSON canonicalization.

1. Validate source, names, metadata, and the destination.
2. Write staged files exclusively and synchronize them.
3. Write and synchronize `intent.pending`.
4. Rename it to `intent.json`, synchronize its directory, and issue a drive barrier.
5. Validate staged hashes and destination preconditions again.
6. Publish the source and metadata through synchronized atomic renames.
7. Issue a drive barrier, remove the intent, then remove owned staging files.

The published, synchronized intent commits the operation to roll forward.
Imports publish the TXT before JSON; the pair itself is not atomic.
Comments atomically replace only the JSON after checking its previous hash.
The original TXT remains untouched.

New destinations are never overwritten.
Existing destinations must match the intended after-hash or the recorded before-hash.
An already matching after-hash makes replay idempotent.
Unexpected bytes stop replay and preserve both live files and staged evidence.

Durability policy:

- Staged, published, and cache files use checked `fsync`; affected directories are synchronized after creation, rename, and cleanup.
- A drive barrier (`F_FULLFSYNC`) follows each intent commit rename, so staged bytes and the intent reach
  permanent storage before any live file changes. A second barrier precedes intent removal, so published
  changes are permanent before the record that can replay them disappears. Library initialization issues
  one barrier after publishing the format marker.
- Disposable cache publication issues no drive barrier.
- Synchronization errors prevent success reporting.

Measured with a release build on local APFS, this policy reduced a small import from 39.7 ms to 24.6 ms
and unpacking a 182-leaf book from 2.21 s to 0.80 s, compared with a drive flush per staged file.
Apple's [fsync reference](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html)
distinguishes host synchronization from stronger drive-flush requests.
Process-kill tests do not establish power-loss durability.

## File and tree mutation publication

Organization and replacement use intent version `2`; readers continue to replay version `1` intents.
Version `2` operations follow the same durability policy: a drive barrier after the intent commit rename and before intent removal.
The library marker and item metadata remain at version `1`.
Version `2` requires `schemaVersion`, `operationId`, `kind`, `changes`, and `cacheIds`,
with optional `sourceFolder`, `destinationFolder`, and `tree` for tree operations.
Unexpected fields, versions, paths, sizes, and hashes are refused.

`files` intents contain relative paths with optional `before` and `after` SHA-256 hashes.
Exact preimages and postimages are staged as `before-000000` and `after-000000`, indexed in change order.
All staged bytes and live preconditions are checked before publishing the intent and on replay.
Old names are removed before new names publish, supporting case-only renames on insensitive APFS.
Replacement retains its staged preimage until publication and cache invalidation complete.

Item deletion and source replacement also stage copies of the exact preimage TXT and JSON under
`removed/<name> (deleted|replaced <date> UTC)/` before the intent commits. After publication and the drive barrier,
and before intent removal, that folder moves to the macOS Trash; replay skips the step once `removed/` is gone,
so a crash never loses or duplicates it. If the Trash refuses the folder, it moves to `operations-quarantine/`
inside the library instead, so an unavailable Trash never blocks recovery.
`FB_NATIVE_TRASH_DIRECTORY`, an absolute path, redirects these folders for tests and development;
`tools/swift.sh test` sets it to `.cache/test-trash`.
The multi-file operation becomes consistent through roll-forward recovery; it is not one filesystem-atomic rename.

`tree-create` and `tree-delete` intents record a complete directory/file inventory with exact file hashes and sizes.
`tree-move` intents record an identity inventory instead: the moved folder's root inode plus every member path and size,
without reading file content. A rename preserves the inode, and APFS inode numbers survive remounts,
so replay identifies the moved folder even after a restart; a look-alike folder with the same members is refused.
Replay still accepts move intents written with content hashes.
Creation prepares the whole tree under staging before commit.
Move withdraws the source to `operations/<UUID>/tree`, then publishes it exclusively at its destination.
Empty-folder deletion withdraws the validated folder to staging before removing the intent and cleaning the withdrawn tree.
Exactly one matching tree must exist at the source, stage, or destination on replay.
Conflicting trees, unsafe members, or unexpected destination bytes preserve the evidence and stop recovery.
Unpacking publishes all folders, descriptions, and leaf pairs as one prepared tree.
By design, each leaf TXT is a newly encoded standalone string that preserves the leaf's JSON, unknown fields included;
the original book string is not retained, so the book cannot be reassembled byte-for-byte from unpacked items.
Importing the book with `import` keeps its exact bytes.

Cache cleanup is a separate repeatable derived-file operation with dry-run default, bounded inventory,
and stamp revalidation before deletion. It does not purge operations staging; `staging-cleanup` does.

## Recovery and bounded work

Opening an owned library replays committed intents before exposing ordinary operations.
`NativeLibrary.completedOnOpen` lists the committed operations that opening completed (ID and intent kind), and
`recover()` returns those it completed, so applications can tell the owner that an interrupted change finished.
`requiresRecovery` reports whether a failed mutation has blocked the session.
Explicit `recover` invokes the same replay logic and is safe to repeat.
Failed mutations block further work in that session until recovery or reopening.
Unsupported or conflicting intents remain preserved for investigation.

Unpublished staging is ignored by normal replay. It never changed the library: either its intent never committed,
or it remains after intent removal but before staging cleanup.
`staging-cleanup` selects only operation directories without `intent.json`, validates their members,
and removes them with `--apply`; it is a dry run by default and runs under normal ownership.

A refused operation blocks opening. `operations` lists pending operations under ownership without replaying them.
`recover --quarantine <operation-id>` moves one operation directory unchanged to `operations-quarantine/`,
followed by a drive barrier. Replay ignores quarantined operations, so the library opens again.
A quarantined committed operation may have published part of its change; inconsistencies surface as listing issues,
and the quarantined intent and staged copies remain for manual inspection.
Do not delete an operations directory to bypass a recovery refusal; quarantine it instead.
Disk usage counts quarantined operations with `operations`.

| Work | Initial bound |
| --- | --- |
| Format and version 1 intents | 64 KiB each |
| Version 2 intent | 16 MiB |
| File changes per version 2 operation | 10,000 |
| Total staged pre/postimage or hashed tree content | 256 MiB (folder moves are not content-bounded) |
| Tree inventory members | 100,000 |
| Item metadata | 4 MiB |
| Comment text | 64 KiB UTF-8 |
| Comments per item | 10,000, subject to metadata capacity |
| Operation directories | 128, including unpublished staging |
| Members per version 1 operation directory | 64 |
| Members per version 2 file operation directory | 20,064 |
| Listing entries | 100,000 across the hierarchy |
| Listing source/metadata bytes | 256 MiB |

The [codec ceilings](../development/Codec.md#input-admission) govern TXT decoding.
Directory scans and file reads stop at their limits rather than returning silent partial success.
Listings hash saved sources without decoding them. Release-build measurement on local APFS: listing 888 roots
takes 0.24 s with a warm source index and 0.69 s when rebuilding it; one CLI comment takes 0.06 s.
Renderer helpers hold no owner lease; preview caches remain disposable and separate from authoritative recovery.
