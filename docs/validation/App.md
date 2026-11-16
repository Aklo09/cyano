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

## Statistics (2026-11-14)

Milestone 3 subtask A13. Tests written with the implementation (not by the `qa-engineer` subagent); they use the
minimal test release, and the parity test uses the private release when present.

| Check | Result |
| --- | --- |
| `StatisticsModelTests` (5 tests) | STA-4 no release asks for one; STA-5 books and planners are not applicable; STA-1 counts, groups, and footprint for a root blueprint and a book entry reached through the browser by stored index; SET-5 the map loads once for several entries; STA-3 warnings worded once with their count, naming the entity or quality, known bounds as "at least", no known bounds as incomplete; refused data shows "Statistics can't be calculated for this blueprint"; STA-6 an unsuitable map says the release can't provide statistics; rows copy as text |
| `StatisticsParityAppTests` | STA-2: for `RS.txt`, `4x_Rocket_Silo.txt`, `Hazard_Patterns.txt`, `bp.txt` `0.0` and `1.1`, `v0.59.0.txt` `1.1`, and `elevated-rails.bp.txt` `0`, every count, footprint, completeness flag, group row, and warning count shown matches `fb-native statistics` with the private release |
| `just lint`, `just test`, `just app-build`, independence check (`Package.swift`: `LibraryAppTests` depends on `FBNativeCLI`) | Pass |

Real app, scripted (owner allowed the screen; private release): at the minimum window size (900 × 552 with the
toolbar) "concrete patterns" showed 0 entities, 437 tiles, footprint 21 × 21, concrete 181 and refined-hazard-concrete
256, as `fb-native statistics` reported before launch; "Simple RS Latch" showed 7 entities, 4 × 4, and its three
combinators, also matching; the book showed "Statistics don't apply to books…" and the planner "Statistics don't
apply to planners."; entry `0.0` of the `bp.txt` book, opened with ⌘↓ twice, showed 1,157 entities, 83 × 43, and a
legendary fast-inserter row; selecting two rows and pressing ⌘C copied `assembling-machine-3	30` and
`bulk-inserter	106` (the owner's clipboard was restored afterwards). After quit, no app or worker process remained and
the library was idle.

Fixed during the run: with a planner selected, the Statistics message asked for more height than the window had, and
the whole window's content (sidebar included) shifted up under the toolbar. Messages now sit in a scroll view, like the
Details tab.

## Menus and lifecycle (2026-11-14)

Milestone 3 subtask A15. Tests written with the implementation (not by the `qa-engineer` subagent).

| Check | Result |
| --- | --- |
| `LifecycleTests` (4 cases) | LIFE-1 closing the library during a render cancels it, reaps the worker (a shell-script stand-in that records its ID and blocks), releases ownership, forgets the library, and publishes nothing; LIFE-2 quitting during a render does the same synchronously and keeps the library to reopen, and later calls are refused; LIFE-3 quitting during an import paused before and after `intentPublished` finishes it, and the library reopens with nothing to recover. With the quit-time close disabled, LIFE-2 and LIFE-3 fail |
| Real app, scripted (owner allowed the screen; private release) | Menu bar read through accessibility with no library, a library open, a folder selected, an item selected, and a preview window in front: every command in the screen specs' table is present with its shortcut; Delete Folder replaces Move to Trash for a folder; selection commands are disabled while a preview window is key, and its zoom commands are enabled. Closing the main window with a preview window open closed the preview window, showed library selection, left no worker, and `fb-native owner` reported the library idle (LIFE-1). Quitting while entry `0.0` of the `bp.txt` book showed "Rendering…" (worker process seen) left no app or worker process, an idle library, no image for that entry, and the library to reopen (LIFE-2). The relaunch reopened the library with no preview windows (PRV-13) |
| `just lint`, `just test` (twice), `just app-build` | Pass |

Fixed during the run: none. Found in the full `just test` run: two app tests (one Previews, one Lifecycle) timed
out at 5 s while other test targets ran alongside, because library writes force data to disk; their waits now
allow 30 s and return as soon as the condition holds.

Observed, not fixed: with no library open, the Window menu lists "Factorio Blueprint Library" twice (the selection
window and a second, untitled-looking entry); for A16/A17.

## Accessibility (2026-11-15)

Milestone 3 subtask A16. The owner allowed scripted keystrokes and clicks on a scratch copy of the Debug app (scratch
library with folders, a book, an unpacked planner book, and a comment; separate preferences; the private 2.1.24
release), and switching Increase Contrast for the run. Full Keyboard Access was already on and stayed on. The
clipboard text was saved and restored. VoiceOver itself was not run (owner's choice): rows marked "AX tree" were read
through the native accessibility API (`AXUIElementCopyAttributeValue`), which is what VoiceOver reads, and
announcements through an `AXObserver` on `AXAnnouncementRequested`. Contrast was measured on window captures
(`screencapture -l`) from glyph-core pixels (98th percentile of per-pixel contrast) against each region's dominant
background; dark mode is the system setting, light mode a scratch-copy `NSRequiresAquaSystemAppearance`.

### Keyboard walkthrough (screen specs, "Accessibility")

| Step | How verified | Result |
| --- | --- | --- |
| Open a library (first launch, no recents) | Keystrokes + AX focus | Selection window labelled; focus starts on a button; Window menu lists it once |
| Find an item with ⌘F | Keystrokes + AX focus | Focus in the search field; typing filters; Tab moves into the results |
| Open a folder or book with ⌘↓ | Keystrokes + AX focus + capture | **Fixed:** focus fell to the window when the book's table replaced the item list, and a folder opened in place lost its selection. Now the list keeps focus with its first row selected; ⌘↑ returns to the item list |
| Copy an entry with ⌘C | Keystrokes + clipboard | 7,813-byte entry string copied; "Copied blueprint string" announced (twice while a view also posted it; that duplicate was removed and not re-observed). Rechecked after the Window-menu change: 919-byte item string copied |
| Add a comment with ⌥⌘K and ⌘↩ | Keystrokes + AX + capture | Focus in "New comment"; ⌘↩ adds it. **Fixed:** Shift-Tab never left the field and Escape left focus nowhere; Tab and Shift-Tab now move focus and Escape returns to the list |
| Preview window with Space; zoom with ⌘+ and ⌘9 | Keystrokes + AX | Window opens with the image focused; ⌘+ 88→110→137%, ⌘− 110%, ⌘0 100%, ⌘9 fit 88%; ⌘W returns focus to the entries list |
| Import from the clipboard with ⇧⌘V and ⌘↩ | Keystrokes + AX focus + capture | Sheet opens with focus in "Blueprint string"; ⌘↩ imports, selects the new item, focus in the item list |
| Tab order, main window | Keystrokes + AX focus + captures | Sidebar → Hide Sidebar → Import → search → item list, every stop with a visible focus ring or selection. **Fixed (A7 finding):** focus did reach the list but showed nothing; entering it with no shown row selected now selects the first row. A selection hidden by the search counts as none. Repeated: 30 of 30 ⌘F-search-Tab cycles across three launches and 3 of 3 first Tabs after launch selected the shown row (an earlier guard on `.keyDown` missed about one in ten, see the app guide) |
| Sheets return focus | Keystrokes + AX focus | Move To (⌃⌘M), Import (⇧⌘I), and Replace Source: Escape returns focus to where it was |
| Delete a comment | Keystrokes + AX | Delete in the comments list opens the confirmation with Cancel as default; Tab, Space confirms. Deleting the last comment removes the list and focus falls back to the window (observed, not changed) |
| Stale focus restore | Keystrokes + AX focus | After ⌘↓ into a folder, a search that empties and refills the list keeps focus in the search field |
| Mouse-only gestures (GEN-5) | Menus + code | Drag move → Move To… (⌃⌘M); drop import → Import… (⇧⌘I); pan → arrow keys in the preview; comment delete → Delete in the comments list; **added:** View ▸ Sort By for the column headers, with the header indicator following it |

### VoiceOver labels and announcements

| Check | How verified | Result |
| --- | --- | --- |
| Item rows | AX tree | "(2026-06), book, updated 15 November 2026, 260 KB"; book entries add "entry 0"; kind symbols hidden |
| Preview image and states | AX tree + observer | "Preview of (2026-06) — Entry 4"; "Preview ready" announced |
| Toolbars | AX tree | Hide Sidebar, Import, Zoom Out/In, Zoom to Fit, Actual Size, Background labelled with help text; zoom level "Zoom 88 percent" |
| Inspector, Settings, selection window | AX tree | Every button labelled (System Events reports these titles empty; the native API has them) |
| Comments | AX tree | **Fixed:** the list was unlabeled and each comment read only its date; now "Comments", and "Latch for the oil cracking setup, 15 Nov 2026 at 9:09" |
| Import, Move To, Replace Source sheets | AX tree | **Fixed:** the name field, "Save in" pop-up, "Books" choice, and the Move To folder list ("Folders") were unlabeled; Replace Source was already labelled |
| Banners and confirmations | Observer + code | Confirmations were already announced by the model. Banners now announce their text when shown and keep their action a separate button (`contain`, not `combine`); no banner state occurred in the run |
| System-drawn elements | AX tree | Window buttons, scroll-bar parts, outline disclosure triangles, and the Statistics list's leading section row carry no label of their own (system standard) |

### Contrast (text the app draws, 4.5:1)

| Area | Dark | Light | Increase Contrast (dark / light) |
| --- | --- | --- | --- |
| Item rows | 12.4 | 14.0 | 14.6 / 17.6 |
| Selected row, key window | 6.2 | 5.4 | 4.6 / 7.6 |
| Selected row, background window | — | 11.6 | — |
| Sidebar item, selected item | 18.4, 12.6 | 19.6, 15.9 | 16.7, 6.4 / 19.6, 8.5 |
| Column headers | 15.6 | 14.9 | 18.7 / 21.0 |
| Path bar | 13.5 | 14.9 | — |
| Inspector text | 18.7 | 21.0 | 18.7 / 21.0 |
| Material panel over the checkerboard | 11.5 | 7.7 | — |
| "Books have no preview" entry count | **3.1 → 17.0** | — | — |
| Statistics quality name ("rare") | 13.5 after the change | — | — |

**Fixed:** the entry count (3.1:1 in dark mode) and the Statistics quality name used `.secondary`; both are primary
text now, the quality name set smaller. The quality name was only measured after the change. System-drawn text keeps system styling as the spec allows: the selected
inspector segment (3.8 dark, 4.3 light) and a background window's sidebar (about 3:1) and title (2:1).
Increase Contrast is followed through system colors. Reduce Motion: zoom from buttons and shortcuts uses no animation
(code: `PreviewViews.swift` checks `accessibilityDisplayShouldReduceMotion`); not toggled in the run. Text uses system
styles; the one fixed size is the decorative symbol in the selection window.

### Window menu

**Fixed (A15 finding):** each `Window` scene added its own Window-menu item, both named after the app. The library
scene now drops its item and AppKit lists its window by title. Checked in one session: library open "Library"; with
a preview "Library, Simple RS Latch"; preview closed "Library"; ⇧⌘W shows the selection window listed once; reopening
from the recents list shows "Library" again. Removing the selection scene's item as well also removed Edit's Cut,
Copy, Paste, Delete, and Select All; that variant was dropped, and File, Edit, and Library now match the A15 menu dump
item for item.

Not checked: Full Keyboard Access off (it stayed on for the run). Also unchecked: after a keyboard-confirmed item
deletion, focus returning to the list may select its first row, so a second ⌘⌫ would target that row (still behind
the confirmation).

| Check | Result |
| --- | --- |
| `LibraryBrowserModelTests` (2 new) | Keyboard focus selects the first row only when no shown row is selected (also in search results, with a hidden selection, and with no matches); the location key follows folders and books, not the filter; Sort By titles |
| `just lint`, `just app-build` | Pass |
| `just test` | First run: one failure, LIFE-2 (`LifecycleTests.swift:103`, "the render never started a worker" after its 30 s wait); every other test passed. The suite alone passed three times in a row (about 1.5 s each), and the second and final full `just test` runs passed |

Observed, not fixed: the LIFE-2 failure above, which looks load-related (no change here touches preview rendering);
for A17 to watch in repeated full runs.

## Tests and smoke runs (2026-11-15)

Milestone 3 subtask A17. The owner allowed the scripted runs on their Mac (hands off; clipboard saved and restored).

| Check | Result |
| --- | --- |
| Session tests in `just test` | Every app suite in `just app-test` is in `just test` (session, messages, selection, browsing, books, import, export, comments, organization, settings, previews, statistics, lifecycle). 15 full runs on 2026-11-15 |
| PRV-11, failed twice in full runs | **Fixed (test race):** the test finished the fake render as soon as the viewer showed "rendering", which happens when the job is scheduled; the fake backend's `finish` only reaches a render that has registered, so under load the signal was lost and the render never ended. It now waits for the render to start, as every other test there does. `until` now reports the calling line (that is how the second failure pointed at the wait after `finish`). Three full runs after the fix passed |
| LIFE-2, failed once in a full run | Not reproduced in 14 other full runs. Its worker is a real process, so this race does not apply; its failure message now includes the viewer state and whether a render is running |
| Test preference files | **Fixed:** test cleanups called `removePersistentDomain`, which empties a domain while the preferences daemon writes the empty file back, so 848 `local.fb.library.tests-*.plist` files had built up in `~/Library/Preferences`. `removeTestPreferences` also runs `defaults delete` and removes the file; after `just app-test` and full runs none remain. The leftovers, and 18 from earlier manual runs, were removed with the owner's approval; the app's own `local.fb.library.plist` was kept |
| `just app-smoke --assets .cache/renderer-assets --deny-path ../fb` (`.cache/smoke/20261115-103807`) | 13 of 13 pass: first launch offline shows selection and quits; relaunch reopens the library; Space opens a preview window; three uncached previews peaked at one worker; renaming retitles the open window; replacing keeps it open with a new image (the old original went to the run's `trash/`); clearing the release shows "No asset release is configured" in the window; closing the library closes the windows and shows selection; after quit no worker, owner idle. 11 captures |
| `just app-smoke --deny-path ../fb` (no assets, `.cache/smoke/20261115-104046`) | 11 pass, 2 skipped (worker and release checks) |
| Independence check | The app launch moved to the smoke run; see below |

Deferred real-app checks from A12 now covered by the smoke run: Space in the list, windows closing with the library,
rename and replace with a window open, a release change, and one worker at most under real renders.

Fixed in the tool during the runs (no app changes): the window-server list includes hidden windows (a closed library
window stays listed, still showing "Loading library…"), so visible titles come from the accessibility API and
captures prefer on-screen windows; System Events cannot find the Settings Clear button (it reports the label as
empty), so buttons are pressed through the native accessibility API.



## Entry icons (2026-11-15)

Milestone 4, R5. A real-app check with the owner's permission: a copy of the Debug app, a scratch library holding
`v0.59.0.txt`, `space-age.bp.txt`, `bp.txt`, and `RS.txt`, a separate preferences domain, and the R3 release in
`.cache/renderer-assets`. Rows were selected and books opened through accessibility actions only (no keystrokes or
clicks); window captures stayed in the scratch directory.

| Check | Result |
|---|---|
| Folder rows (ICN-1) | Kind symbol, then the root's icons in slot order, then the name: R and S signals for the RS latch, four item icons for the Space Age book, the legendary quality icon for `bp.txt`, two parameter signals for `v0.59.0.txt` |
| Inspector tile (ICN-2) | Four icons in the 2 × 2 grid (Space Age book), two side by side (`v0.59.0.txt`), three in the top-left, top-right, bottom-left slots (`v0.59.0.txt` `1.4`), one with its badge (`bp.txt` `8`) |
| Planets (ICN-11) | Nauvis, Vulcanus, Gleba, Fulgora, and Aquilo icons in `v0.59.0.txt` book `1` rows and the inspector |
| Quality badges | Legendary badges in the bottom-left corner of row and inspector icons (`bp.txt` `4`, `6`, `7`, `8`) |
| No icons (ICN-3) | Book entries without icons show the kind symbol only |
| Quit | Quit through the app menu; no worker left; the preferences domain was removed |

Seen but outside R5: tagged names still lose their tags (`bp.txt` shows "(2026-06)", "U235", "Carbon fiber"), which
R6 changes; and right after selecting a large entry the preview area briefly showed an empty checkerboard, with no
Waiting or Rendering text, before the image appeared. The latter is to be checked in R10's smoke run.

## Milestone 4 smoke runs (2026-11-15)

R10, with the owner's permission: `just app-smoke --assets .cache/renderer-assets` and `just app-smoke` on the Debug
app built after R9, each on its own scratch library and preferences domain. With assets 31 of 31 checks passed; without
assets 27 passed and 5 were skipped for needing a release (worker count, warnings, Copy Image, background, release
change). The four new checks:

| Check | With assets | Without assets |
|---|---|---|
| Rows name their entry icons (ICN-1) | Pass: "icons: signal R; signal S" | Pass |
| A tagged root label stays the item name (ICN-5, ICN-6, ICN-8) | Pass: read as `legendary (2026-06)` | Pass: read as `[quality=legendary](2026-06)` |
| Warnings count and list (WRN-1, WRN-2) | Pass: "1 warning"; popover lists "1 × Unsupported entity: ee-infinity-loader (8)" | Skipped |
| Copy Image gives the cached PNG (IMG-1) | Pass: 2,290,116 bytes, equal to the cache file | Skipped |

Visual check of R6 to R9 from the captures: icons for rich-text tags in book rows (`bp.txt`: U235, Carbon fiber, Iron
plate), the path bar, and the inspector title; item icons in Statistics rows; the warnings button beside Open in Window
and its popover. One defect: rows whose names held tag icons were taller than the others, because the 16-point inline
icon exceeded the text line. Inline icons are now 14 points in rows, the sidebar, and the path bar, and 20 points in
the inspector title, lowered to stay within the line; the acceptance runs (R11) confirm it. Seen, not changed: the
inspector header's 48-point icon tile makes the header a little taller, so with the default window height its last
line (Folder) scrolls under the preview, as the header's height cap (milestone 3) intends.

Follow-up (owner, 2026-11-15): icons in rows were too small, the kind symbol then looked too small beside them, and
the inspector header hid its last lines. Row icons are now 24 points with the kind symbol in the same square, tag
icons 20 points in the sidebar and path bar, the inspector tile 64 points with 28-point title icons, and the header may
use up to 45% of the inspector's height. A real-app check (accessibility actions and window captures only) showed one
row height, the kind symbols matching the icons, and the whole header (Updated, Created, Size, Folder) for the RS latch
and `bp.txt` entry 6. Rows with tag icons in their names were still 3 to 4 points taller; the minimum row height is now
the icon size plus 12 points, to be confirmed in the acceptance runs.


## Statistics by inventory tab (2026-11-16)

From the owner's walkthrough: the Statistics tab listed every item twice, once under Construction items and again
under Placement, Modules, Equipment, or Other inserted. The owner chose to group the items by the game's inventory
tabs. The tab now shows each construction item once, in one section per tab (Logistics, Production, Intermediate
products, Space, Combat, and Unsorted for the game's catch-all tab), in the game's order, then Equipment requests.
This needed the game's inventory order in the prototype map (schema 2, see the
[statistics contract](../contracts/Statistics.md#prototype-data)), so the statistics reference was regenerated from
Factorio 2.1.24 ([asset preparation](../development/Asset-Preparation.md#regenerate)).

| Check | Result |
| --- | --- |
| Regenerated map against the previous one | Only `schema`, `itemGroups`, `itemSubgroups`, and each item's `subgroup` and `order` differ; every item resolves to a tab |
| `evaluate-statistics.mjs` | 347 passed, 1 expected failure (`ee-infinity-loader`), as before |
| `just statistics-golden` against the previous golden | All 348 expected results identical; only the map and reference calculator hashes changed |
| `just statistics-test` | 13 of 13 pass |
| `just tools-check` | Pass, with the three adapted copied files recorded in `tools/provenance.json` |
| `just lint` | No findings |
| `just test` | Four Swift test runs (43, 69, 99, and 34 tests, none skipped, including both statistics parity suites and the private map), 4 Python asset-release tests, and the artwork check (406 files) pass |
| `just app-build` | Pass, no warnings |

New tests: `PrototypeMapTests` reads the inventory order and refuses items or rows that do not resolve, a missing
order, and schema 1; `StatisticsModelTests` checks tabs and their order with a module and fuel, and STA-2 now requires
the tabs together to list exactly the CLI's `constructionItems`, each once and under its own tab. Not yet checked in
the real app: the owner's look at the new tab.
