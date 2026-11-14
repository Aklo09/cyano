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
