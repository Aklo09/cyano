# Complete native library commands

Organization and maintenance commands now share the native library's ownership and recovery rules.
The prior storage checkpoint was committed as `aa6d5e5` before this implementation began.
Recorded: 2026-11-13, in the [foundation environment](Foundation.md#environment).
Native statistics, real-image painting, and the macOS application remain pending.

## Command coverage

The comparison used the original `fb` CLI command inventory and storage behavior.
Native commands use explicit library-path arguments; folder and entry selectors follow the [CLI guide](../development/Library-CLI.md).

| Capability | Native command | Result |
| --- | --- | --- |
| Initialize, inspect ownership, list, recover | `init`, `owner`, `list`, `recover` | Retained |
| Import a whole source | `import` | Exact original bytes retained |
| Unpack a book | `import-unpacked` | Real folders, description sidecars, independent leaf UUIDs |
| Export root or entry | `export` | Raw stdout or exclusive `--output` creation |
| Replace source | `update` | Retains identity, name, creation time; promotes removed-entry comments |
| Rename or move item | `rename`, `move` | Preserves original source bytes and comments |
| Delete item | `delete` | Removes pair and private item cache |
| Create, move/rename, delete empty folder | `folder-create`, `folder-move`, `folder-delete` | Collisions, cycles, root deletion, and nonempty deletion refused |
| Add or delete scoped comment | `comment`, `comment-add`, `comment-delete` | Stable comment IDs and actual stored indices |
| Clean derived caches | `cache-cleanup` | Dry-run default; `abandoned`, `obsolete`, `all`; recomputed `--apply` |
| Measure disk categories | `usage` | Bounded, inode-aware totals and explicit incomplete results |
| Verify offline release | `assets-verify` | Independent inventory/hash/profile/schema verification |
| Application-managed backup and restore | None | Deliberately excluded by the owner |

Scoped cleanup recognizes the reserved native identity format rather than historical web manifests.
Unknown formats remain protected unless `all` is selected.
There is no native preview writer yet; the default generator identifier reserves that future integration.

## Verification

| Check | Result |
| --- | --- |
| `just test` | 54 native tests pass across six suites |
| Relocated isolation check | Fresh build, all native tests, CLI release, and planner probe pass without readable original checkouts, networking, or Node on PATH |
| `just tools-check` | All 153 copied files, 42 planner inputs, and five pinned development dependencies remain valid |
| CLI guide workflow | All runnable examples pass through `just library`, using a disposable library path containing spaces |
| Private release verification | 451 inventoried files, 211,964,616 bytes, both tiers; no image decoding |
| Large supplied book unpack | 18 folders, 162 items, no listing issues; approximately 3.9 seconds for unpack in this debug build |
| `git diff --check` | Pass |

The large-book item count includes 149 blueprints, 12 upgrade planners, and one deconstruction planner.
This is one local smoke measurement, not the full latency/memory acceptance workload.

The isolation command is `python3 tools/check-independence.py --deny-path /Users/aklo/Projects/fb`.
It requires execution outside an enclosing sandbox so its own `sandbox-exec` policy can apply.
Tests and guide workflows create and remove only their disposable directories.
No real user library was opened or modified.
Private assets and qualification outputs remain ignored.

## Process interruption and integrity

The existing 14 storage tests still cover version 1 import/comment recovery and real kernel exclusion.
New tests kill a separate helper process with `SIGKILL` in 35 file/tree publication scenarios:

| Operation | Tested boundaries |
| --- | --- |
| Item rename and move | Changes staged; intent published; old file removed; new file published; intent removed |
| Source replacement | Changes staged; intent published; file published; cache removed; intent removed |
| Item deletion | Changes staged; intent published; file removed; cache removed; intent removed |
| Comment deletion | Changes staged; intent published; metadata published; intent removed |
| Folder move/rename | Intent published; tree withdrawn; tree published; intent removed |
| Empty-folder deletion | Intent published; tree withdrawn; intent removed |
| Unpacked import | Tree staged; intent published; tree published; intent removed |

Reopening and repeated recovery yield the old state before commit or the complete new state after commit.
Identity, original bytes, creation dates, and retained comments survive.
A separate conflicting-rename case preserves foreign destination bytes, the committed intent, and exact staged preimages.
Recovery also rejects a nonempty tree described as an empty-folder deletion.
Case-only item/folder names, collisions, cycles, and description-only folder deletion are covered.
`LibraryNameTests` (2026-11-14) covers folded collisions (`Straße`/`STRASSE`, `σ`/`ς`, U+1C80/`в`, `ﬀ`/`ff`) for
folder creation, import suffixes, renames, and moves on the case-insensitive temporary volume and on a freshly
attached case-sensitive APFS disk image, and existing folded duplicates as listing issues. Before the fix, the
case-sensitive volume accepted both names, and on the case-insensitive volume a folded `folder-create` committed an
intent that failed with `EEXIST`, leaving the library unable to open until the operation was quarantined.
A one-off sweep of every BMP scalar and every case-mapped supplementary scalar on a case-insensitive APFS image
found 200 pairs APFS equates that lowercasing distinguished, 14 that Foundation folding alone distinguished, and
none for the adopted key.
`failedExportWrite` (2026-11-14) exports under a 16-byte file-size limit in the storage test driver: the write
fails with `EFBIG` and no file remains; before the fix the partial file stayed and blocked the next export.
`LibraryFinderMetadataTests` (2026-11-14) writes `.DS_Store` files into every library, operation, and cache
directory at every write phase of folder creation, import, comments, renames, item and folder moves, replacement,
item and empty-folder deletion, unpacking, and cache cleanup, and replays interrupted folder moves and deletions
after those files appear, change, or disappear, including an intent that records a `.DS_Store` member. Before the
fix, a `.DS_Store` in `operations/` or in an operation directory blocked opening with `RECOVERY_REQUIRED`, Finder
writes during an operation forced recovery, and a folder holding only a `.DS_Store` could not become a library.
Non-regular objects named `.DS_Store` remain listing issues.

## Maintenance and asset admission

Tests verify dry-run immutability, applied selections, orphaned native manifests, obsolete identities,
unknown-manifest protection, item-cache invalidation, and refusal before deletion when caches contain unsafe aliases or shared inodes.
Cache results disclose selected files and directories.
Usage tests verify separate categories, shared-inode deduplication, optional assets, and visible unsafe-path issues.

Asset tests verify canonical release identities, complete inventories, hashes, supported profiles,
atlas dimensions, and physical packed-frame bounds. Tampered bytes, unknown members,
symlinks, shared file inodes, incompatible profiles/densities, and out-of-bounds frames are refused.
Synthetic non-image bytes deliberately pass a structurally valid inventory, proving this is not image decoding.

Two implementation regressions were found and corrected during verification:

- Root book unpacking accidentally validated a path with an empty trailing component. The sparse-book and CLI tests now cover the corrected root-path construction.
- Atlas validation initially compared logical frame geometry with physical atlas dimensions. The retained source defines `pw`/`ph` as packed sizes; a regression test and the real 1x/2x release now pass using those sizes.

## Review and remaining limits

Manual review covered path confinement, bounded input, kernel ownership, journal validation,
exclusive publication, cache/asset boundaries, source preservation, and structured error/output handling.
Inputs are not interpolated into executed shell commands. No external dependency or secret was introduced.
No additional security scanner was installed or run; the repository has no adopted scanner command.

Library/item format remains version 1; new file/tree intents use version 2 alongside version 1 replay.
See the [storage contract](../contracts/Storage.md) for synchronization and work limits.
Process-kill coverage does not establish power-loss durability or concurrent external-edit support.
Unpublished operations staging remains preserved; cache cleanup never discards recovery evidence.
Allocated usage is an inode-based estimate, not an APFS clone-sharing measurement or guaranteed reclaim figure.
Asset verification does not decode images, render previews, or perform complete semantic validation of prototype statistics.
The 1,000-root workload, renderer lifecycle, statistics integration, and native UI remain separate work.
