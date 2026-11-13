# Core revisions after milestone 1

Date: 2026-11-13. Status: approved by the owner; implementation in progress.
These decisions come from the review of the accepted milestone 1 work ([acceptance record](../validation/Native-Milestone-1.md)).
They change the [storage](../contracts/Native-Storage.md) and [preview cache](../contracts/Native-Preview-Cache.md) contracts
and precede milestone 2, because milestones 3–5 build on the affected interfaces.

## Measurements that motivated the review

Release build, local APFS, throwaway library in temporary storage:

| Workload | Result |
| --- | --- |
| `list`, 858 small roots plus ten 260 KB books | 2.5–3.0 s |
| `comment` on one item in that library | 0.67 s |
| `list` after adding thirty 696 KB `v0.59.0.txt` books | 11.9 s |
| `import` of one small root (debug build) | ~41 ms |
| `import-unpacked` of the 182-leaf `v0.59.0.txt` book (debug build) | 3.6 s |

`v0.59.0.txt` is an outlier; real libraries hold mostly small roots.
Listing cost is dominated by decoding every saved blueprint (92% of samples in `BoundedJSONParser`),
and ID-addressed operations read every item metadata file. Both grow with the number of items, not their size.

## Decisions

| # | Previous decision | Revised decision |
| --- | --- | --- |
| D1 | Listing decodes and validates every saved source; ID lookup scans all metadata | Listing reads metadata and checks source size and hash; a disposable index under `cache/` keyed by source hash supplies kind and label; ID lookup uses the index and falls back to a scan. Sources decode only when an item is opened |
| D2 | A library render holds the serial queue for its whole duration | Snapshot the source and identity on the queue, render off the queue, then revalidate the source hash and publish on the queue |
| D3 | The worker inherits the owner lease on descriptor 3 | The worker receives no lease: it never reads or writes library files. Only the owner publishes |
| D4 | Delete and replace erase originals permanently; no backup in v1 | After a delete or replace commits, its exact staged preimages move to the macOS Trash as one folder per item; backup/restore stays out of v1 |
| D5 | A conflicting intent blocks opening with no supported resolution; unpublished staging is kept forever and counts toward 128 operations | `recover --quarantine <operation>` moves a refused operation, unchanged, to `operations-quarantine/`; `staging-cleanup` removes unpublished staging, which never changed the library |
| D6 | Every staged and cache file gets `F_FULLFSYNC`; directory renames get `fsync` only | Files and directories get `fsync`; one `F_FULLFSYNC` barrier follows the intent commit and one follows publication; disposable cache files get no drive flush. Measure before and after |
| D7 | Folder moves hash every contained file, capped at 256 MiB and 100,000 members | Moves record the folder's filesystem identity and member inventory without content hashes; creation and deletion keep content hashes |
| D8 | Duplicate IDs report `notFound`; unpacking keeps no link to the original book; the worker inherits the full environment | Duplicate IDs report a distinct `AMBIGUOUS_ID`; unpacked leaves remain re-encoded standalone strings without the book, recorded as intended; the worker starts with an empty environment |

## Order and verification

Each revision is one commit that updates its contract, tests, and code together.

1. D3: remove the worker lease. Lifecycle tests drop lease-inheritance assertions and keep reaping, cancellation, and close behavior.
2. D2: three-phase rendering. New tests show library operations completing while a render is in flight, and a source change during rendering preventing publication.
3. D6: durability barriers. Interruption tests stay green; import and unpack timings are recorded.
4. D5: quarantine and staging cleanup. Tests cover a conflicting intent that becomes openable after quarantine with evidence intact, and cleanup that never touches committed intents.
5. D4: Trash for removed originals. Tests cover delete and replace leaving byte-identical preimages in a Trash-equivalent destination.
6. D7: identity-based folder moves. Tests cover moving a folder above the former content cap and replaying an interrupted move.
7. D1: metadata listing and index. Tests cover stale and missing index entries, corrupted sources reported on open, and listing timings at 1,000 roots.
8. D8: smaller items.

Every step runs `just lint` and `just test`; D1, D2, and D6 also record release-build timings.
