# Storage checkpoint validation

Libraries now preserve originals and comments through ownership conflicts and interrupted publication.
This checkpoint implements the minimal milestone 1 storage workflow, without completing renderer acceptance.

Recorded: 2026-11-13, in the [foundation environment](Foundation.md#environment).
Library format, item metadata, and journal versions are `1`.
The codec checkpoint was committed as `0f9b777` before storage implementation began.

## Completed checks

| Check | Result |
| --- | --- |
| `just storage-test` | All 14 storage tests pass |
| `just test` | All 35 tests pass across four suites |
| `just tools-check` | Local source boundaries and 153 copied-file hashes remain valid |
| Relocated isolation check | Fresh build and all 35 tests pass with both original checkouts and networking denied |
| CLI wrapper workflow | Paths with spaces, JSON results, comments, recovery, and byte-exact stdout export pass |

The C shim only exposes the SDK's `flock` function without its Swift name collision.
No external package dependency, runtime service, or artwork dependency was added.

## Storage and metadata

- **Round-trip originals:** import → comment → close → reopen → export preserves CRLF and surrounding whitespace.
- **Keep identities:** item UUIDs, creation dates, source hashes, and comments survive reopening.
- **Address book entries:** scoped comments and exports use actual stored indices.
- **Export the large leaf:** a 6,814-entity entry remains a complete standalone blueprint.
- **Keep real folders:** empty directories appear in listings; imports can select existing folders.
- **Handle collisions:** case and Unicode-normalization collisions receive separate filenames.
- **Reject foreign roots:** nonempty unknown directories and bare foreign locks remain untouched.
- **Reject future data:** unsupported marker/sidecar versions and unknown fields are not rewritten.
- **Report corruption:** damaged source hashes exclude unusable items with visible listing issues.
- **Bound inputs:** oversized files are refused before full reads; unsafe source objects do not block.

## Ownership and concurrency

A separate helper process holds a real kernel lease while the tests exercise competing access.
A second open, CLI listing, and symlink-alias open are refused.
Read-only owner probing remains available.
Terminating the owner releases kernel exclusion without deleting a lockfile.

Replacing a live lock inode causes refusal in the existing session.
An existing library with a missing lock never recreates it.
Symlinks, hardlinks, FIFOs, and traversal attempts are refused.
External targets behind refused symlinks remain untouched.

Eight concurrent comment requests complete through one library object.
All eight comments remain present, with the original item identity and creation date.
Close is idempotent; operations after close fail.

## Actual process interruptions

The test helper kills itself with `SIGKILL` at publication boundaries.
It is separate from the ordinary CLI and uses a testing SPI.

| Operation | Interruption points | Result after reopening |
| --- | --- | --- |
| Initialization | Marker published | Same library identity; empty managed directories become available |
| Import before commit | Source staged; metadata staged | No live item; unpublished staging preserved |
| Import after commit | Intent published; source published; metadata published; intent removed | Exactly one complete item with original bytes |
| Comment | Metadata staged; intent published; metadata published; intent removed | Original or complete updated comments, according to the commit point |

Repeated recovery and reopening retain the same visible result.
Changing published TXT bytes after interruption causes an integrity refusal.
The conflicting live bytes, staged original, and recovery intent remain intact.

## Evidence boundaries

### Encoded NUL regression

- **Symptom:** a URL containing `%00` passed the initial path-admission assertion.
- **Cause:** legacy `URL.path` retained the encoded token, hiding the decoded NUL from that check.
- **Evidence:** a minimal Foundation probe reproduced the difference between legacy and fully decoded paths.
- **Fix:** admission inspects `path(percentEncoded: false)` before filesystem access.
- **Coverage:** initialization, ownership probing, source reads, and directory construction share this validator.

The regression assertion was retained and verified with the complete storage suite and isolation check.

### Remaining qualification

These tests establish process-interruption behavior on the recorded local APFS host.
They do not establish crash-proof power-loss durability.
The implementation requests file synchronization and drive flushing; hardware-loss testing remains separate.
Other APFS case variants, synchronized stores, network filesystems, and Intel hardware are unqualified.

Listings currently validate whole sources instead of using an indexing cache.
The multi-operation large-book storage test takes roughly 16–18 seconds in debug builds.
This is test wall time, not a single-command latency benchmark.
The 1,000-root latency and memory targets remain unqualified.

Unpublished staging is preserved; automated cleanup is deferred to maintenance work.
Replacement, organization mutations, deletion, unpacking, and cache maintenance were pending at this checkpoint;
the subsequent [command checkpoint](Library-Commands.md) implements them. Statistics integration remains pending.
No image painting, renderer-worker lifecycle, or macOS UI is qualified here.
