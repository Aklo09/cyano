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
