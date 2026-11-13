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
Redirect it to a file when needed.
Build messages and recipe diagnostics stay on stderr.

Book entry comments and standalone exports accept `--entry 5.0`.
Numbers are actual stored indices, not displayed row numbers.
The path must exist in the saved book.
Omit `--entry` for the root.

Import can select an existing real folder with `--folder "Smelting"`.
Close all library owners before creating or organizing directories in Finder.
Folder creation, move/rename, replacement, deletion, and unpacking commands are not available yet.

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
See the [storage contract](../contracts/Native-Storage.md) before investigating interrupted operations.

## Structured results

Successful commands, except help and export, return one JSON object on stdout.
The envelope fields are `schema: 1`, `ok: true`, `command`, and `result`.
Lists include `folders`, usable `items`, and `issues` for excluded malformed content.
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

`release` reports the available capabilities and native format version without opening a library.
Raw exports preserve their separate byte-oriented protocol.

## Verification

Run focused storage checks:

```sh
just storage-test
```

The test driver is package test support, with no failure-injection flags in the ordinary CLI.
See [storage validation](../validation/Native-Storage.md) for completed checks and limitations.
