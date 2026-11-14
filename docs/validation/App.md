# Native app validation

Evidence for the native app scaffold ([guide](../development/App.md)), milestone 3 subtask A3.

## App scaffold (2026-11-14)

Environment: Xcode 27.2 (27B52), macOS 27.2, Apple Silicon. `xcodebuild` first failed to load
`IDESimulatorFoundation` until the owner ran `sudo xcodebuild -runFirstLaunch`.

| Check | Result |
| --- | --- |
| `just app-build` (Debug) | Builds `Factorio Blueprint Library.app`; Info.plist has `local.fb.library`, version 0.1.0 (1), minimum macOS 27.0 |
| `just app-build Release` | Builds; `codesign --verify --strict` passes; no entitlements |
| Signing | `Signature=adhoc`, `TeamIdentifier=not set`; Debug entitlements only `get-task-allow`; no sandbox entitlement |
| Package resources | `FBNative_PreviewRenderer.bundle` is copied into `Contents/Resources` |
| Launch | Opened with `open -n` and run directly: one 420 × 190 window (the library selection placeholder) |
| Offline launch | Under `sandbox-exec` denying IP networking (where `curl https://example.com` fails to connect): one window |
| `python3 tools/check-independence.py --deny-path ../fb` | PASS, including the relocated app build and offline launch with a window |
| Repository state | Building leaves no files outside `.cache/` (gitignored) |
| `just lint`, `just build`, `just test` | Pass; lint now includes `App/Sources` |

Finding: under a blanket `deny network*` profile the app keeps running but never shows a window, because that rule
also blocks local connections; the independence launch therefore denies IP networking only.

Not covered yet: the app has no behavior beyond its placeholder window, and no `LibraryApp` test suite exists
(A4 adds it). The independence check's test filter still omits `LibraryNameTests` and
`LibraryFinderMetadataTests`; the first of them attaches a disk image, which has not been tried inside that sandbox.

## Library session layer (2026-11-14)

Milestone 3 subtask A4. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `NativeLibraryTests/completedOnOpen` | Interrupted import and folder move are reported as `import` and `tree-move` when completed; a failed change sets `requiresRecovery` until `recover()` |
| `LibrarySessionTests` (6 tests) | Create, list, change, and close with ownership released; calls run off the main thread; in use with Try Again; not a library leaves the folder untouched; a refused replay (thrown as `INTEGRITY_CONFLICT`) shows the committed operation with a shell-quoted quarantine command and opens after quarantine; completed-change notice shown once; mid-session block cleared by Recover; overlapping opens leave one library owned and the other released; a result arriving after close is ignored |
| `LibraryMessageTests` (4 tests) | Every case of `NativeLibraryError`, `BlueprintCodecError` (all limits), `PreviewError`, `PlannerRuntimeError`, `StatisticsError`, `AssetReleaseError`, `PrototypeMapError`, and an unknown error, in every activity, has a title and guidance without codes or errno and the expected code in Details; cancelled renders show nothing; listing issues have their own wording |
| Repetition | The two app suites passed 15 consecutive runs after the overlapping-open test stopped assuming which open starts first |

## Library selection (2026-11-14)

Milestone 3 subtask A5. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `LibrarySelectionModelTests` (9 tests) | LIB-1 to LIB-11 and REC-2 to REC-4 at model level: first launch, empty and `.DS_Store`-only folders asking before creation, New Library on an existing library, recents order/dedupe/limit/unavailable/remove, foreign folder untouched, `UNSUPPORTED_VERSION`, LIB-6 only through an injected opener (no synchronized folder is created by tests), in use with Try Again, switching releases the first library, reopen at launch kept on quit and app dismissal but forgotten when the owner closes, missing or held last library ending in selection, recovery state surviving `close()` and dismissed by Back, preferences override |
| Repetition | The three app suites passed 5 consecutive runs |
| Real app, isolated preferences, launched with `open` | No last library: only the selection window (520 × 232). Last library available: only the library window (900 × 452), `fb-native owner` reports owned, then idle after terminate. Last library held by another process: only the selection window, showing the in-use state (520 × 280); the holder kept running and exited normally |
| `python3 tools/check-independence.py --deny-path ../fb` | PASS, with the launch using a scratch preferences domain that is deleted afterwards |
| `just lint`, `just build`, `just test`, `just app-build` (Debug and Release) | Pass |

Findings:

- **Window on another Space:** launched directly (not through `open`), the app is not activated, so its window can
  open on another Space and never count as on screen; the A3 build in its own worktree still did, the same code
  built here did not. Launch checks therefore count the windows the app created, or launch through `open`.
- **Macro plugins under `sandbox-exec`:** with `@State` and `@Observable`, the relocated app build failed until
  `tools/xcode.sh` passed `-disable-sandbox` to the Swift compiler.

Not covered by scripts: closing the library window by hand and quitting with ⌘Q (no accessibility access to drive
the UI); both are left to the owner walkthrough. Termination in the checks above used SIGTERM, which releases the
kernel lease but is not a normal quit.

## Browsing (2026-11-14)

Milestone 3 subtask A6. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `LibraryBrowserModelTests` (8 tests, fixture library with nested folders, a book, an unpacked book with a description, and a malformed item) | BRW-1 rows and folder tree; sorting by each column with folders first; BRW-4 path bar, opening and Enclosing Folder; BRW-5/BRW-6 whole-library filter ignoring case and accents, results with their folder, no-match state, clearing returns to the folder; BRW-2/BRW-3 empty library and folders; BRW-7 folder description; BRW-8 issues worded without codes; BRW-10 too-large state; location and selection kept valid after changes and reset for a new library; formats |
| Offscreen render of the library window (throwaway probe, not committed) | Light mode: sidebar with Library and expandable folders, path bar links, table with folders first, local dates, decimal sizes, inspector folder summary, issues footer. Dark mode, sheets, and selection highlights do not render offscreen and are left to the owner walkthrough |
| `just lint`, `just build`, `just test`, `just app-build` | Pass |
| `python3 tools/check-independence.py --deny-path ../fb` | PASS after the saved-state fix below |

Finding: after the owner quit the app with no windows open, every later direct launch of `local.fb.library`
(including the A3 and A5 builds and isolated preferences) opened no window, because AppKit restored the saved state.
Launching with `-ApplePersistenceIgnoreState YES` showed the window; the app now registers that default.
Screenshots of the real window are not possible from the terminal without Screen Recording permission (A17).

## Window fixes and real-window checks (2026-11-14)

After the owner granted the terminal Screen Recording and Accessibility access, the real app was captured and driven
by script with isolated preferences and the scratch library from A6.

| Check | Result |
| --- | --- |
| Library window size | Opens at 1200 × 720 (was 900 × 452, which truncated names and hid the Size column); inspector 220–400 points, 260 by default |
| Dark content background | Item list, path bar, and inspector use `contentBackground` (`#121212` in dark mode). Captures are tagged Display P3 and brighten dark grays: the system `#1E1E1E` window background reads `#282828` and the content reads `#171717`, the same proportion |
| Light mode | Not captured: forcing light appearance for one launch is ignored; light mode keeps system colors only |
| Closing the library window with its close button (LIFE-1) | Library released (`fb-native owner` idle), reopen-at-launch cleared, selection window shown with the library in its recents |
| ⌘Q with a library open (LIB-11) | App quits, library released, kept for reopening at the next launch |

The repository also lost a Vim swap file committed by mistake with the A2 screen specs; `.gitignore` now ignores
Vim swap files.

## Books and planners (2026-11-14)

Milestone 3 subtask A7. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `LibraryBookTests` (6 tests, a book stored out of index order with sparse indices, a nested and an empty book, both planner kinds, untitled and rich-text labels, unknown fields) | BOOK-1/BOOK-2 stored order and indices; BOOK-3 nested books through Open, the path bar, and Enclosing Folder; BOOK-4 empty books; BOOK-5 descriptions with line breaks (planners from `settings.description`); BOOK-5a `2.0.55` and invalid versions; BOOK-6 mappings and filters as text; BOOK-8 export and stored bytes unchanged after browsing; a replaced source reloads, a deleted item closes the book, search works from inside a book |
| Real app, driven with mouse events and keystrokes | `bp.txt` (book `(2026-06)`): entries 0, 1, 3, 4, 5, 6, 7, 8, 12, 18 in stored order; nested `Starter Quality` with 0, 1, 6, 7, 12; path bar `Library › Trains › (2026-06) › Starter Quality`; inspector `Entry 0.0 in Starter Quality`, `Factorio 2.0.77`, description with line breaks; ⌘↑ returns with the nested book selected |
| `just lint`, `just build`, `just test`, `just app-build` | Pass |

Findings:

- **Rich-text labels:** entry names showed raw tags (`[item=uranium-235,quality=legendary]U235`) while item names,
  derived from the same labels for filenames, did not; entry names now drop tags too.
- **Keyboard focus (for A16):** with full keyboard access, Tab moves from the sidebar to the issues footer, the
  toolbar, and the search field, and never visibly reaches the item list. Double-click and ⌘↓/⌘↑ work.
- **Scripting:** System Events `click at` does not select table rows; real mouse events posted with Core Graphics do.

## Import (2026-11-14)

Milestone 3 subtask A8. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `ImportModelTests` (5 tests) | IMP-1/IMP-5 pasted text with CRLF and surrounding whitespace stored byte for byte, label used as the name, the new item selected; IMP-2/IMP-3 file bytes kept, several files with an invalid and an empty one give "Imported 1 of 3 files" with reasons; IMP-4 default destination is the current folder or the open book's folder, drop folders override it; IMP-6 duplicate names get ` (2)`; an explicit name is used; IMP-7/IMP-8 invalid, over-16 MB, empty, and whitespace-only sources are refused and nothing is created; IMP-9 to IMP-12 unpacking selects the new folder with its description, collisions get a suffix, non-books are refused for pasted text and files |
| Real app, scripted | Clipboard filled with `pbcopy` (RS.txt with a leading `  \r\n` and trailing `\r\n\t `); ⇧⌘V opened the sheet showing "Blueprint"; ⌘↩ imported and selected "Simple RS Latch"; after ⌘Q, `fb-native export` matched the clipboard byte for byte (925 bytes) |
| `just lint`, `just build`, `just test`, `just app-build` | Pass |

Not scripted: dragging files from Finder onto the list or a sidebar folder (the model path is tested); left to the
owner walkthrough. The inspector no longer repeats small sizes as "925 bytes (925 bytes)".

## Export (2026-11-14)

Milestone 3 subtask A9. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `ExportActionsTests` (4 tests) | EXP-1 Copy String puts the exact root bytes (CRLF and surrounding whitespace) on the clipboard; EXP-2 an entry in an open book copies its standalone string; EXP-3 Save As TXT writes the export bytes; EXP-4 replacing moves the previous file to the (test) Trash; EXP-5 destinations inside the library, through a link, or replacing a stored file are refused with nothing changed; EXP-6 a failed save leaves no file and restores a replaced one |
| Core: `LibraryCommandTests/failedExportWrite` | A write failing part way (file-size limit) leaves no partial file |
| Real app, scripted | ⌘C on "Simple RS Latch" put exactly the stored 925 bytes on the clipboard and showed "Copied blueprint string"; ⇧⌘E saved through the real save panel a file identical to the stored bytes; saving into the library folder showed "Exports can't be saved inside the library folder" and wrote nothing; the system replace prompt defaulted to Cancel |
| `just lint`, `just build`, `just test`, `just app-build` | Pass |

Note: the app has no icon yet, so alerts show the generic application icon.

## Comments (2026-11-14)

Milestone 3 subtask A10. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `LibraryCommentsTests` (4 tests) | COM-1 to COM-3 root, entry, and nested-entry comments oldest first with line breaks, kept after reopening with the source unchanged; COM-4/COM-5 empty, whitespace-only, and over-64 KB text refused with the draft kept; drafts stay with their item or entry; COM-6 deletion persists; COM-7 a replacement's promoted comment shows as `[Former book entry 3]` root text; Add Comment opens the Comments tab |
| Real app, scripted | ⌥⌘K on "Simple RS Latch" opened the Comments tab with the field focused; a two-line comment added with ⌘↩ appeared with its date, the field cleared, and after ⌘Q the stored comment kept its line break while `fb-native export` still matched the original bytes |
| `just lint`, `just build`, `just test`, `just app-build` | Pass |

Not scripted: deleting through the context menu or Delete key (the model path is tested).

## Organization (2026-11-14)

Milestone 3 subtask A11. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `OrganizeActionsTests` (6 tests) | ORG-1 New Folder names and rename start; ORG-2 to ORG-5 renames keep identity, dates, and comments, case-only renames work, collisions and invalid names keep the field open; ORG-6/ORG-7 moves keep metadata, invalid targets are excluded, collisions are refused; dragged rows resolve by identifier and book entries never qualify; ORG-8 to ORG-10 confirmation wording, Trash, non-empty folders refused; ORG-11 to ORG-13 replacement keeps identity and name, reports the moved comment, refuses invalid input, stores exact bytes |
| Core: `LibraryCommandTests/removalOutcomes` | Replacement reports promoted comments; deletion reports `quarantine` when the Trash is unusable |
| Real app, scripted (scratch library, `FB_NATIVE_TRASH_DIRECTORY` set through `open --env`) | ⇧⌘N created "New Folder" in rename mode, typed "Belts" and Return renamed it; a row dragged onto the Trains sidebar folder moved there; Return then typing renamed "Trains" to "Rail"; ⌘⌫ showed "Move “4x Rocket Silo Beaconed” to the Trash?" with Cancel as default, and Move to Trash put the originals in the scratch Trash |
| `just lint`, `just build`, `just test`, `just app-build` | Pass |

Findings fixed during the real-app run:

- **⌘⌫ never reached the list:** command-modified keys go through menu key equivalents, not view key handlers. Move
  to Trash is now a menu shortcut that forwards ⌘⌫ to a focused text field.
- **Confirmed deletions did nothing:** dismissing the alert cleared `pendingDeletion` before the button's action read
  it. The alert now passes its value; the test reproduces the order.
- **Return-to-rename lost focus:** the table kept focus while handling Return; the field now claims it on the next
  run-loop turn.

Not scripted: Move To sheet, Replace Source sheet, renaming from the sidebar menu (model paths tested).

## Settings (2026-11-14)

Milestone 3 subtask A14. Tests written with the implementation (not by the `qa-engineer` subagent); they build a
minimal release in a temporary folder (`AppTestAssetRelease`), so no private assets are needed.

| Check | Result |
| --- | --- |
| `AssetSettingsTests` (5 tests) | SET-1 a chosen release verifies and shows its name and Factorio version; SET-4 it is re-verified at the next launch and a removed folder becomes "The asset release folder is missing"; SET-2 a folder without `release.json` is refused as "This folder isn't a usable asset release" with the previous release kept; SET-3 a release inside or containing the library is refused and never offered for it; SET-5/SET-5a/SET-6 the prototype map loads once per release, changing or clearing the release resets it; STA-6 a release whose map is unsuitable verifies but cannot give statistics |
| Real app, scripted | ⌘, opened Settings showing "None"; Choose… with the real private release showed "Verified: native-renderer, Factorio 2.1.23" and saved the path; a relaunch with that path saved re-verified it at startup |
| `just lint`, `just build`, `just test`, `just app-build` | Pass |

Fixed during the run: a folder without `release.json` first read as a disk error (`ENOENT`); every verification
failure in Settings now reads as an unusable release, with the code and reason in Details.

## Previews (2026-11-14)

Milestone 3 subtask A12. Tests written with the implementation (not by the `qa-engineer` subagent); app tests use a
gated fake backend or the app's real lookup without a worker, and the service test renders with synthetic assets, so
no private assets are needed.

| Check | Result |
| --- | --- |
| `PreviewCenterTests` (9 tests) | PRV-5/PRV-7 renders run one at a time in request order and the inspector and a window share one render; PRV-6 a dropped waiter leaves the render alone, a dropped render is cancelled and the next starts; PRV-2/PRV-12 cache hits and empty blueprints start no render; PRV-9 no release shows the no-assets state; PRV-11 missing items and book entries are the deleted state; PRV-10 failures show the reason and Retry renders again; SET-5a/SET-6 clearing the release cancels the render; the real lookup finds empty blueprints and a missing worker asks to reinstall; library calls complete during a render |
| `PreviewViewportTests` (3 tests) | PRV-8 fit follows resizes until zoom or pan, zoom keeps the point under the pointer, Fit and Actual Size alternate, pan stays over the image |
| `LibraryPreviewTests` cache-only lookup | `cached` needs no worker or release verification, matches only the given identity and options; a caller's cancellation token cancels its render |
| Bundle | Debug and Release apps carry `Contents/MacOS/preview-worker`; `codesign --verify --deep --strict` passes; the Release worker's only rpath is `@executable_path/../Frameworks` |
| Real app, scripted (relocated copy, build `PackageFrameworks` moved aside, private release) | The inspector rendered "4x Rocket Silo Beaconed" uncached and published it to `cache/`; "Empty" showed "This blueprint has no entities or tiles." with no worker; ⌘Y opened the upgrade planner in a window titled "Upgrade" at Fit (296%); View-menu Zoom to Fit, Zoom Out, and ⌘− changed the zoom; after quit, no app or worker process remained and `fb-native owner` reported the library idle |
| `just lint`, `just test`, `just app-build` (Debug, Release), independence check | Pass |

Not exercised in the real app (scripted input stopped while the owner was using the Mac): Space in the list, windows
closing with the library, rename or replace with a window open, a release change, and sampling worker processes under
real renders. During the run a Colors panel opened and the zoom read 332% after one ⌘− keystroke; repeating the same
steps did not reproduce it, so it is unexplained (possibly outside input).
