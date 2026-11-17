#!/bin/sh
# Builds the thin Xcode app target with derived data and package checkouts kept under .cache/.
# Like tools/swift.sh --disable-sandbox, it turns off Xcode's manifest sandbox and the compiler's sandbox for macro
# plugins, neither of which can nest inside sandbox-exec (tools/check-independence.py).
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-Debug}
case "$configuration" in
Debug | Release) ;;
*)
    echo 'Usage: tools/xcode.sh [Debug|Release] [xcodebuild arguments...]' >&2
    exit 2
    ;;
esac
[ "$#" -gt 0 ] && shift
export CLANG_MODULE_CACHE_PATH="$project_root/.cache/clang"
exec xcodebuild \
    -project "$project_root/App/Cyano.xcodeproj" \
    -scheme Cyano \
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$project_root/.cache/xcode" \
    -clonedSourcePackagesDirPath "$project_root/.cache/xcode-packages" \
    -packageCachePath "$project_root/.cache/xcode-package-cache" \
    -quiet \
    -IDEPackageSupportDisableManifestSandbox=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' \
    build "$@"
