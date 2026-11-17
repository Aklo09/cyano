#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -eq 0 ]; then
    echo 'Usage: tools/swift.sh <build|test|run|package> [arguments...]' >&2
    exit 2
fi
swift_command=$1
shift
export CLANG_MODULE_CACHE_PATH="$project_root/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.cache/swift-modules"
# Tests delete and replace items; keep their removed originals out of the user's Trash.
if [ "$swift_command" = test ] && [ -z "${CYANO_TRASH_DIRECTORY:-}" ]; then
    export CYANO_TRASH_DIRECTORY="$project_root/.cache/test-trash"
    rm -rf "$CYANO_TRASH_DIRECTORY"
fi
exec swift "$swift_command" \
    --package-path "$project_root" \
    --cache-path "$project_root/.cache/swiftpm" \
    --config-path "$project_root/.cache/swiftpm-config" \
    --security-path "$project_root/.cache/swiftpm-security" \
    --disable-sandbox "$@"
