# Bounded native codec validation

Native decoding preserves exact originals and supports lossless selected-entry exports.
This checkpoint completes codec admission, without qualifying persistent library operations.

Recorded: 2026-11-13, using the [foundation environment](Native-Foundation.md#environment).
The foundation was committed separately as `f0389ab` before codec implementation began.

## Completed checks

| Check | Result |
| --- | --- |
| `just test` | All 21 native tests pass across three suites |
| `just tools-check` | Fixture provenance and independent source boundaries remain valid |
| Relocated isolation check | Fresh build, all 21 tests, and both executables pass without Node, network, or original checkouts |

`just codec-test` passes 16 focused tests:

- **Preserve supplied originals:** all nine TXT files decode and export byte-for-byte.
- **Keep surrounding whitespace:** CRLF, spaces, and boundary BOMs remain in root exports.
- **Select sparse entries:** actual stored indices control navigation and standalone exports.
- **Retain unknown content:** wrapper fields, nested values, large integers, and precise decimals survive export.
- **Keep distinct keys:** canonically equivalent Unicode keys retain distinct scalar sequences.
- **Read both planners:** minimal payloads and explicit empty settings descriptions remain valid.
- **Reject bad transport:** malformed UTF-8 and noncanonical base64 fail admission.
- **Enforce zlib framing:** truncation, checksum damage, raw DEFLATE, gzip, and trailing streams fail.
- **Bound byte allocation:** exact byte boundaries and a compressed oversized payload are exercised.
- **Bound JSON structure:** depth and node budgets also apply to unknown subtrees.
- **Bound whole documents:** entry and entity/tile totals apply across book contents.
- **Check nesting boundaries:** 32 book levels pass; the next level fails.
- **Export the large leaf:** entry `[1, 1]` retains all 6,814 entities and its complete body.
- **Reject malformed shapes:** ambiguous roots, duplicate indices, invalid labels, and nonfinite positions fail.
- **Reject invalid JSON:** duplicate keys, malformed escapes, isolated surrogates, and trailing values fail.
- **Check integer semantics:** exponent notation, negative zero, safe boundaries, and invalid configurations are exercised.

Tests construct synthetic source strings using independent one-shot zlib compression.
The production codec uses streaming operations instead.
The gzip rejection vector was generated separately using Python's gzip encoder.
Supplied fixtures and their frozen inventory remain unchanged.

## Security boundaries

Manual review covered input encoding, framing, recursion, numeric conversion, and output limits.
The codec enforces a finite schema-independent JSON budget before downstream use.
Duplicate keys cannot hide overwritten fields.
Unexpected numeric precision cannot round an invalid version or index into validity.
Errors use controlled descriptions, without embedding private source text.
The codec adds no filesystem, networking, or code-execution interface.

No external dependency or additional scanning tool was installed for this checkpoint.
The codec uses Apple's SDK-provided zlib module.

## Remaining work

Metadata schemas, bounded filesystem reads, ownership exclusion, and journaled publication remain pending.
So do persistent comments, CLI library commands, and interrupted-operation recovery.
No native image painting or power-loss durability is established by these codec tests.
