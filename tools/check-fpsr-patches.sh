#!/bin/sh
# Rebuild tools/vendor/fpsr from its pristine upstream baseline plus the local patches,
# and require the result to match the working tree exactly.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
patches="$project_root/tools/vendor/fpsr-patches"
base=$(cat "$patches/BASE")
work="$project_root/.cache/fpsr-patches-check"
rm -rf "$work"
mkdir -p "$work"
git -C "$project_root" archive "$base" tools/vendor/fpsr | tar -x -C "$work"
count=0
for patch in "$patches"/[0-9][0-9][0-9][0-9]-*.patch; do
    [ -e "$patch" ] || continue
    # patch(1), not git apply: inside this repository git would resolve paths against its root.
    patch --quiet --forward -p1 -d "$work/tools/vendor/fpsr" <"$patch"
    count=$((count + 1))
done
if ! diff -r "$work/tools/vendor/fpsr" "$project_root/tools/vendor/fpsr"; then
    echo "tools/vendor/fpsr differs from $base plus $count patches; regenerate the patch (docs/development/Asset-Preparation.md#local-fpsr-patches)." >&2
    exit 1
fi
rm -rf "$work"
echo "fpsr patches verified: $base plus $count patches reproduce tools/vendor/fpsr."
