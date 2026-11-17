# Blueprint codec

Decode Factorio strings without rewriting their originals or dropping unknown JSON content.
The codec lives in `LibraryCore` and requires no private game assets.

## Public interface

| Interface | Behavior |
| --- | --- |
| `BlueprintCodec.decode(_:limits:)` | Validate source bytes and return an immutable document |
| `BlueprintDocument.original` | Retain original bytes and their SHA-256 hash |
| `BlueprintDocument.root` | Expose the validated root entry and generic JSON tree |
| `BlueprintDocument.entry(at:)` | Select by actual stored book indices |
| `BlueprintDocument.export(at:)` | Return exact root bytes or generate a standalone selected entry |
| `BlueprintCodecLimits` | Lower individual admission budgets without exceeding supported ceilings |
| `BlueprintCodecError` | Distinguish invalid input, exceeded budgets, invalid paths, and compression failures |

An empty entry path identifies the root.
An internal path such as `[5, 0]` follows stored indices, independently of array positions.
Invalid paths fail without selecting a different entry.

The [CLI](Library-CLI.md) uses these interfaces for imports and exports.

## Input admission

The codec accepts format `0`, canonical base64, and one complete zlib-wrapped stream.
It rejects raw DEFLATE, gzip, missing checksums, damaged streams, and trailing stream data.
Source text and decompressed JSON must both contain valid UTF-8.
Surrounding source whitespace and a boundary BOM are ignored for decoding only.
An initial UTF-8 BOM is also accepted in decompressed JSON.

Streaming decompression checks output size before appending beyond the budget.
JSON parsing checks depth and node counts while constructing the tree.
The parser rejects duplicate keys, invalid escapes, malformed numbers, and trailing JSON values.

| Budget | Supported ceiling |
| --- | --- |
| Original source | 16 MiB, including whitespace |
| Decompressed JSON | 64 MiB |
| JSON value depth | 128, with root depth zero |
| Book entry depth | 32, with root depth zero |
| Entries | 10,000, including the root |
| Entities and tiles | 100,000 across the entire document |
| JSON values | 1,000,000, excluding object keys |

Limits can be lowered to nonnegative values for constrained callers and tests.
Raising them requires an explicit supported-budget change.
Callers reading files must also bound reads before constructing their input `Data`.

Each entry must contain exactly one recognized kind and a nonnegative safe-integer version.
Book indices must be unique nonnegative safe integers within each book.
Blueprint entities and tiles require textual names and finite numeric positions.
Planner payloads may be minimal versioned objects.
Unknown prototypes remain admissible; rendering and statistics determine their support separately.

## Content preservation

Root export returns the original TXT bytes, including whitespace and line endings.
It never serializes the parsed tree back over the source.

Selected-entry export creates a fresh format-0 string using system zlib.
It removes that entry's enclosing-book `index` and preserves other wrapper fields.
Nested books retain their descendants' indices and source order.
The resulting compressed bytes can differ from other valid encoders.

The generic tree preserves unknown fields, object order, and numeric tokens.
Large integers and precise decimal tokens never pass through `Double` during export.
Known integer fields receive exact range and integrality checks.
Known coordinate fields must convert to finite numbers.

Object lookup and equality compare UTF-8 sequences without Unicode normalization.
Consequently, canonically equivalent but distinct JSON keys remain distinct.
Export may change JSON string escapes while preserving their scalar sequences.
JSON serialization and compression also enforce their respective byte budgets.

The implementation uses the SDK's existing `zlib` module.
The [zlib manual](https://zlib.net/manual.html) documents its framing and stream-completion APIs.
No new package dependency or runtime service was added.

## Verification

Run the focused tests from the repository root:

```sh
just codec-test
```

Run all checks with `just test`.
See [codec validation](../validation/Codec.md) for completed cases and limitations.
