# Milestone 3: native application

Date: 2026-11-13. Status: approved by the owner on 2026-11-14, with the decisions below.
A1, the [app spec](../specs/Native-App.md), is approved and A0 is done (2026-11-14). A2, the
[screen specs](../specs/Native-App-Screens.md), is approved, and A3, the [app scaffold](../development/App.md), is done
(2026-11-14). A4, the library session layer, A5, library selection, A6, browsing, A7, books and planners, A8, import, A9, export, A10, comments, and A11, organization, A14, settings, A12, previews, A13, statistics, A15, menus and lifecycle, A16, accessibility, and A17, tests and smoke runs, are done. Next: A18 (docs and
acceptance).
Roadmap entry: [native plan](macOS-Plan.md#delivery-roadmap), milestone 3.

## Scope

Library selection, browsing, nested books, import/export, comments, organization, an image viewport, and preview
windows for visual comparison.

Exit condition: everyday workflows work offline, including without renderer assets.

Out of scope, owned by later milestones or excluded from v1:

- Thumbnail scheduling across whole grids, bounded preview queues, progress and retry across many items,
  and full-corpus visual qualification (milestone 4).
- Installation, the 1,000-root workload targets, and power-loss qualification (milestone 5).
- Copying or saving a preview image: required, deferred by the owner to a later milestone (not yet assigned).
- Icons for Factorio rich-text tags in item and entry names (milestone 4, owner decision 2026-11-14); milestone 3
  removes the tags from displayed names.
- Backup/restore, App Store submission, and public distribution (excluded from v1).

The original web application's workflows are a reference, not a specification
(see its Application-Integration contract in the original repository).

## Decisions

The owner settled these on 2026-11-14.

| # | Question | Decision | Rejected alternative |
| --- | --- | --- | --- |
| 1 | App structure (A3) | UI and logic in a package target, testable under `just test`; a thin Xcode app target only for the `.app` bundle, Info.plist, signing, and SwiftUI previews, as the plan anticipated | SwiftPM only, with a script assembling the `.app` |
| 2 | App Sandbox | None: a directly distributed, signed app for personal use, as the assessment recommends | Sandbox with security-scoped bookmarks and a re-qualified preview worker |
| 3 | Window model | One library per app, in one main window; opening another library closes the current one and releases its lease. Any root item or book entry (by stored index) can open in its own preview window, so several can be compared side by side | One window per library with several libraries open; root items only in preview windows |
| 4 | Previews | On demand only: the inspector's selected item and each open preview window. Renders run one at a time through the single shared preview service, in request order; waiting windows say so, cache hits appear at once, and closing a window or changing the selection cancels its render. List rows show a thumbnail only when one is already cached | Parallel workers per window; grid thumbnail scheduling now |
| 5 | Statistics | Include the statistics panel (A13), with item names as text; icons need the private sprite atlases and come with milestone 4 | Statistics out of the app until milestone 4 |
| 6 | Maintenance | Cache cleanup, staging cleanup, quarantine, and usage stay CLI-only; the app shows "recovery required" with a Recover action | Maintenance screens in the app |
| 7 | UI testing | Session-layer unit tests in `just test`, scripted screenshot runs, and an owner walkthrough; no XCUITest | Automated UI tests with XCUITest |

Preview windows follow their item by ID: a rename updates the title, a replaced source re-renders, and a deleted item
(or a book entry that no longer exists) shows that it was deleted and stays open until closed.
Closing the library closes its preview windows.

## Subtasks

| # | Subtask | Delivers | Done when | Depends on |
| --- | --- | --- | --- | --- |
| A0 | Core name and Finder-file fixes | LibraryCore collision keys use full Unicode case folding with normalization, independent of the volume; `.DS_Store` files are ignored in `operations/`, operation directories, and folder move/delete inventories; storage contract updated | Spec GEN-6–GEN-8 hold in core tests on case-sensitive and case-insensitive volumes; existing suites pass | — |
| A1 | App spec | `docs/specs/Native-App.md`: given/when/then criteria per workflow, including empty and error cases | Owner approves | — |
| A2 | Screen specs | Main window layout (folder sidebar, item list, detail inspector) and preview windows, states (empty, loading, library in use, recovery required, assets missing), focus order, shortcuts, accessibility | Owner approves | A1 |
| A3 | App scaffold | Package UI target, thin Xcode app target, `just app-build` and `just app-run`, independence check extended to the app | The empty app builds and launches offline; existing checks pass | — |
| A4 | Library session layer | Main-actor session running library calls off the main thread; every library error code mapped to a user message; library change notifications for open windows; opening reports operations completed by replay (spec REC-1) | Unit tests cover state changes and every error code | A3 |
| A5 | Library selection | Open or create, recent libraries, one library per app (opening another closes the current one); in-use, unsupported, recovery-required (with Recover), and unknown-folder states | Each state reachable in tests; closing the library releases ownership | A4 |
| A6 | Browsing | Folder sidebar, item list (name, kind, updated date, size), name filter, breadcrumbs, empty-folder state, listing issues shown | Tests on a fixture library; owner walkthrough | A5 |
| A7 | Nested books and planners | Immediate children by stored index, descriptions with line breaks, planner settings as text | Sparse indices and nested books display correctly | A6 |
| A8 | Import | Paste, open TXT (exact bytes), drag and drop; target folder; save as one book or unpack; select the result | CRLF and whitespace preserved; invalid strings and non-book unpacking explained | A6 |
| A9 | Export | Copy exact root string, copy standalone entry, save as TXT (no Reveal in Finder, by owner decision) | Bytes match the CLI export; replacing an existing file asks first | A7 |
| A10 | Comments | List, add (root or entry), delete | Survive reopening; empty comment refused | A7 |
| A11 | Organization | New folder, rename, move (menu and drag and drop), delete to the Trash with confirmation, delete empty folder, replace source | Identity, dates, and comments preserved per the contracts; collisions explained | A6 |
| A12 | Image viewport and preview windows | On-demand preview in the inspector and in preview windows for root items and book entries; one render at a time in request order with a waiting state; pan/zoom/fit; cancelled on selection change or window close; failure with Retry; "no assets configured" state; windows follow renames, replacements, and deletions | Works with and without assets; cache hits instant; several windows compare side by side; no concurrent worker | A7, A14 |
| A13 | Statistics panel | Requirement groups, footprint, warnings worded from codes; not applicable for books and planners | Matches `fb-native statistics` for the seven approved blueprints | A7, A14 |
| A14 | Settings | Asset release location, verified when chosen; prototype map loaded once per session | An invalid release is refused clearly; everything else works without assets | A4 |
| A15 | Menus and lifecycle | Commands and shortcuts; closing the library closes its preview windows; close and quit cancel renders and release the library; clear message when the CLI holds it | Lifecycle tests pass; no stray worker after quit | A5, A12 |
| A16 | Accessibility | VoiceOver labels, keyboard navigation, contrast in light and dark mode | Main flow works by keyboard alone; checklist recorded | A6–A13 |
| A17 | Tests and smoke runs | Session tests in `just test`; scripted launch with screenshots of key screens, including the window-launch check moved out of the independence check | All pass; screenshots kept private | A4–A15 |
| A18 | Docs and acceptance | User guide, `docs/validation/Milestone-3.md`, offline and no-assets runs, owner walkthrough | Exit condition shown; owner approves | All |

Suggested order: A0 (found in the A1 review) → A1 → A2 → A3 → A4 → A5 → A6; then A7–A11 and A14 in any order; then A12, A13; then A15–A18.
