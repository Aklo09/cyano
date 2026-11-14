# Native macOS app

Build and run the Factorio Blueprint Library app from this repository.
Behavior is specified in the [app spec](../specs/Native-App.md) and the [screen specs](../specs/Native-App-Screens.md);
the delivery plan is [milestone 3](../planning/Milestone-3.md).

## Structure

| Part | Location | Contents |
| --- | --- | --- |
| Interface and logic | `Sources/LibraryApp` (SwiftPM target and product `LibraryApp`) | Scenes, views, and their models; builds and tests with SwiftPM like the other targets |
| App bundle | `App/FactorioBlueprintLibrary.xcodeproj`, `App/Sources` | One app target whose only source is the `@main` entry point, linking the local package product `LibraryApp` |
| Build wrapper | `tools/xcode.sh` | Runs `xcodebuild` for the shared scheme with derived data and package caches under `.cache/` |

Put new interface code in `Sources/LibraryApp`, not in `App/Sources`, so it stays testable under `just test`.
The Xcode project holds only bundle settings: change them in Xcode or in `project.pbxproj`, and keep the shared
scheme `FactorioBlueprintLibrary` committed.

## Commands

```sh
just app-build            # Debug app
just app-build Release    # Release app
just app-run              # build the Debug app and open it
```

The app is written to `.cache/xcode/Build/Products/<configuration>/Factorio Blueprint Library.app`.
Open `App/FactorioBlueprintLibrary.xcodeproj` in Xcode for SwiftUI previews and debugging; Xcode then uses its own
derived data location instead of `.cache/`.

`tools/xcode.sh` passes `-IDEPackageSupportDisableManifestSandbox=YES`, the Xcode counterpart of
`tools/swift.sh --disable-sandbox`: Xcode's manifest sandbox cannot run inside the `sandbox-exec` profile used by
the independence check. If `xcodebuild` reports that a required plug-in failed to load, run
`sudo xcodebuild -runFirstLaunch` once to install Xcode's system components.

## Bundle identity and signing

| Setting | Value |
| --- | --- |
| Name | Factorio Blueprint Library |
| Bundle identifier | `local.fb.library` |
| Version | 0.1.0 (build 1), a placeholder until the owner sets a versioning scheme |
| Minimum system | macOS 27.0, Apple Silicon (`arm64`), matching `Package.swift` |
| Signing | Ad-hoc ("Sign to Run Locally", identity `-`), no team |
| App Sandbox | Off (milestone 3 decision 2); hardened runtime off |
| Entitlements | Debug: `get-task-allow` only, for debugging; Release: none |

Developer ID signing and notarization belong to distribution, which is outside v1.

## Independence

`python3 tools/check-independence.py --deny-path ../fb` copies `App/` and both wrappers into a relocated tree,
builds the Debug app there with the original checkout and the given paths unreadable and networking denied, then
launches it and requires a window within 10 seconds. The launch denies IP networking only: a blanket
`deny network*` also blocks the local connections a GUI app needs, and the app then shows no window.

## Pending work

- **Preview worker:** the app must carry `preview-worker` inside its bundle before rendering (A12); embedding a
  SwiftPM executable in the Xcode target is not set up yet.
- **Isolated launches:** once the app reopens the last library at launch (LIB-11), scripted launches need isolated
  preferences so they never open the owner's real library (A5, A17).
- **Tests:** the `LibraryApp` target has no test suite yet; the session layer (A4) adds one to `just test`.
