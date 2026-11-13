# Resume native implementation

The owner approved the [native plan](planning/Native-macOS-Plan.md) on 2026-11-13.
Milestone 1's independent foundation is implemented and validated.
The bounded native codec is implemented, with [focused validation](validation/Native-Codec.md).
Minimal storage and CLI workflows are implemented, with [process-interruption evidence](validation/Native-Storage.md).
The owner then prioritized [complete library commands](validation/Native-Library-Commands.md) before renderer feasibility; those are implemented.
The complete milestone remains in progress.

## Current state

- **Build native targets:** three shared libraries, CLI, and planner probe compile.
- **Preserve supplied fixtures:** all nine TXT inputs retain their original hashes.
- **Decode native strings:** bounded parsing preserves unknown fields and exact original exports.
- **Own native libraries:** permanent kernel leases exclude competing app/CLI sessions.
- **Publish recoverably:** version 1 import/comment intents and version 2 file/tree mutations retain hashed staged evidence.
- **Organize sources:** folder/item moves and renames, empty-folder and item deletion, replacement, unpacking, and comment deletion are available.
- **Maintain offline:** bounded usage, scoped cache cleanup, and independent asset-release verification are available.
- **Reuse planner source:** system JavaScriptCore executes the locally bundled fpsr planner.
- **Keep tooling local:** preparation sources, dependency locks, and notices live here.
- **Keep artwork private:** copied sprites and prototype data remain ignored.
- **Read the evidence:** [foundation validation](validation/Native-Foundation.md) records checks and limitations.

The CLI includes all original library command capabilities except deliberately excluded backup/restore.
Native cache identities differ from historical web caches; unknown formats are protected by scoped cleanup.
The preview probe plans empty diagrams; it does not paint images.
The macOS UI, native statistics integration, and renderer production are not implemented.

## Next implementation

Continue renderer feasibility using the independent JavaScriptCore planner and private local assets.
Implement real Core Graphics composition, bounded helper jobs, and independently decoded image probes.
Cover representative blueprints and both planner kinds before full UI work.

Preserve the [native storage contract](contracts/Native-Storage.md) when integrating rendering.
Helpers must not retain write access after ownership is released.
Unpublished staging remains preserved; automatic cleanup is deferred.
Listings currently validate full sources; large-library performance is not qualified.

Retain original bytes, sparse entry indices, and unknown blueprint fields.
Application-managed backup and restore remain outside v1.
Neither builds nor runtime should depend on the original web checkout.

Run `just --list` for available commands.
Use `just build`, `just test`, and `just planner-test` for native checks.
Use `just codec-test` for focused codec admission and export checks.
Use `just storage-test` for metadata, exclusion, CLI, and crash-recovery checks.
Use `just asset-test` for inventory/profile/hash and packed-frame admission checks.
Use `just library --help` for available native commands.
