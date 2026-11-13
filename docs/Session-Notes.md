# Resume native implementation

The owner approved the [native plan](planning/Native-macOS-Plan.md) on 2026-11-13.
Milestone 1's independent foundation is implemented and validated.
The bounded native codec is implemented, with [focused validation](validation/Native-Codec.md).
Minimal storage and CLI workflows are implemented, with [process-interruption evidence](validation/Native-Storage.md).
The owner then prioritized [complete library commands](validation/Native-Library-Commands.md) before renderer feasibility; those are implemented.
The standalone [native renderer harness](validation/Native-Renderer.md) now paints real images through a supervised helper.
The renderer checkpoint is committed as `75aec1c`; [owned library previews and caches](validation/Native-Library-Previews.md) are implemented next.
Milestone 1 is [accepted](validation/Native-Milestone-1.md): all criteria re-verified on `8daa40e` and the representative images approved by the owner.

## Current state

- **Build native targets:** three shared libraries, CLI, and planner probe compile.
- **Preserve supplied fixtures:** all nine TXT inputs retain their original hashes.
- **Decode native strings:** bounded parsing preserves unknown fields and exact original exports.
- **Own native libraries:** permanent kernel leases exclude competing app/CLI sessions.
- **Publish recoverably:** version 1 import/comment intents and version 2 file/tree mutations retain hashed staged evidence.
- **Organize sources:** folder/item moves and renames, empty-folder and item deletion, replacement, unpacking, and comment deletion are available.
- **Maintain offline:** bounded usage, scoped cache cleanup, and independent asset-release verification are available.
- **Reuse planner source:** system JavaScriptCore executes the locally bundled fpsr planner.
- **Paint previews:** Core Graphics handles ordered sprites, shadows, wires, icons, and planner labels; Image I/O decodes atlases and encodes PNGs.
- **Supervise helpers:** deadlines, cancellation, sampled memory limits, and parent-death lifelines are tested.
- **Retain ownership:** POSIX launch explicitly hands the shared kernel lease to bound workers; close cancels/drains jobs.
- **Reuse derived previews:** complete cache metadata binds identities, PNG bytes, and stored reports without changing source metadata.
- **Keep tooling local:** preparation sources, dependency locks, and notices live here.
- **Keep artwork private:** copied sprites and prototype data remain ignored.
- **Read the evidence:** [foundation validation](validation/Native-Foundation.md) records checks and limitations.

The CLI includes all original library command capabilities except deliberately excluded backup/restore.
Native cache identities differ from historical web caches; unknown formats are protected by scoped cleanup.
The preview probe renders standalone source files and selected book leaves with verified private assets.
Saved-item preview and cache integration are available through `fb-native preview`.
Application scheduling, the macOS UI, and native statistics remain pending.

## Next implementation

Continue the complete-core milestone with the native construction-statistics port using the retained reference cases.
Keep application scheduling/progress/retry and UI work separate from the completed library preview command.
Preserve inherited kernel ownership, sticky cancellation, and owner-only cache publication.
Connected-rail/full-corpus review (milestone 4) and workload measurements remain outstanding.

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
Use `just renderer-test` for composition, complete jobs, and helper lifecycle checks.
Use `just preview --help` and the [preview guide](development/Native-Preview.md) for rendering commands.
Use the [library preview guide](development/Native-Library-Previews.md) for saved-item reuse and refresh.
Use `just library --help` for available native commands.
