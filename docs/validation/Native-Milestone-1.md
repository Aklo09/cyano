# Milestone 1 acceptance

Milestone 1 (foundation and feasibility) is accepted.
Every criterion in the [native plan](../planning/Native-macOS-Plan.md#acceptance-and-validation) was re-verified on commit `8daa40e`,
after the swift-format reformat (`a337ee1`), and the owner approved the representative images.
Recorded: 2026-11-13 in the [foundation environment](Native-Foundation.md#environment).

## Final checks on `8daa40e`

| Check | Result |
| --- | --- |
| `just build` | Pass |
| `just lint` | Strict swift-format lint reports no findings |
| `just test` | 80 native tests across ten suites and four Python assembly tests pass |
| Relocated isolation | Build, tests, and executables pass with the original checkout unreadable, networking denied, and no Node on PATH |
| `just tools-check` | All 153 copied files, 42 planner inputs, and five pinned development dependencies remain valid |
| `just planner-check` | Committed JavaScript resource matches its 42 pinned local inputs |
| `just planner-test` | Planner self-test passes through system JavaScriptCore |
| `just assets-check` | Local asset pipeline imports without launching the game |
| `just library assets-verify .cache/renderer-assets` | Private release verifies |

The isolation command is `python3 tools/check-independence.py --deny-path /Users/aklo/Projects/fb`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Empty directory initializes; unknown nonempty directories stay unchanged | [Storage validation](Native-Storage.md); `just test` |
| CRLF and surrounding whitespace survive import → comment → close → reopen → export | [Codec](Native-Codec.md) and [storage](Native-Storage.md) validation; `just test` |
| Sparse nested indices and unknown fields keep their meaning on selection and export | [Codec validation](Native-Codec.md); `just test` |
| Competing processes and path aliases: one owner, refusal changes nothing | [Storage validation](Native-Storage.md); `just test` |
| Termination at every import publication boundary is recoverable | [Storage validation](Native-Storage.md); `just test` |
| Conflicting recovery bytes stop recovery without overwriting evidence | [Storage validation](Native-Storage.md); `just test` |
| Source operations succeed without assets | [Renderer validation](Native-Renderer.md); `just test` |
| RS, rails/wires, both planners, and the 6,814-entity leaf render decodable PNGs within the deadline | Representative renders below |
| Representative images reviewed for layering, connections, transparency, and clipping | Owner approval below |
| Timeout, cancellation, worker crash, and parent termination leave no writer outside ownership | [Renderer](Native-Renderer.md) and [library preview](Native-Library-Previews.md) validation; `just test` |
| Builds use only this repository; prepared executables run offline without Node | Relocated isolation above |

## Representative renders

Rendered from `8daa40e` with the verified private release into ignored `.cache/m1-acceptance/`.
All seven PNGs are byte-identical to the pre-reformat review renders in `.cache/renderer-review/`.

| Input / entry | Output | Worker peak RSS | Warnings |
| --- | --- | --- | --- |
| `RS.txt`, root, 2x | 256 × 256 | ~79 MiB | None |
| `RS.txt`, root, 1x | 256 × 256 | ~83 MiB | None |
| `bp.txt`, `1.1`, 2x | 1664 × 1568 | ~212 MiB | None |
| `v0.59.0.txt`, `2.0` upgrade planner | 608 × 224 | ~119 MiB | None |
| `v0.59.0.txt`, `29.12` deconstruction planner | 512 × 192 | ~117 MiB | None |
| `v0.59.0.txt`, `1.1`, 6,814-entity leaf | 2048 × 810 | ~341 MiB | `Unsupported entity: ee-infinity-loader (8)` (mod entity, official-only profile) |
| Elevated-rail fixture, `0`, checkerboard | 1103 × 2048 | ~265 MiB | None |

## Owner visual approval

On 2026-11-13 the owner reviewed the seven images above for layering, connections, transparency, and clipping, and approved them.
This approves the representative set; it is not pixel parity with the game renderer.

## Carried forward

These are outside milestone 1 by the plan's roadmap:

- Full-corpus visual qualification, including connected-rail seams (milestone 4).
- Native construction statistics (milestone 2).
- The 1,000-root workload targets and power-loss durability (milestone 5 and separate acceptance work).
- The macOS application (milestone 3).
