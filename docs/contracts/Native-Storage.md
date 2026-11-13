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
  cache/
```

The native marker contains exactly `format`, `schemaVersion`, `id`, and `createdAt`.
The format is `fb-native-library`; its current version is integer `1`.
Identity uses a canonical lowercase UUID; dates use UTC with millisecond precision.
The marker is immutable during ordinary library sessions.

Initialization refuses unknown nonempty directories, including a bare foreign lockfile.
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
Duplicate item UUIDs are reported; ID-addressed operations require a unique match.

Folder membership comes from real filesystem directories.
The CLI creates, moves, renames, and deletes empty folders, and lists empty folders.
Unpacked books use `.folder.json` records containing exactly `schemaVersion: 1`, `comment`, and `createdAt`.
Descriptions are plain text, bounded like comments; no folder UUID substitutes for its real path.
An empty folder with a valid description can be deleted; a folder containing other content cannot.

Item moves preserve metadata bytes. Renames preserve identities and creation dates while changing the name and update date.
Source replacement preserves the chosen filename/override and promotes comments whose entry paths disappear to the root.
Item deletion and replacement invalidate the item's derived cache under the same committed intent.

## Portable names and confined access

Initial basenames derive from the source label or explicit import name.
Filename projection examines at most 4,096 UTF-8 bytes before normalization.
It strips rich-text tags and replaces forbidden filename characters.
It preserves source content independently from the resulting name.
Missing or unusable names receive kind-specific untitled names.

The initial basename is capped at 180 UTF-8 bytes.
Duplicate imports receive ` (2)`, ` (3)`, and subsequent suffixes.
Collision keys use NFC normalization and lowercase comparison.
Existing physical names are revalidated before publication.
Publication of new files also uses the filesystem's exclusive-rename primitive.

Folder paths are relative, at most 32 components and 4,096 UTF-8 bytes.
Managed components reject traversal, hidden names, control characters, and reserved portable names.
Managed access uses directory descriptors, no-follow opens, and inode/device checks.
Root and source URLs reject remote hosts and decoded NUL characters before filesystem access.
Regular files must have one link; symlinks, hardlinks, and special files are refused.
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
Closing also signals a bound preview's cancellation token and drains worker cleanup before the owner lease closes.
See the [preview lifetime/cache contract](Native-Preview-Cache.md) for inherited kernel ownership and derived publication.

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
4. Rename it to `intent.json` and synchronize its directory.
5. Validate staged hashes and destination preconditions again.
6. Publish the source and metadata through synchronized atomic renames.
7. Remove the intent after successful publication, then remove owned staging files.

The published, synchronized intent commits the operation to roll forward.
Imports publish the TXT before JSON; the pair itself is not atomic.
Comments atomically replace only the JSON after checking its previous hash.
The original TXT remains untouched.

New destinations are never overwritten.
Existing destinations must match the intended after-hash or the recorded before-hash.
An already matching after-hash makes replay idempotent.
Unexpected bytes stop replay and preserve both live files and staged evidence.

Files use checked `fsync` and `F_FULLFSYNC` calls before publication.
Affected directories are synchronized after creation, rename, and cleanup.
Synchronization errors prevent success reporting.
Apple's [fsync reference](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html)
distinguishes host synchronization from stronger drive-flush requests.
Process-kill tests do not establish power-loss durability.

## File and tree mutation publication

Organization and replacement use intent version `2`; readers continue to replay version `1` intents.
The library marker and item metadata remain at version `1`.
Version `2` requires `schemaVersion`, `operationId`, `kind`, `changes`, and `cacheIds`,
with optional `sourceFolder`, `destinationFolder`, and `tree` for tree operations.
Unexpected fields, versions, paths, sizes, and hashes are refused.

`files` intents contain relative paths with optional `before` and `after` SHA-256 hashes.
Exact preimages and postimages are staged as `before-000000` and `after-000000`, indexed in change order.
All staged bytes and live preconditions are checked before publishing the intent and on replay.
Old names are removed before new names publish, supporting case-only renames on insensitive APFS.
Replacement retains its staged preimage until publication and cache invalidation complete.
The multi-file operation becomes consistent through roll-forward recovery; it is not one filesystem-atomic rename.

`tree-create`, `tree-move`, and `tree-delete` intents record a complete directory/file inventory with exact file hashes and sizes.
Creation prepares the whole tree under staging before commit.
Move withdraws the source to `operations/<UUID>/tree`, then publishes it exclusively at its destination.
Empty-folder deletion withdraws the validated folder to staging before removing the intent and cleaning the withdrawn tree.
Exactly one matching tree must exist at the source, stage, or destination on replay.
Conflicting trees, unsafe members, or unexpected destination bytes preserve the evidence and stop recovery.
Unpacking publishes all folders, descriptions, and leaf pairs as one prepared tree.

Cache cleanup is a separate repeatable derived-file operation with dry-run default, bounded inventory,
and stamp revalidation before deletion. It does not purge unpublished operations staging.

## Recovery and bounded work

Opening an owned library replays committed intents before exposing ordinary operations.
Explicit `recover` invokes the same replay logic and is safe to repeat.
Failed mutations block further work in that session until recovery or reopening.
Unsupported or conflicting intents remain preserved for investigation.

Unpublished staging is retained and ignored by normal replay.
This also covers interruption after intent removal but before staging cleanup.
Automatic abandoned-staging maintenance is deferred.
Do not discard an operations directory to bypass a recovery refusal.

| Work | Initial bound |
| --- | --- |
| Format and version 1 intents | 64 KiB each |
| Version 2 intent | 16 MiB |
| File changes per version 2 operation | 10,000 |
| Total staged pre/postimage or tree content | 256 MiB |
| Tree inventory members | 100,000 |
| Item metadata | 4 MiB |
| Comment text | 64 KiB UTF-8 |
| Comments per item | 10,000, subject to metadata capacity |
| Operation directories | 128, including unpublished staging |
| Members per version 1 operation directory | 64 |
| Members per version 2 file operation directory | 20,064 |
| Listing entries | 100,000 across the hierarchy |
| Listing source/metadata bytes | 256 MiB |

The [codec ceilings](../development/Native-Codec.md#input-admission) govern TXT decoding.
Directory scans and file reads stop at their limits rather than returning silent partial success.
Listings currently decode and validate saved sources; large-library performance remains unqualified.
Bound renderer helpers now share the owner lease; preview caches remain disposable and separate from authoritative recovery.
