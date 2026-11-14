# Factorio Blueprint Library for macOS

Keep original blueprint strings, books, planners, and comments in an ordinary local directory.
This project is an independent native port of the original web application.

**Current status:** native storage and the library CLI are implemented, including organization, replacement,
deletion, book unpacking, maintenance, and offline asset verification.
The standalone renderer paints real previews through supervised native workers.
Saved-item previews reuse validated derived caches.
Construction statistics report a blueprint's building requirements and footprint from a verified asset release.
The macOS app scaffold builds and launches offline; its interface is being built in milestone 3.

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
just codec-test
just storage-test
just asset-test
just release
just planner-test
just renderer-test
```

Native builds need no Node installation, game process, or private assets.
The committed planner resource runs through Apple's system JavaScriptCore framework.
The probe supports its original planner self-test and real image rendering with a verified private asset release.

The Swift wrapper keeps compiler and package caches inside this repository.
It disables SwiftPM's subprocess sandbox for these development commands.

Build and open the macOS app (Xcode 27.2 required):

```sh
just app-build
just app-run
```

See the [app guide](docs/development/App.md) for its structure, signing, and caches.

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
These retained JavaScript cases, with `just statistics-golden`, provide the reference the native statistics are checked against.

## Documentation

- **Read the roadmap:** [approved native plan](docs/planning/macOS-Plan.md).
- **Build the app:** [app guide](docs/development/App.md) and [validation](docs/validation/App.md).
- **Inspect evidence:** [foundation validation](docs/validation/Foundation.md).
- **Use the codec:** [native interfaces](docs/development/Codec.md) and [validation](docs/validation/Codec.md).
- **Manage a library:** [CLI guide](docs/development/Library-CLI.md), [storage contract](docs/contracts/Storage.md), and [validation](docs/validation/Storage.md).
- **Inspect command completion:** [organization and maintenance validation](docs/validation/Library-Commands.md).
- **Prepare assets:** [local tooling guide](docs/development/Asset-Preparation.md).
- **Render previews:** [native harness guide](docs/development/Preview.md) and [renderer validation](docs/validation/Renderer.md).
- **Cache saved-item previews:** [library preview guide](docs/development/Library-Previews.md), [contract](docs/contracts/Preview-Cache.md), and [validation](docs/validation/Library-Previews.md).
- **Calculate statistics:** [statistics guide](docs/development/Statistics.md), [contract](docs/contracts/Statistics.md), and [validation](docs/validation/Statistics.md).
- **Check milestones:** [milestone 1](docs/validation/Milestone-1.md) and [milestone 2](docs/validation/Milestone-2.md) acceptance records.
- **Resume development:** [session notes](docs/Session-Notes.md).
- **Find documents:** [documentation map](docs/README.md).

## License

Project code uses the [MIT License](LICENSE).
Vendored fpsr code retains its [MIT notice](tools/vendor/fpsr/LICENSE).
Copied files and adaptations are recorded in [the provenance inventory](tools/provenance.json).

Factorio artwork is copyright Wube Software Ltd. and remains private.
Game artwork is excluded from source control and native package resources.
This project is not affiliated with or endorsed by Wube Software.
