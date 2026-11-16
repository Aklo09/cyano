# Native macOS port: roadmap and first milestone

Date: 2026-11-13. Status: approved by the owner; milestones 1, 2, 3, and 4 are accepted.
Based on the [initial assessment](macOS-Assessment.md), with the scope decisions recorded below.

## Progress

- [x] Independent Swift package, fixture preservation, local preparation tooling, and build/test commands.
- [x] Planner resource executes through system JavaScriptCore without Node or private assets.
- [x] Relocated native build passes with original checkouts unreadable and networking denied.
- [x] Bounded native codec, exact-byte root exports, and selected-entry exports preserving unknown content.
- [x] Native metadata, exclusive ownership, minimal CLI library operations, and process-interruption recovery.
- [x] Complete library commands: organization, replacement, deletion, unpacking, cache maintenance, usage, and offline asset verification.
- [x] Standalone real-image renderer feasibility, bounded native workers, process deadlines, and independent PNG decoding.
- [x] Library-bound helper lease retention, close/cancellation, and owned derived-cache publication/reuse.
- [x] Owner visual approval and complete milestone 1 acceptance ([acceptance record](../validation/Milestone-1.md)).
- [x] Core revisions after milestone 1 review ([decisions](Core-Revisions.md)).
- [x] Native construction statistics: contract, strict prototype map, calculator, reference parity, library/CLI integration, and measurements ([validation](../validation/Statistics.md)).
- [x] Milestone 2 acceptance ([acceptance record](../validation/Milestone-2.md)).
- [x] Milestone 4 acceptance: approved by the owner on 2026-11-16 ([acceptance record](../validation/Milestone-4.md)).

See [foundation validation](../validation/Foundation.md) for evidence and limitations.
The [codec validation](../validation/Codec.md) records the next completed checkpoint.
The [storage validation](../validation/Storage.md) records native ownership and publication evidence.
The [command validation](../validation/Library-Commands.md) records the owner's requested organization/maintenance checkpoint before renderer work.
Milestone 2 is [accepted](../validation/Milestone-2.md). Milestone 3 is [accepted](../validation/Milestone-3.md). Milestone 4, rendering integration, is [accepted](../validation/Milestone-4.md) (2026-11-16).
The [renderer validation](../validation/Renderer.md) records the standalone painter/worker checkpoint.
The [library preview validation](../validation/Library-Previews.md) records the subsequent ownership/cache integration.
Power-loss durability and the full workload qualification remain separate acceptance work.

## Summary

Build an independent macOS application for managing a personal Factorio blueprint library, using SwiftUI, a shared Swift storage core, and a standalone CLI.

Target this Apple Silicon Mac first. Preserve the useful workflows and data-safety guarantees of `fb`, while adopting native navigation and controls.

The first milestone delivers a CLI and preview harness that prove storage, recovery, and renderer feasibility. It does not include the application UI.

**Excluded from v1:** application-managed backup/restore (deleted and replaced originals go to the macOS Trash instead), web-store migration, cloud synchronization, network libraries, mods, Intel qualification, App Store submission, and public distribution packaging. A closed library can be copied with ordinary filesystem tools.

## Architecture and independence

- **LibraryCore:** blueprint decoding, validation, filesystem storage, comments, organization, ownership, and interrupted-operation recovery. No dependency on SwiftUI or rendering.
- **FactorioData:** versioned asset and prototype-map loading, compatibility checks, and construction statistics.
- **PreviewRenderer:** planner bridge, native composition, worker lifecycle, and derived-result caching.
- **Executables:** `fb-native` for library operations and separate preview harness/worker products.
- **Application:** SwiftUI navigation and editing, with AppKit for file panels and image inspection.

Use a Swift package for shared code, executables, and tests. Add an Xcode application target when UI work begins.

Reuse fpsr planning through system [JavaScriptCore](https://developer.apple.com/documentation/javascriptcore), then paint through Core Graphics and encode PNGs through [Image I/O](https://developer.apple.com/documentation/imageio/cgimagedestination). This is the first approach to qualify; alternative renderers require a revised plan if it fails.

Make this repository self-contained:

- Copy the supplied blueprint fixtures unchanged, relevant reference cases, asset-preparation scripts, and supporting source.
- Preserve provenance, pinned revisions, licenses, and notices.
- Establish project-owned dependency locks and reproducible planner bundling.
- Replace references to the old repository and temporary upstream checkout.
- Copy the required prepared assets and prototype map into ignored private storage here.
- Retain Node tooling for preparation and development only. Shipped Swift executables must run without Node, network access, or a running game.

## Delivery roadmap

| Milestone | Deliverable | Exit condition |
| --- | --- | --- |
| **1. Foundation and feasibility** | Independent toolchain, minimal library CLI, recovery protocol, JavaScriptCore/Core Graphics preview harness | Storage and representative real images pass the checks below |
| **2. Complete library core** | Replacement, folder/item organization, unpacked-book import, deletion, maintenance, and statistics | Shared operations preserve identities, comments, originals, and recovery guarantees |
| **3. Native application** | Library selection, browsing, nested books, import/export, comments, organization, and image viewport | Everyday workflows work offline, including without renderer assets |
| **4. Rendering integration** | Cache identity, cancellation, retry, and render warnings; entry icons in list rows and the inspector, icons for Factorio rich-text tags in names and for statistics items, and planet icons in the private release (owner decisions, 2026-11-14 and 2026-11-15); copying and saving preview images. Thumbnails, visible-item scheduling, and bounded queues were dropped (2026-11-15) | Full supplied corpus receives native rendering and visual qualification |
| **5. Personal-use qualification** | App/CLI installation, lifecycle handling, documentation, and workload measurements | The 1,000-root library and 149-leaf book meet recorded native acceptance targets |

Do not carry forward the assessment's full-rewrite estimate as a delivery commitment. Re-estimate after milestone 1 establishes renderer reuse costs.

## Milestone 1: implementation specification

### Independent foundation

Create the Swift package, focused test targets, development commands, and documentation entry points. Record the actual Xcode, Swift, macOS, architecture, asset profile, and dependency revisions used.

Use the existing official Factorio 2.1.23 asset profile initially. Preserve the original assessment as historical analysis; the new plan records the changed scope.

### Minimal library and CLI

Use the assessment's ordinary-directory layout: explicit native format marker, permanent ownership lock, adjacent TXT/JSON pairs under `library/`, and separate operational staging and disposable caches.

Implement these CLI capabilities:

- Initialize an empty native library.
- Import TXT bytes, list saved roots, and add a root or selected-entry comment.
- Export an original root exactly; export a selected nested entry as a standalone string.
- Inspect ownership without activating the library.
- Recover an interrupted operation under exclusive ownership.

Keep UUIDs, source hashes, dates, display-name overrides, and comments in strictly versioned metadata. Address book entries by their actual stored indices. Preserve unknown blueprint fields; typed projections must not discard them during entry export.

Carry forward the existing codec admission limits: 16 MiB source, 64 MiB decompressed JSON, depth 128, book depth 32, 10,000 entries, 100,000 entities/tiles, and one million JSON nodes.

Define a native versioned JSON result envelope and stable error categories. Raw exports write only source bytes to stdout; diagnostics go to stderr.

### Ownership and recovery

Require nonblocking kernel ownership for ordinary library reads and writes. Reject unsupported formats, unsafe paths, symlinks within managed content, and nonempty unknown libraries.

Serialize complete operations, including suspension points.

For the initial import protocol:

1. Stage validated source and metadata on the library filesystem.
2. Synchronize staged files.
3. Publish a versioned recovery intent containing destinations and expected hashes.
4. Publish the file pair and synchronize affected directories.
5. Remove the completed journal after publication is durable.

The published intent commits the operation to roll forward. Before that point, no library item is visible. Recovery is repeatable; unexpected destination bytes block recovery and remain preserved.

Comments use checked atomic sidecar replacement. Synchronization failures prevent success reporting. Explicitly document file flushing and directory synchronization; process-interruption tests do not establish power-loss guarantees. [Apple's durability reference](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html) distinguishes `fsync` from stronger drive-flush requests.

### Preview feasibility harness

Bundle the pinned planner into JavaScript suitable for JavaScriptCore. Supply decoded documents and immutable render data; transfer complete draw lists rather than individual drawing callbacks.

Implement the draw commands required by the representative corpus, including sprite transforms, ordering, shadows, wires, icons, text, and planner diagrams. Unsupported commands produce explicit failures or warnings.

Run planning and painting in a helper process with one active job and a 60-second execution deadline. The owner validates results and publishes caches. Helpers receive no library mutation interface; library-bound helpers retain the ownership lease until exit.

Measure startup, planning, bridge transfer, painting, PNG encoding, peak memory, and cancellation separately.

**Gate:** if planner execution, asset decoding, required composition, or worker termination fails qualification, record the evidence and revise the renderer approach before milestone 2 expands implementation.

## Acceptance and validation

Milestone 1 passes when:

- Given an empty directory, initialization creates a recognizable native library; unknown nonempty directories remain unchanged.
- Given TXT containing CRLF and surrounding whitespace, import → comment → close → reopen → export produces identical bytes.
- Given sparse nested entry indices and unknown fields, selection and standalone export preserve their meaning.
- Given competing processes or path aliases, only one acquires ownership; refusal changes no library content.
- Given termination at every import publication boundary, reopening either exposes the complete committed item or preserves the pre-commit state.
- Given conflicting recovery bytes, recovery stops without overwriting evidence.
- Given missing assets, source operations still succeed.
- Given RS, rails/wires, nested upgrade and deconstruction planners, and the 6,814-entity leaf, the harness produces independently decoded PNGs within the deadline.
- Representative images receive separate visual review for layering, connections, transparency, and clipping.
- Timeout, cancellation, worker crash, and parent termination leave no surviving writer outside ownership.
- With `~/Projects/fb` unavailable, project builds use only this repository and declared dependencies; prepared executables run offline without Node.

Use focused Swift tests, subprocess interruption tests, and real-image probes. Record measured results and limitations separately from source inspection and visual approval.
