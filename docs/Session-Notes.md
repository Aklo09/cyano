# Resume native implementation

The owner approved the [native plan](planning/macOS-Plan.md) on 2026-11-13.
Milestone 1 is [accepted](validation/Milestone-1.md): all criteria re-verified on `8daa40e` and the representative
images approved by the owner. The approved [core revisions](planning/Core-Revisions.md) that followed are implemented.
Milestone 2 is [accepted](validation/Milestone-2.md), including native construction statistics approved by the owner.

## Current state

- **Build native targets:** shared libraries, the CLI, the preview worker, and the planner probe compile.
- **Preserve supplied fixtures:** all nine TXT inputs retain their original hashes.
- **Decode native strings:** bounded parsing preserves unknown fields and exact original exports.
- **Own native libraries:** permanent kernel leases exclude competing app/CLI sessions.
- **Publish recoverably:** intents commit behind a drive barrier; replay rolls forward; refused operations can be
  quarantined; uncommitted staging can be cleaned up.
- **Organize sources:** folder/item moves and renames, empty-folder and item deletion, replacement, unpacking, and
  comment deletion are available. Deleted and replaced originals go to the Trash.
- **List quickly:** listing reads metadata and source hashes with a derived kind index; ID lookups use an
  in-session index. 888 roots list in 0.24 s in a release build.
- **Maintain offline:** bounded usage, scoped cache cleanup, and independent asset-release verification are available.
- **Paint previews:** JavaScriptCore runs the bundled fpsr planner; Core Graphics paints and Image I/O encodes PNGs.
- **Supervise helpers:** workers get only stdin/stdout/stderr and an empty environment, never the lease; deadlines,
  cancellation, memory limits, and parent-death lifelines are tested. Rendering runs off the library queue.
- **Reuse derived previews:** cache metadata binds identities, PNG bytes, and reports without changing source metadata.
- **Calculate statistics:** construction requirements and game-tile footprints for one blueprint entry, from a
  strictly loaded prototype map bound to a verified release; 0 differences from the reference on 348 cases.
- **Keep tooling local:** preparation sources, dependency locks, and notices live here.
- **Keep artwork private:** copied sprites, prototype data, and outputs derived from them stay in ignored directories.

The CLI includes all original library command capabilities except deliberately excluded backup/restore.
Native cache identities differ from historical web caches; unknown formats are protected by scoped cleanup.
Application scheduling and the macOS UI remain pending.

## Next implementation

Milestone 3, the native macOS application, is being planned. Resume here (stopped 2026-11-13):

1. The [milestone 3 draft](planning/Milestone-3.md) lists 18 subtasks (A1–A18) and seven open decisions,
   each with a recommendation. The owner asked to clarify the decisions before choosing; start by asking
   what they want to clarify, then record their choices in the draft and mark it approved.
2. Then start with A1 (app spec, product-manager role) and A2 (screen specs, ux-designer role).

Keep application scheduling/progress/retry and UI work separate from the completed library commands.
Preserve sticky cancellation, worker isolation, and owner-only cache publication.
Connected-rail/full-corpus review (milestone 4), the 1,000-root workload targets, and power-loss qualification
remain outstanding.

Preserve the [storage contract](contracts/Storage.md) and [statistics contract](contracts/Statistics.md).
Retain original bytes, sparse entry indices, and unknown blueprint fields.
Application-managed backup and restore remain outside v1.
Neither builds nor runtime should depend on the original web checkout.
Strict conformance with the original web application is not required: prefer better native behavior and record the
difference in the relevant contract.

Run `just --list` for available commands.
Use `just build`, `just lint`, and `just test` for native checks.
Use `just codec-test`, `just storage-test`, `just asset-test`, and `just renderer-test` for focused suites.
Use the [preview guide](development/Preview.md) and [library preview guide](development/Library-Previews.md) for rendering,
and the [statistics guide](development/Statistics.md) for statistics and their reference tooling.
