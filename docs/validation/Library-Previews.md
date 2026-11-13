# Owned library preview validation

Saved-item rendering now retains kernel ownership and publishes validated derived caches through the storage owner.
The standalone renderer checkpoint was committed as `75aec1c` before this work began.
Recorded: 2026-11-13 in the [foundation environment](Foundation.md#environment).

## Completed checks

| Check | Result |
| --- | --- |
| `just test` | 80 native tests across ten suites and four Python assembly tests pass |
| Relocated isolation | Fresh build and all 80 native tests pass with original checkouts unreadable, networking denied, and no Node on PATH |
| Focused integration/lifecycle run | All 11 library-preview and six supervisor tests pass |
| `just tools-check` | All 153 copied files, 42 planner inputs, and five pinned development dependencies remain valid |
| `just planner-check` | Committed JavaScript resource matches pinned local inputs |
| Real CLI workflow | Miss → hit → explicit refresh, selected large-book entry reuse, and unchanged authoritative bytes pass |
| `git diff --check` | Pass |

The isolation command is `python3 tools/check-independence.py --deny-path /Users/aklo/Projects/fb`.
It runs outside the enclosing tool sandbox so it can apply its own restrictive policy.
No external dependency, database, CI change, or artwork resource was added.
The new C test target is test support, not a shipped runtime dependency.

## Kernel lifetime and close

Tests establish:

- A bound render excludes a second owner and serializes with library operations.
- Library close cancels and reaps a deliberately blocked renderer before releasing its owner.
- Cancellation before launch remains effective and starts no child.
- A deliberately noncooperating helper retains the real flock lease after its parent is killed.
  A new owner remains refused until that helper is terminated.
- An unrelated descriptor deliberately lacking close-on-exec does not survive the launch allowlist.
- A worker descendant that retains the lease but closes its output pipes is still terminated by process-group cleanup.
- Existing timeout, memory-limit, cancellation, crash, framing/size, and parent-death tests continue to pass after replacing Foundation launch with explicit POSIX descriptor handoff.

Process observation peeks without reaping, preserving the leader PID until group shutdown.
Normal preview requests expose no library path, source/cache write descriptor, or mutation callback to the worker.
The dedicated descriptor retains only the kernel lock lifetime; this is not a hostile-code sandbox claim.

## Cache correctness and interruption

Tests verify complete image/report hashes, valid cache hits with no worker executable present,
distinct settings and sparse-entry identities, explicit refresh, known-image corruption repair,
future-metadata preservation, scoped obsolete cleanup, and source replacement/deletion invalidation.
Moves/names/comments remain independent from rendering identity when source bytes do not change.
Cache aliases and asset/library overlap are rejected before starting a worker or publishing derived files.

Four helper-process cases kill the owner with `SIGKILL` after:

1. Image staging.
2. Metadata staging.
3. PNG publication.
4. Metadata publication.

Reopening preserves exact TXT and authoritative JSON bytes.
Before complete publication, the next request regenerates the derived entry; after complete publication, it reuses it.
Abandoned temporary files remain safely classifiable by existing maintenance commands.
No authoritative journal is introduced for cache writes.

The CLI returns schema 1 JSON metadata with a cache-relative image path and no base64 PNG payload.
It reports available library rendering in `release`; missing required options retain the existing argument-error protocol.
Rendering failures use stable `PREVIEW_*` codes and exit 8, with invalid preview content/options using exit 7.

## Real asset/source workflow

The workflow ran through `just library` against a generated `.cache/Preview-Library` and the private verified release.

| Request | Observed owner duration |
| --- | --- |
| RS first render | ~2.97 s |
| RS validated reuse | ~1.34 s |
| RS explicit refresh | ~3.16 s |
| 6,814-entity book leaf, first render | ~10.46 s |
| Same selected leaf, validated reuse | ~2.81 s |

These debug-build measurements include parent asset verification, source selection, validation, and publication;
they are broader than the standalone worker timings recorded in [renderer validation](Renderer.md).
Cache hits still validate complete sources/assets and decode the PNG. They are not indexing-cache latency measurements.
The large leaf retains its explicit warning for eight unsupported `ee-infinity-loader` entities.
Exact RS source/metadata bytes remained unchanged across first render, reuse, and refresh.
Default abandoned cleanup selected no completed cache files.

## Review and remaining qualification

Manual review covered descriptor ownership, close/cancellation ordering, PID/PGID reuse,
bounded framing and cache bytes, strict metadata versions, source revalidation, image/report hash binding,
alias refusal, exclusive/checked replacement, and source/asset separation.
No additional security scanner was installed or run.
Tests operate on generated temporary libraries or the task's ignored demo library, never a real user library.

The [contract](../contracts/Preview-Cache.md) and [usage guide](../development/Library-Previews.md) describe the implemented boundary.
Native statistics, application scheduling/progress/retry, cache quotas, the macOS UI,
owner visual approval, connected-rail/full-corpus image review, and the 1,000-root workload remain pending.
Process termination tests do not establish hardware power-loss durability.
Concurrent external file edits and hostile helpers remain unsupported.
