# Local asset and planner tooling

Prepare private assets without depending on the original web repository.
Native builds consume committed planner resources and require no Node runtime.

## Pinned sources

The vendored fpsr source uses revision `2f7dc70f2681de530402556f757006e904e692d5`.
Its renderer sources, pipeline sources, owned placeholder artwork, and required fixtures are included.
Its license remains alongside those files.

The copied web-project source uses revision `bf80a5e3c5a3db942d1ab872462f157912883650`.
Its calculator and preparation helpers now resolve local dependencies and fixtures.

[The inventory](../../tools/provenance.json) records original paths, revisions, byte counts, and hashes.
Adapted files retain their original hashes alongside their current hashes.
Unmodified supplied blueprint strings are packaged as test resources.

## Install and verify

Use the Node version in the root `.nvmrc`.
Run these commands from the repository root:

```sh
just tools-install
just tools-check
just planner-check
just assets-check
```

The toolchain pins fpsr 0.0.3, esbuild 0.28.1, and tsx 4.23.0.
It pins sharp 0.35.5 and fflate 0.8.3.
The lockfile records transitive dependencies and integrity hashes.
These dependencies belong to development tooling, outside the Swift package.

The planner check rebuilds in memory and compares committed resources.
The generated metadata identifies all 42 bundled source inputs by hash.
The native resource includes fpsr's license.

The asset check imports the vendored pipeline through tsx's Node loader.
It neither launches the game nor regenerates assets.

## Private inputs

The existing prepared profile and prototype map were copied into:

```text
private-assets/
  2.1.23/
  statistics-reference/
    prototype-map.json
```

These files are ignored by Git and excluded from native package resources.
Native build and planner-loading checks do not require them.
For native image rendering, assemble these inputs into a new private release using the
[preview harness guide](Native-Preview.md#prepare-a-private-release).
Run the retained statistics cases when the map is present:

```sh
just statistics-test
```

## Regeneration status

The asset builder now uses the vendored pipeline and project-local Node dependencies.
Its help describes the required Factorio installation and new private output directory:

```sh
node tools/asset-preparation/build-assets.mjs --help
```

Asset generation requires Factorio 2.1.23 and refuses an existing output directory.
It stages isolated game configuration and mods beneath the selected private output.
The normal game profile is not used.

Full asset regeneration and game-reference generation have not been exercised in this port.
Their copied outputs remain useful inputs, without qualifying a new exporter run.
The initial foundation does not replace Node-based preparation with native tools.
