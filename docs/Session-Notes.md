# Resume native implementation

The owner approved the [native plan](planning/Native-macOS-Plan.md) on 2026-11-13.
Milestone 1's independent foundation is implemented and validated.
The bounded native codec is implemented, with [focused validation](validation/Native-Codec.md).
The complete milestone remains in progress.

## Current state

- **Build native targets:** three shared libraries, CLI, and planner probe compile.
- **Preserve supplied fixtures:** all nine TXT inputs retain their original hashes.
- **Decode native strings:** bounded parsing preserves unknown fields and exact original exports.
- **Reuse planner source:** system JavaScriptCore executes the locally bundled fpsr planner.
- **Keep tooling local:** preparation sources, dependency locks, and notices live here.
- **Keep artwork private:** copied sprites and prototype data remain ignored.
- **Read the evidence:** [foundation validation](validation/Native-Foundation.md) records checks and limitations.

The CLI currently supports help and release information only.
The preview probe plans empty diagrams; it does not paint images.
Library commands and app UI are not implemented.

## Next implementation

Define native metadata and the minimal recoverable TXT/JSON publication protocol.
Add real ownership exclusion, exact-byte import/export, comments, and interruption tests.
Continue renderer feasibility with real assets after those storage boundaries exist.

Retain original bytes, sparse entry indices, and unknown blueprint fields.
Application-managed backup and restore remain outside v1.
Neither builds nor runtime should depend on the original web checkout.

Run `just --list` for available commands.
Use `just build`, `just test`, and `just planner-test` for native checks.
Use `just codec-test` for focused codec admission and export checks.
