set positional-arguments

default:
    @just --list

# Build the native libraries and executable scaffolds. No Node required.
build:
    sh tools/swift.sh build

# Test source preservation, bounded decoding, and real JavaScriptCore planner execution.
test:
    sh tools/swift.sh test --filter 'OriginalSourceTests|BlueprintCodecTests|NativeLibraryTests|LibraryCommandTests|AssetReleaseTests|PlannerRuntimeTests|NativePainterTests|PreviewProcessTests|PreviewIntegrationTests'
    python3 tools/test-asset-release.py

# Exercise native metadata, process exclusion, CLI workflows, and crash recovery.
storage-test:
    sh tools/swift.sh test --filter 'NativeLibraryTests|LibraryCommandTests'

# Verify offline asset inventory, hashes, profiles, and declared frame bounds.
asset-test:
    sh tools/swift.sh test --filter AssetReleaseTests

# Run native CLI commands; export stdout contains only source bytes.
library *args:
    sh tools/swift.sh run fb-native "$@"

# Run focused codec admission, preservation, and selected-entry export checks.
codec-test:
    sh tools/swift.sh test --filter BlueprintCodecTests

# Print the currently available CLI capabilities.
release:
    sh tools/swift.sh run fb-native release

# Run the planner loading/empty-diagram probe. Does not paint images.
planner-test:
    sh tools/swift.sh run preview-probe --self-test

# Exercise native composition and supervised worker success/failure paths without private assets.
renderer-test:
    sh tools/swift.sh test --filter 'PlannerRuntimeTests|NativePainterTests|PreviewProcessTests|PreviewIntegrationTests'
    python3 tools/test-asset-release.py

# Render a standalone source or selected book leaf using a verified private asset release.
preview *args:
    sh tools/swift.sh run preview-probe "$@"

# Install locked development dependencies without package lifecycle scripts.
tools-install:
    npm ci --prefix tools --ignore-scripts --no-audit --no-fund --cache .cache/npm

# Rebuild the committed JavaScriptCore resource from vendored source.
planner-build:
    npm run --prefix tools planner:build

# Check that the committed resource matches pinned source and bundler output.
planner-check:
    npm run --prefix tools planner:check

# Verify copied sources, fixture hashes, local dependency versions, and references.
tools-check:
    node tools/check-foundation.mjs

# Import the local asset pipeline without launching Factorio.
assets-check:
    node tools/asset-preparation/build-assets.mjs --check

# Run the retained statistics reference cases against the private prototype map.
statistics-test:
    npm test --prefix tools
