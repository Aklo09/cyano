# Native macOS port assessment

Keep libraries portable and fully usable offline through a native macOS application.

Date: 2026-11-12. Baseline: source release `v0.0.3` and the current implementation.
Status: assessment and proposed direction; no native implementation or contract changes are approved here.
Existing [contracts](../README.md#agreed-contracts) remain authoritative for the web application.
The owner confirmed that the web application has only held test data.
Existing web stores, snapshots, operational state, and CLI protocols require no native compatibility.

## Recommendation

Build a shared Swift library core, a SwiftUI application, and a standalone Swift CLI.
Use AppKit selectively for file panels, desktop interactions, and image viewing.
Evaluate reusable planners and native helpers before committing to a complete renderer rewrite.
Use Core Graphics for an initial native compositor; evaluate Metal against measured workloads.
Keep renderer planning separate from painting and application UI.

Preserve adjacent TXT/JSON files, real folders, and independently verifiable native backups.
Design new metadata, journal, ownership, and backup formats where they simplify native implementation.
Keep originals independent from previews, statistics, assets, and application availability.
The UI can adopt standard macOS controls without reproducing browser layout.

This is a fresh native implementation preserving useful behavioral guarantees.
Existing storage logic and fixtures provide design references, without requiring protocol compatibility.

## Contracts to retain or adapt

| Existing contract | Native treatment |
| --- | --- |
| [Storage](../contracts/Storage-Layout.md) | Retain exact originals, adjacent sidecars, UUIDs, real folders, bounded input, and interruption safety. Native schemas and recovery protocols can change. |
| [Backups](../contracts/Backups.md) | Retain complete inventories, hashes, safe publication, and independent verification. Define a native backup format. |
| [Restoration](../contracts/Restoration.md) | Retain fresh targets, guarded activation, and deliberate interrupted-restore handling. Simplify the native state machine where possible. |
| [Ownership](../contracts/Ownership-and-Shutdown.md) | Retain kernel exclusion and safe shutdown. Define native controls without Node domain compatibility. |
| [Cache maintenance](../contracts/Cache-Maintenance.md) | Retain dry-run scopes, confinement, revalidation, bounded scans, and byte-accounting distinctions. |
| [Statistics](../contracts/Statistics-and-Footprint.md) | Retain saved-source requirements, quality grouping, building rectangles, and incomplete-result warnings. |
| [Rendering](../contracts/Renderer-Evaluation.md) | Retain local rendering, explicit support scope, planner diagrams, warnings, and source independence. Replace implementation-specific dependencies. |
| [Application](../contracts/Application-Integration.md) | Retain user workflows and entry addressing. Replace routes, forms, cookies, and browser-specific interactions. |
| [Resource limits](../contracts/Resource-Limits.md) | Retain workloads and bounded scheduling. Establish new native measurements and hardware targets. |
| [Release compatibility](../contracts/Release-Compatibility.md) | Version native formats and assets explicitly. Define future native upgrades separately from historical web releases. |

Basic authentication, HTTPS proxying, CSRF checks, and HTTP health routes serve deployment-specific needs.
A local-only application needs no equivalent HTTP service.
Docker packaging and server operational procedures remain relevant only to the existing web deployment.
Use application preferences for display choices currently stored in cookies.
Keep preferences outside authoritative library sidecars.

## Filesystem layout

Let users choose an ordinary library directory on supported local APFS storage.
Keep its contents visible and understandable in Finder.
Avoid introducing a database as the authoritative source or an opaque document archive.

```text
Chosen Library/
  .library-format.json
  .owner.lock
  library/
    Smelting/
      Iron Smelting.txt
      Iron Smelting.json
    Unpacked Book/
      .folder.json
      5 - Blueprint.txt
      5 - Blueprint.json
  cache/
    <stable-item-id>/
  operations/
```

The chosen directory contains both user-visible content and private operational directories.
The proposed `.library-format.json` identifies the native format and supported version.
It prevents accidental treatment of a web store as a native library.
Operational filenames remain design choices, rather than compatibility commitments.
Keep transactional staging on the library filesystem for atomic publication.
Keeping `cache/` alongside it is convenient, but native caches could use system storage instead.
Private immutable assets and portable backups can live separately.

- **Preserve imported bytes:** read TXT files as bytes and retain whitespace and line endings.
- **Export original bytes:** root exports read saved TXT files without re-encoding JSON.
- **Preserve metadata meaning:** retain stable UUIDs, comments, actual entry paths, dates, and source hashes.
- **Preserve real folders:** retain empty directories and unpacked-book `.folder.json` descriptions.
- **Keep journals durable:** interrupted operations can hold authoritative originals under `operations/`.
- **Keep caches disposable:** deleting derived images must never remove source or recovery information.
- **Keep portable naming:** define normalization, collision keys, UTF-8 limits, and case-only rename behavior explicitly.
- **Reject unsafe paths:** retain symlink checks, traversal rejection, and filesystem-domain admission.

Finder visibility does not authorize concurrent editing while an application owns the store.
Retain the current stop-before-external-edits rule.
Network stores and synchronized folders need separate qualification before admission.
An APFS filesystem check alone does not establish safe cloud synchronization.

## Swift core and offline operations

Both meanings of offline matter: disconnected operation and maintenance without launching the app.

| Proposed component | Responsibility |
| --- | --- |
| `LibraryCore` | Codec, validation, metadata, scanning, operations, ownership, journals, backups, restore, maintenance. |
| `FactorioData` | Versioned prototype maps, asset descriptors, requirements, footprints, and support warnings. |
| `PreviewRenderer` | Planning and painting interface, bounded jobs, cancellation, and versioned derived results. |
| macOS application | Native navigation, editing controls, clipboard, file selection, progress, and image inspection. |
| Standalone CLI | Offline operations using the same core and a documented native result protocol. |

These are proposed boundaries, not implemented package names or commands.

Offline operations should include import, unpack, export, organization, comments, and source replacement.
Also retain owner inspection, recovery, usage, cleanup, backup verification, and guarded restoration.
Define clear CLI results, failure categories, and exit codes without reproducing the Node protocol.
Keep exact-byte stdout exports and diagnostic commands independent from store activation.

The application normally retains ownership until closing its library.
Separate CLI store commands then report ownership conflicts, including reads and exports.
Independent backup verification and read-only status probes retain their exceptions.
In-app backup actions can execute through the owning core's serialized operation queue.
They must pause conflicting work and preserve snapshot consistency.

Browsing, saving, exporting, and maintenance must work without renderer assets.
Rendering and complete statistics require compatible local assets and prototype data.
After asset preparation, ordinary runtime needs neither network access nor a running Factorio process.
Ship UI resources locally; avoid making first launch depend on downloads.

## Storage implementation risks

Use the current persistence logic to identify failure cases and required guarantees.
Implement a smaller native protocol without interpreting historical web journals or restore markers.
Its implementation includes [storage](../../src/lib/server/storage/library.ts), [ownership](../../runtime/ownership.mjs),
[backup](../../runtime/backup.mjs), and [restore](../../runtime/restore.mjs) modules.

- **Use Darwin primitives:** use nonblocking `flock`, descriptor checks, exclusive creation, and atomic renames appropriately.
- **Sync durable boundaries:** synchronize files and parent directories throughout publication and recovery.
- **Serialize complete operations:** Swift actors alone do not prevent interleaving across suspension points.
- **Bound decoding:** retain strict base64, zlib framing, UTF-8 validation, and decompression limits.
- **Preserve unknown content:** generic blueprint JSON must retain fields outside the app's typed projections.
- **Validate metadata strictly:** default Codable decoding must not silently accept unsupported fields or versions.
- **Define native serialization:** specify deterministic checksums without reproducing JavaScript object order or JSON encoding.
- **Version recovery state:** use native journals and restore guards with documented publication points.
- **Test naming behavior:** cover normalization, case comparison, numeric limits, and filename byte counts on APFS.
- **Retain failure evidence:** unknown live bytes and conflicting journals remain preserved for investigation.

Ordinary atomic file writes do not make a TXT/JSON pair transactional.
Choose an explicit commit point and make every interrupted phase recoverable.
This remains necessary even with entirely new metadata and journal schemas.
Factorio strings still require their zlib wrapper format; raw DEFLATE is insufficient.
Native compressors can produce different valid standalone-entry strings; exact root bytes remain mandatory.

Apple distinguishes `fsync` from stronger `F_FULLFSYNC` drive-flush requests.
Choose and measure the native durability policy explicitly.
Do not claim power-loss guarantees from process-interruption tests alone.
See Apple's [fsync reference](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html).

## Rendering and renderer reuse

The installed dependency is `@rickyzhangca/fpsr@0.0.3`, rather than `fprs`.
Its [worker integration](../../runtime/render-worker.mjs) uses several distinct capabilities:

1. Decode blueprint documents and select blueprint or planner entries.
2. Resolve Factorio-specific components against a sprite database.
3. Plan positions, orientations, connections, layers, and visual bounds.
4. Paint sprites and overlays, then encode transparent PNG output.
5. Draw upgrade and deconstruction planner configuration diagrams.

Factorio version display also uses fpsr's packed-version decoder.
Replacing that small helper is straightforward compared with replacing render planning.

The [construction calculator](../../runtime/blueprint-statistics.mjs) is already separate and pure.
Port it with the matching prototype map and existing reference fixtures.
Do not derive construction quantities or building footprints from renderer sprite bounds.

### Native painting choices

| Approach | Assessment |
| --- | --- |
| Core Graphics bitmap compositor | Recommended starting point for capped, cached previews. Implement atlas crops, transforms, alpha, ordering, and PNG encoding. Benchmark representative leaves. |
| Metal compositor | Consider for measured drawing bottlenecks or a future interactive scene viewer. It still needs Factorio planning, texture management, and offscreen image export. |
| SwiftUI Canvas | Suitable for small diagrams. Keep heavy preview generation outside the UI view lifecycle. |
| AppKit image viewport | Display cached images with native pan, zoom, fit, and background controls. Independent from the image generator. |

SwiftUI can embed AppKit views through [NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable).
Metal supports [offscreen rendering passes](https://developer.apple.com/documentation/metal/customizing-render-pass-setup).
Neither API provides Factorio prototype resolution or connection rules.

Existing measurements show PNG encoding can exceed painting time.
The [native benchmark](../validation/Renderer-macOS-Validation.md#initial-resource-measurements) records that distinction.
Therefore, GPU adoption does not establish a faster end-to-end preview pipeline.
The current renderer explicitly disables GPU output for its approved pixel hashes.
Native output needs new image and visual acceptance; those hashes are not portable requirements.

Retain meaningful visual structure, readable planners, warnings, and complete source preservation.
Pixel equality with the browser interface is unnecessary.
If preview simplification is acceptable, define omissions explicitly before reducing renderer scope.

### Renderer alternatives: source review, 2026-11-12

Evaluate reuse before assuming that fpsr needs complete replacement.
Distinguish reusable helper executables from code suitable for translation into Swift.
Both can support a native interface and offline operation.

The following revisions were inspected through GitHub source and repository metadata.
Commit dates describe inspected revisions, without establishing support or image correctness.

| Candidate | Inspected revision | Commit date |
| --- | --- | --- |
| [fpsr](https://github.com/rickyzhangca/fpsr/tree/2f7dc70f2681de530402556f757006e904e692d5) | `2f7dc70f2681de530402556f757006e904e692d5` | 2026-07-21 |
| [Factorio-FBSR upstream](https://github.com/demodude4u/Factorio-FBSR/tree/2f0c698a9b92d02192e9e54c0c66c2ae59fcddad) | `2f0c698a9b92d02192e9e54c0c66c2ae59fcddad` | 2025-10-08 |
| [Factorio-FBSR perfectsine fork](https://github.com/perfectsine/Factorio-FBSR/tree/18d0b6a268b1434351ab9eaf0eae6ef805fc2ef2) | `18d0b6a268b1434351ab9eaf0eae6ef805fc2ef2` | 2026-10-26 |
| [factorio-scanner](https://github.com/fgardt/factorio-scanner/tree/361bb762f799cf57bad201dbcb7ab5d0ac3d4b1f) | `361bb762f799cf57bad201dbcb7ab5d0ac3d4b1f` | 2026-10-07 |

| Approach | Native integration | Principal limitation | Initial position |
| --- | --- | --- | --- |
| fpsr planner through JavaScriptCore, Swift compositor | System JavaScript engine plus Core Graphics; no Node runtime required in the proposed design. | Requires bundling, engine compatibility, bridge-cost measurement, and a new compositor. | Prototype first. |
| factorio-scanner helper | Compiled Rust executable; a C interface could follow after qualification. | Target-version alignment, offline loader changes, and missing planner previews. | Strong native-binary alternative. |
| FBSR helper | Java 21/Java2D with a bundled runtime and local asset profiles. | JVM packaging, dependency extraction, and unproven current-profile acceptance. | Evaluate as a complete backend. |
| Full Swift renderer | Native planning and composition under application control. | Reimplements Factorio-specific rules and carries the largest engineering cost. | Retain as the rewrite baseline. |

#### fpsr: reuse planning before rewriting it

The [planner entry point](https://github.com/rickyzhangca/fpsr/blob/2f7dc70f2681de530402556f757006e904e692d5/packages/renderer/src/planner.ts) exports resolution and blueprint/planner draw-list generation.
The [draw-list type](https://github.com/rickyzhangca/fpsr/blob/2f7dc70f2681de530402556f757006e904e692d5/packages/renderer/src/types/draw-list.ts) defines ordered, JSON-serializable drawing commands and bounds.
Commands describe sprites, wires, rectangles, icons, text, snap grids, and train couplings.

A conservative static import walk covered 44 files, including type imports and re-exports.
Fetched file lengths were checked against the pinned GitHub tree.
The walk found no external module imports or unresolved relative imports.
It found no Node or DOM runtime dependency in that graph.
Timing hooks handle unavailable Performance APIs and fall back to `Date.now()`.
This supports a portability hypothesis; it does not prove JavaScriptCore execution.

Apple's [JavaScriptCore framework](https://developer.apple.com/documentation/javascriptcore) executes JavaScript from Swift.
Bundle the planner as ordinary JavaScript, supplying decoded blueprint JSON and the render database.
Receive its draw list and execute commands through a Swift compositor.
Keep file access, asset decoding, original-byte preservation, and cache publication in native code.
Avoid bridging individual draw calls; transfer the complete bounded draw list instead.
Measure copying, serialization, peak memory, and supported JavaScript features on the minimum macOS version.
Retain helper-process isolation where deadlines require terminating synchronous planning.

This approach can remove Node and skia-canvas without immediately translating Factorio planning logic.
It also retains existing upgrade/deconstruction planner planning and the current asset pipeline.
Successful planner execution still leaves native painting and visual acceptance to implement.

#### FBSR: viable helper candidate, substantial Swift translation

The [upstream Maven configuration](https://github.com/demodude4u/Factorio-FBSR/blob/2f0c698a9b92d02192e9e54c0c66c2ae59fcddad/FactorioBlueprintStringRenderer/pom.xml) targets Java 21.
It includes FactorioDataWrapper, bot/reporting dependencies, web-service components, and an image codec.
A desktop helper should expose only rendering and exclude unrelated services where practical.

Its [renderable abstraction](https://github.com/demodude4u/Factorio-FBSR/blob/2f0c698a9b92d02192e9e54c0c66c2ae59fcddad/FactorioBlueprintStringRenderer/src/com/demod/fbsr/map/MapRenderable.java) invokes Java2D directly.
Sprite composition and entity factories depend on Java classes and prototype wrappers.
This is a less direct Swift-compositor boundary than fpsr's declarative draw list.
That comparison is an architectural inference, rather than a measured porting result.

Its vanilla profile includes base, Space Age, Quality, and Elevated Rails.
Source includes elevated-rail factories, quality handling, transparency options, and bounded image dimensions.
These establish implemented mechanisms, without qualifying the project's exact Factorio 2.1.23 corpus.
The render API consumes `BSBlueprint`; decoding planner objects does not establish planner image support.
No equivalent planner-image entry point was established during this review.

The [profile implementation](https://github.com/demodude4u/Factorio-FBSR/blob/2f0c698a9b92d02192e9e54c0c66c2ae59fcddad/FactorioBlueprintStringRenderer/src/com/demod/fbsr/Profile.java) loads prepared asset files independently from asset-building steps.
That makes offline execution from prepared profiles plausible.
Test it with networking denied, no running game, and an isolated configuration.
Use a local process protocol rather than shipping bot integrations or an HTTP server.
Java permits self-contained runtime packaging; [Oracle's packaging guide](https://docs.oracle.com/en/java/javase/21/jpackage/packaging-overview.html) describes that mechanism.
macOS ARM64 startup, image codecs, cold memory, and shutdown still need qualification.

The perfectsine fork is another candidate, with packaging and dependency changes in its inspected revision.
Its Maven configuration also targets Java 21, despite its README listing Java 11.
Evaluate each pinned revision separately; fork identity does not establish interchangeable behavior.
Do not choose a revision solely because its last commit is newer.

#### factorio-scanner: native packaging with integration work

Rust permits a compiled renderer helper without a separate Node or Java runtime.
Its [CI configuration](https://github.com/fgardt/factorio-scanner/blob/361bb762f799cf57bad201dbcb7ab5d0ac3d4b1f/.github/workflows/rust.yml) includes Intel and Apple Silicon macOS build targets.
Configured targets do not establish successful rendering on either architecture.

The [prototype crate](https://github.com/fgardt/factorio-scanner/blob/361bb762f799cf57bad201dbcb7ab5d0ac3d4b1f/prototypes/Cargo.toml) targets Factorio 2.1.21.
Its top-level README still describes the 2.0 port as work in progress.
Therefore, inspect code and corpus behavior rather than relying solely on that README.
The project also explicitly withholds stability guarantees.

The [scanner documentation](https://github.com/fgardt/factorio-scanner/blob/361bb762f799cf57bad201dbcb7ab5d0ac3d4b1f/scanner/README.md) describes limited Alt mode and absent upgrade/deconstruction planner rendering.
Native planner diagrams would need separate implementation or another backend.
The [loader source](https://github.com/fgardt/factorio-scanner/blob/361bb762f799cf57bad201dbcb7ab5d0ac3d4b1f/scanner/src/lib.rs) requests an exact targeted base-game version.
The current 2.1.23 profile therefore needs target alignment and fresh compatibility checks.

The stock loader can resolve/download mods and invoke Factorio for prototype dumps.
Providing a dump does not bypass all mod-resolution work.
The stock CLI also checks for a Factorio executable before rendering.
A strict offline application should construct prepared data separately and call the rendering layer directly.
Use immutable local prototypes and sprites, with missing prerequisites reported instead of downloaded automatically.
Keep preparation isolated from the user's ordinary game settings and mod directory.

Start with a helper executable before considering an in-process C interface.
This simplifies deadline enforcement and keeps crashes away from authoritative storage.
Actual image support, memory, and timing remain unmeasured for our corpus.

#### Selection gates

Prototype JavaScriptCore planner reuse and scanner integration before choosing a full rewrite.
Use FBSR as an additional complete-backend candidate when a bundled Java runtime is acceptable.
No candidate replaces the saved-source statistics contract automatically.
Keep the existing pure calculator's semantics and reference fixtures independent from rendering.

- **Pin each candidate:** record source revision, dependencies, runtime, assets, game version, and architecture.
- **Prove offline operation:** deny network access and prevent game execution after preparation.
- **Protect the library:** keep renderer helpers unable to alter originals, sidecars, or recovery state.
- **Cover representative content:** include RS, rails, wires, quality, tiles, Space Age, nested books, and planners.
- **Check unsupported content:** retain visible warnings and incomplete results without corrupting source data.
- **Measure the pipeline:** separate startup, planning, painting, encoding, peak memory, and bridge overhead.
- **Exercise large inputs:** include the 6,814-entity leaf and the 149-leaf large-book workload.
- **Validate actual images:** independently decode PNGs and inspect layering, connections, transparency, and clipping.
- **Keep evidence separate:** source inspection and successful builds do not prove correct rendered pixels.

This review downloaded source into memory and inspected repository metadata.
It installed no candidate dependencies and executed no candidate renderer.
No new images, macOS builds, benchmark results, or visual approvals were produced.

### Asset preparation is a separate dependency

Replacing runtime painting does not replace the asset exporter automatically.
The [existing builder](../../tools/renderer-evaluation/build-assets.mjs) invokes pinned upstream fpsr pipeline code.
It prepares a licensed game's isolated dump, distilled sprite definitions, and packed atlases.
The prototype-map generator also depends on matching engine reference data.

Initially, keep existing private bundles and exporter tooling if native consumers can read them.
Validate database semantics and image decoding before committing to format reuse.
This permits a Node-free application runtime while retaining external build-time tooling.
A completely Node-free preparation workflow requires additional exporter work.
The full-rewrite estimates below assume exporter reuse, not its complete replacement.
Alternative backends need their own prepared assets and cannot assume fpsr bundle compatibility.

Private artwork remains separate from distributable source and application resources.
Current source-release approval does not qualify a new distributed native binary.
The existing [distribution review](../validation/License-Compliance.md) records that boundary.

### Isolation and cache identity

Use a bounded native helper process when rendering needs enforceable deadlines or crash isolation.
Swift task cancellation requires cooperation and cannot stop arbitrary synchronous work.
An initial proposal lets helpers receive source bytes and read immutable assets only.
The owning application validates results and publishes all store cache writes.
Such helpers must have no surviving ability to modify the store.
Document helper lifetimes and cache publication in the native ownership contract.
Any helper writing store files must instead retain exclusion throughout its writing lifetime.

Keep cache keys based on source hash, entry path, generator settings, and asset identity.
Give the native generator a new fingerprint; never reuse fpsr identity for changed output.
Retain bounded scheduling, persisted failures, explicit retry, and source-independent availability.

## macOS access and distribution

Prefer a directly distributed, signed application for the initial filesystem-and-CLI workflow.
Sandboxing remains possible but adds persistent permissions and helper-access design.
This recommendation does not settle final distribution requirements.

Sandboxed applications use user-selected folders and security-scoped bookmarks for persistent access.
Library, asset, and backup locations can require separate selections.
Handle revoked permissions and stale bookmarks without altering stored data.
A standalone CLI needs its own access design; GUI permission does not automatically authorize it.
Apple documents these mechanisms in [sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

Choose the minimum supported macOS version and processor scope during the initial prototype.
Existing native evidence covers macOS ARM64, not a new Swift application or Intel Macs.

## Fresh libraries and native acceptance

Existing data compatibility is outside scope, following the owner's clarification.
The web application has only run against test data.
No web-store migration, historical backup reader, or bidirectional CLI acceptance is required.

Create fresh native libraries with explicit native format identification.
Refuse nonempty unknown stores; do not silently reinterpret their control files or sidecars.
Users can import ordinary Factorio TXT strings through the native import workflow.
Importing those strings creates new native metadata without transferring web application state.

The native application and CLI must agree on their own formats and exclusion protocol.
Standalone native tools must verify and restore backups without the GUI or asset bundle.
Choose a documented, accessible snapshot format rather than preserving the web manifest schema.
Format versioning protects future native upgrades; historical web rollback matrices do not apply.

Native qualification should include:

- **Verify native snapshots:** standalone verification detects corruption, missing members, and incomplete publication.
- **Restore native snapshots:** fresh-target restoration preserves exact originals, sidecars, hierarchy, and empty folders.
- **Check native mutations:** app and CLI preserve comments, identities, dates, and replacement semantics.
- **Check unsupported formats:** native readers refuse unknown versions without silently changing stored bytes.
- **Exercise durable interruptions:** test publication boundaries, replacements, unpacking, deletion, restore resume, and discard.
- **Exercise process exclusion:** app versus CLI, aliases, second app, crashes, and surviving writers.
- **Exercise native filesystems:** qualify case-sensitive and case-insensitive APFS naming and target collisions.
- **Separate evidence types:** metadata validation, image decoding, statistics, and visual approval remain distinct.

Keep supplied blueprint strings and historical examples unchanged.
Use expected source behavior and statistics as fixtures, without adopting web storage formats.
Retain the 1,000-root workload and 149-leaf large book for new native performance qualification.

## Proposed delivery and effort

Estimates assume one experienced full-time developer with Swift and graphics experience.
They cover the current official profile and behavioral scope, without matching interface pixels.
They assume access to a Mac, licensed local assets, and existing exporter tooling.
They exclude legacy data compatibility, new game profiles, mods, cloud sync, and exporter replacement.
These are engineering estimates, not measured delivery commitments.
They describe the full native-planner rewrite scenario.
Successful planner or backend reuse could reduce effort; quantify savings after the renderer prototype.
The source review above does not establish a replacement implementation schedule.

| Phase | Deliverable | Estimated effort |
| --- | --- | --- |
| 1 | Native format design, codec, APFS ownership probe, and renderer-reuse comparison. | 1–2 weeks |
| 2 | Shared storage core, native recovery, maintenance CLI, backup, restore, and interruption fixtures. | 3–5 weeks |
| 3 | Native browsing, books, import/export, comments, replacement, organization, and image viewport. | 3–5 weeks |
| 4 | Native resolver/planner/compositor, planner diagrams, asset integration, and image acceptance. | 6–12 weeks |
| 5 | Performance qualification, packaging, permissions, lifecycle, and documentation. | 1–3 weeks |

Sequential total: approximately 14–27 engineer-weeks, or roughly three to six months.
A useful source-and-maintenance application without native sprite previews could arrive after phases 1–3.
That earlier milestone represents approximately 7–12 weeks, with deferred image acceptance.
Removing historical compatibility saves an estimated three to four engineer-weeks.
Durability, backup correctness, offline behavior, and Factorio rendering still require qualification.
Renderer and asset-format feasibility dominate uncertainty; revise estimates after phase 1.

A temporary Node/fpsr helper could deliver native UI before replacing image generation.
That path retains runtime packaging and existing native dependencies.
It should remain an optional delivery strategy, rather than the final native architecture.

## First milestone acceptance

Prove the filesystem and rendering boundaries before implementing the complete UI.

Use disposable test directories; this prototype does not qualify complete production recovery.

1. Define native metadata, control files, and a minimal recoverable TXT/JSON publication protocol.
2. Import supplied TXT bytes, add a comment, reopen, and export the original bytes exactly.
3. Acquire the real kernel lease and demonstrate competing-process refusal.
4. Interrupt one published operation and demonstrate deterministic recovery without lost originals.
5. Exercise a native snapshot prototype, preserving file bytes, hierarchy, and empty folders.
6. Compare renderer candidates on RS, rails, a nested planner, and one large supplied leaf.
7. Independently decode generated images and inspect representative structure, layering, and clipping.
8. Confirm missing assets still permit source operations and snapshot creation.
9. Measure codec, planning, painting, encoding, memory, and cancellation separately.

This assessment involved documentation and implementation inspection, plus primary Apple API references.
No Swift compilation, native prototype, new image validation, or runtime benchmarks were performed.
