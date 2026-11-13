# Factorio Blueprint Library for macOS

Keep original blueprint strings, books, planners, and comments in an ordinary local directory.
This project is an independent native port of the original web application.

**Current status:** milestone 1's independent foundation is implemented.
The CLI exposes build information; the preview probe exercises JavaScriptCore.
Library operations, image painting, and the macOS interface are still pending.

## Requirements

- **Native development:** Xcode 27.2, Swift 6.4.2, macOS 27.2, Apple Silicon are validated.
- **Command shortcuts:** just 1.54.0 is validated.
- **Development tooling:** Node 24.22.1 and npm 12.2.1 are validated.
- **Private artwork:** prepared assets require your licensed Factorio 2.1.23 installation.

The package currently targets macOS 27.0 or later using Swift tools 6.4.
Older systems and Intel Macs have not been qualified.

## Build and inspect

Run from the repository root:

```sh
just build
just test
just release
just planner-test
```

Native builds need no Node installation, game process, or private assets.
The committed planner resource runs through Apple's system JavaScriptCore framework.
The probe currently plans empty upgrade and deconstruction diagrams, without painting images.

The Swift wrapper keeps compiler and package caches inside this repository.
It disables SwiftPM's subprocess sandbox for these development commands.

## Development tooling

```sh
just tools-install
just tools-check
just planner-check
just assets-check
```

These commands install locked dependencies, verify provenance, and check the local asset pipeline.
Package lifecycle scripts are disabled during installation.
The asset check imports the pipeline without launching Factorio.

Run `just planner-build` after intentionally changing the planner source or adapter.
Commit the regenerated resource and metadata with the source change.

Run `just statistics-test` when the private prototype map is available.
These retained JavaScript cases provide reference behavior for the future Swift statistics port.

## Documentation

- **Read the roadmap:** [approved native plan](docs/planning/Native-macOS-Plan.md).
- **Inspect evidence:** [foundation validation](docs/validation/Native-Foundation.md).
- **Prepare assets:** [local tooling guide](docs/development/Asset-Preparation.md).
- **Resume development:** [session notes](docs/Session-Notes.md).
- **Find documents:** [documentation map](docs/README.md).

## License

Project code uses the [MIT License](LICENSE).
Vendored fpsr code retains its [MIT notice](tools/vendor/fpsr/LICENSE).
Copied files and adaptations are recorded in [the provenance inventory](tools/provenance.json).

Factorio artwork is copyright Wube Software Ltd. and remains private.
Game artwork is excluded from source control and native package resources.
This project is not affiliated with or endorsed by Wube Software.
