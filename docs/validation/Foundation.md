# Independent foundation validation

The native scaffold builds without access to the original web project.
This evidence covers the first foundation checkpoint, not complete milestone 1 acceptance.
The subsequent [codec checkpoint](Codec.md) adds native admission and selected-entry export.
The [storage checkpoint](Storage.md) adds persistent libraries, CLI commands, and interrupted-operation recovery.

Recorded: 2026-11-13.

## Environment

| Component | Recorded value |
| --- | --- |
| Host | macOS 27.2, build 26B5091g, ARM64 |
| Xcode | 27.2, build 27B52 |
| Swift | 6.4.2 |
| Package deployment target | macOS 27.0 |
| Node / npm | 24.22.1 / 12.2.1 |
| just | 1.54.0 |
| Private asset profile | Official Factorio 2.1.23, schema 2 |
| Prototype map | Matching 2.1.23, schema 1 |

## Completed checks

| Check | Result |
| --- | --- |
| `just build` | Native libraries and both executables compile |
| `just test` at the foundation checkpoint | Five Swift tests pass across two suites |
| `just release` | CLI reports only the implemented release-information capability |
| `just planner-test` | Pinned planner executes through system JavaScriptCore |
| `just tools-install` | Locked development dependencies install with lifecycle scripts disabled |
| `just tools-check` | 153 copied files match recorded hashes; five direct dependencies are pinned |
| `just planner-check` | Committed bundle matches 42 local inputs; no external imports remain |
| `just assets-check` | Vendored pipeline imports; no game process starts |
| `just statistics-test` | All 13 retained statistics reference cases pass |
| npm dependency audit | No known vulnerabilities reported for the locked tooling graph |

The nine supplied TXT fixtures match their frozen byte counts and SHA-256 hashes.
Whitespace and line-ending tests confirm that original bytes remain distinct.
The source wrapper is not yet a Factorio codec or persistent library implementation.

The planner tests load independent JavaScriptCore contexts.
They plan empty upgrade/deconstruction diagrams and check finite bounds.
The contexts expose neither Node globals nor network API bridges.
No native image is painted by these tests.

Private asset verification checked all 446 manifest members against hashes and lengths.
The copied prototype map's version matches the sprite bundle.
This establishes input integrity, not rendered-image correctness.
Git ignore checks confirm that private assets, installed tools, and build output remain untracked.

## Isolation check

The isolation script copies only the Swift package, sources, tests, and Swift wrapper.
It creates a temporary checkout and uses a fresh compiler cache.
The sandbox denies networking and reads from both original project directories.
Its restricted PATH contains no Node executable.

From the project root, run:

```sh
python3 tools/check-independence.py --deny-path ../fb
```

At this checkpoint, the relocated build passed all five tests and ran both native executables.
The [codec checkpoint](Codec.md) extends this isolation check to all 21 native tests.
The script removes only its own temporary checkout afterward.
This check uses macOS `sandbox-exec` as a development qualification tool.
It does not define the finished application's sandbox or distribution design.

## Remaining qualification

Native codec admission was subsequently implemented and validated separately.
Storage ownership, journaled publication, and process-interruption recovery were subsequently implemented and validated separately.
So do worker deadlines, image composition, caching, and UI workflows.
Asset regeneration and game-reference generation have not been rerun.
No image approval, performance qualification, or power-loss durability claim is made.
