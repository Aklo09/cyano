# Milestone 4: rendering integration

Date: 2026-11-15. Status: approved by the owner on 2026-11-15, with every decision below settled.
Roadmap entry: [native plan](macOS-Plan.md#delivery-roadmap), milestone 4.

## Scope

Roadmap deliverable: visible-item scheduling, bounded queues, cache identity, progress, cancellation, warnings, and
retry; icons from the private sprite atlases for Factorio rich-text tags in item and entry names (owner decision,
2026-11-14) and for statistics items.

Exit condition: the full supplied corpus receives native rendering and visual qualification.

No Factorio artwork is embedded. Icons, sprites, and planet icons are read at runtime from the private release the
owner prepares from their own game installation and selects in Settings. They are never committed, never added to
package resources or the app bundle, and the app shows the kind symbol and tag text when no release is configured.
R10 adds a check that enforces this.

On 2026-11-15 the owner removed thumbnails from the milestone (settled decision S1). Visible-item scheduling, bounded
queues, and progress across many items therefore leave milestone 4. Entry icons, rich-text icons, and planet icons
join it. The roadmap row was amended on approval.

### Already delivered

Milestones 1 and 3 delivered part of the roadmap row. This milestone extends that work and does not replan it.

- **Cache identity:** source hash, stored entry path, generator (`native-preview-v1`), and release identity
  ([preview cache contract](../contracts/Preview-Cache.md)). Cached reports keep the worker's warnings.
- **Ordering and cancellation:** `PreviewCenter` renders one preview at a time, in request order, off the library
  worker. A request drops when its last viewer leaves, and quitting or closing the library cancels the render
  (PRV-2, PRV-5 to PRV-7, LIFE-1).
- **Retry:** a failure shows its `LibraryMessage` with Retry (PRV-10).
- **Representative images:** RS, dense overlays, both planner kinds, the 6,814-entity leaf, and the elevated-rail
  fixture were reviewed in milestone 1 ([renderer validation](../validation/Renderer.md)).

### Remaining

- **Entry icons:** each blueprint, book, and planner stores an `icons` array of up to four signals. The game shows
  them as the entry's symbol. The app shows only the kind symbol today.
- **Rich-text icons:** names drop every bracketed tag today (`LibraryBookBrowsing.name`). Root item names come from the
  stored basename or rename, and import already strips tags from them ([storage contract](../contracts/Storage.md)).
  See decision 3.
- **Planet icons:** the release's render database has no planet icons (see the survey).
- **Statistics icons:** statistics show item names as text (milestone 3, decision 5).
- **Render warnings:** the planner reports warnings, and the cache keeps them, but the app does not show them.
- **Full-corpus visual qualification,** including connected-rail seams. This has been outstanding since milestone 1.

### Corpus survey (2026-11-15, Factorio 2.1.24 release)

The nine supplied fixtures in `Tests/LibraryCoreTests/Fixtures/Blueprints` hold 198 renderable leaves: 185
blueprints, 12 upgrade planners, and 1 deconstruction planner, in 25 books. The five vendored fpsr visual tests
(`tools/vendor/fpsr/fixtures/visual-tests`) add 41 blueprint leaves: 35 in `book`, 4 in `space-age`, 1 in
`elevated-rails`, and 1 in `recycler`. `quality` is an empty book.

Rails differ between the two sets:

- **Supplied fixtures:** connected straight rails only. There are 5 leaves in `bp.txt`, and 2 in `v0.59.0.txt`, which
  also has elevated straight rails and ramps.
- **Vendored `book`:** the only curved, half-diagonal, and legacy rails.
- **Vendored `elevated-rails`:** the only elevated curves and supports.

Entry icons are common across both sets:

- **Usage:** 258 of 277 entries have them (226 blueprints and 32 books), with 1 to 4 icons each.
- **Signal types:** `item` 301, `virtual` 28, `space-location` 30, `fluid` 10, `recipe` 7, and `quality` 3. 35
  signals carry a quality other than normal.
- **Matching the release:** every signal has an icon in the render database except the planets. Signal type `virtual`
  maps to the database's `virtual-signal/` keys. The 25 references to Nauvis, Vulcanus, Gleba, Fulgora, and Aquilo
  have no icon, because the database's three `space-location` icons are shattered-planet, solar-system-edge, and
  space-location-unknown.

Rich-text tags are rare: 12 of the 277 labels contain them (11 `item`, 2 `fluid`, 1 `quality`), and one of these is a
root label, in `bp.txt`. Every tagged name has an icon in the release. This survey covers labels only. It does not
prove coverage for tag forms the corpus lacks, such as `[img=…]`, `[color=…]`, `[gps=…]`, or `[train=…]`.

The render database has 1,395 icons in these categories: recipe, item, virtual-signal, entity, fluid, tile,
asteroid-chunk, utility, quality, and space-location.

### Out of scope

These belong to later milestones or are excluded from v1:

- Thumbnails, icon or grid views, visible-item scheduling, and bounded preview queues (owner, 2026-11-15, S1).
- The 1,000-root and 149-leaf workload targets, installation, and power-loss qualification (milestone 5). This
  milestone records render timings but sets no targets.
- Asset-release verification counting `.DS_Store` as an unexpected member (unscheduled).
- Backup/restore, App Store submission, and public distribution (excluded from v1).
- Mods and other game profiles.

## Decisions

Settled by the owner on 2026-11-15.

| # | Decision |
| --- | --- |
| S1 | No thumbnails. The inspector's preview of the selected entry is enough. Previews stay on demand with one worker, as in milestone 3 (decision 4) |
| S2 | Entry icons (the `icons` property) appear in list rows and in the inspector when an item or entry is selected |
| S3 | Rich-text tags in names are shown as the matching icon |
| S4 | The release gains the missing planet icons |
| S5 | A tag whose icon is not available stays in the name as written; it is no longer removed |
| 1 | The full supplied corpus is the nine fixtures (198 leaves) plus the four non-empty vendored visual tests (41 leaves), 239 leaves in all. Only the vendored files have curved, diagonal, legacy, and elevated-curve rails |
| 2 | A `just` recipe imports the corpus into a scratch library and calls the existing `fb-native preview … --entry` for every leaf. It writes a report (dimensions, timings, warnings, failures) and contact sheets under `.cache/`. The owner reviews the sheets and opens flagged entries at full size. For rail seams the owner judges crops at 100% and 400%, compared with in-game screenshots where the owner supplies them. No reference renderer and no new dependency |
| 3 | Imports stop removing tags when they name a new item. Filename projection keeps them (`[` and `]` are valid on APFS), so the stored name, renames, and folders made by unpacking all keep their tags and show icons. Finder and the CLI show the tags as text. Items imported earlier keep their stripped names. This changes the filename rule in the [storage contract](../contracts/Storage.md), not the metadata schema |
| 4 | Entry icons have two layouts. The inspector header shows the game's arrangement, using fpsr's layout (`packages/renderer/src/blueprint-icons.ts`): one icon fills the tile, and two to four share a 2 × 2 grid, with quality badges; a signal without an icon leaves its slot empty. List rows keep the kind symbol and show the entry's icons (one to four, in stored order, with quality badges) in a line before the name; a signal without an icon is left out. Without icons or without a release, rows show the kind symbol and name only, and the inspector shows the kind symbol |
| 5 | The app process reads icons at runtime from the verified release only: Image I/O crops the WebP atlas frames that the render database names, kept in a bounded in-memory cache, never written to disk. The 1,395 icons use 944 frames on 37 atlases at 2x (at most 320 × 320, 13.3 MiB decoded in all) or 9 atlases at 1x (3.3 MiB) |
| 6 | Planet icons are added to the render database as `space-location/<planet>`, so that signals and `[planet=…]` tags find them. The profile stays at 2.1.24 schema 2, so a release without them still verifies and shows planet tags as text (S5). Getting the icons means regenerating `private-assets/2.1.24` and reassembling the release, which changes the release identity, so cached previews render again once |
| 7 | Render warnings: a count beside the preview, with a disclosure listing them grouped by text and capped (reports allow up to 100,000), worded from the planner's text after R1 shows which ones occur. Nothing new is persisted |
| 8 | Copy Image and Save Image As… (PNG, the cached bytes exactly) from the inspector and preview windows are part of milestone 4 |

## Subtasks

Numbering uses R for rendering.

| # | Subtask | Delivers | Done when | Depends on |
| --- | --- | --- | --- | --- |
| R0 | Spec amendments | New criteria in the [app spec](../specs/Native-App.md) for entry icons, rich-text icons (including S5's fallback), statistics icons, warnings, and image copy/save, with layouts, states, and accessibility in the [screen specs](../specs/Native-App-Screens.md). BRW and thumbnail references updated for S1 | Owner approves | Decisions |
| R1 | Corpus qualification harness | `just` recipe and script: scratch library, import of the corpus, render of every leaf through the existing CLI, report and contact sheets in `.cache/qualification/` | First full run recorded: per-leaf success, dimensions, timings, warnings; no images committed | Decisions 1, 2 |
| R2 | Renderer corrections | Fixes for defects that R1 and the owner's review find, including connected-rail seams. Each fpsr change is a patch in `tools/vendor/fpsr-patches/`; a render-database change regenerates the private assets | Every corpus leaf renders without failure or unexplained warning; the owner accepts the seam crops | R1 |
| R3 | Planet icons in the release | An fpsr pipeline patch that exports the planet icons; `private-assets/2.1.24` regenerated; asset-preparation guide and renderer validation updated; the owner reminded to reassemble the everyday release | The five corpus planets resolve in the new release; `just asset-test` and `just tools-check` pass | Decision 6 |
| R4 | Icon catalog | Loads the icon table and atlas frames from a verified release, with bounded crops through Image I/O, a memory cache keyed by release identity, and signal-type mapping (`virtual` → `virtual-signal`). Tests use a tiny synthetic release | Unit tests cover known, unknown, quality-badged, and malformed entries, plus a release change | Decision 5 |
| R5 | Entry icons | Icons in a line before the name in list rows, after the kind symbol, and the 2 × 2 composite in the inspector header, for root items and book entries (decision 4) | All 258 corpus entries with icons show them in both places; entries without icons, and the no-assets state, show the kind symbol only | R0, R4 |
| R6 | Rich-text names | One tag parser replaces the regex in `LibraryBookBrowsing.name`. Tags with an icon draw as icons in rows, the path bar, and the inspector header; tags without one stay as written (S5). Window titles, filter, sort, and Save As filenames use the text form; VoiceOver reads icon names. Storage change only if decision 3 is accepted | Corpus labels and synthetic tag forms display as specified; filter and sort behave as the spec says | R0, R4, decision 3 |
| R7 | Statistics icons | Item and quality icons in Statistics rows. Missing icons fall back to text | STA-2 parity holds; every map item has an icon or a fallback | R0, R4 |
| R8 | Render warnings in the UI | Warning count and disclosure in the inspector and preview windows | Synthetic warnings display as specified, with VoiceOver announcements | R0 |
| R9 | Copy and save preview image | Copy Image and Save Image As… (PNG, cached bytes); refuses destinations inside the library, as Save As TXT does | Saved bytes equal the cache file; the clipboard holds a PNG | R0 |
| R10 | Accessibility, smoke run, and artwork check | Keyboard and VoiceOver labels for icons and the new controls; `just app-smoke` extended to entry and name icons, a warning, and image copy. A check in `just test` that fails if Factorio artwork or release data is in git-tracked files, package resources, or the built app bundle: by name (`atlas.*.webp`, `render-db.*.json`, `release.json`, `prototype-map.json`) and, where `private-assets/` exists, by matching SHA-256 against every file in it | Smoke run passes with and without assets; the check passes, and fails on a planted copy of an atlas in a scratch bundle | R5–R9 |
| R11 | Docs and acceptance | Guides (`docs/development/App.md`, `Preview.md`, `Asset-Preparation.md`), the user guide, and `docs/validation/Milestone-4.md` with per-leaf counts, verdicts, timings, and the owner's visual review (images stay in ignored directories) | Exit condition shown; owner approves | All |

Suggested order: R0 first. R1 and R3 can start at once, because they need no app changes;
R1's findings feed R2 in parallel with the app work. Then R4 → R5, R6, R7; R8 and R9 in any order; then R10 and R11.

R2 is open-ended: its size depends on what R1 finds. If R1 turns up more than a handful of distinct renderer
defects, they will be listed and prioritized with the owner before the work continues.
