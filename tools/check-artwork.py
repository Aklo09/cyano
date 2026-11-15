#!/usr/bin/env python3
"""Artwork check (milestone 4, R10; spec GEN-9).

Factorio artwork and release data must never be committed, added to package resources, or built into the app: the
app reads them at runtime from the owner's own release. This check fails when any of these holds such a file:

- the files Git tracks;
- package resources (`Sources/*/Resources`);
- every built app bundle under `.cache/xcode/Build/Products` (skipped when none is built).

A file is reported by name (atlas images, render databases, `release.json`, `prototype-map.json`) or, where
`private-assets/` exists, because its SHA-256 equals a private file's. Only private files of a matching size are
hashed, so the check stays fast. The preparation tools' staging folders (`profile/` and `game-work/`, an isolated
game configuration with project-written mods such as `tools/asset-preparation/statistics-reference.lua`) hold no
artwork and are not compared. `--self-test` plants copies in a scratch bundle and expects them to be found.
"""

import argparse
import fnmatch
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
NAME_PATTERNS = ['atlas.*.webp', 'render-db.*.json', 'release.json', 'prototype-map.json']
STAGING = {'profile', 'game-work'}
BUNDLES = ROOT / '.cache/xcode/Build/Products'


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for block in iter(lambda: handle.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def files_under(directory):
    for parent, _, names in os.walk(directory):
        for name in names:
            path = Path(parent) / name
            if path.is_file() and not path.is_symlink():
                yield path


def tracked_files(root):
    listed = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'], capture_output=True)
    if listed.returncode != 0:
        raise SystemExit('git ls-files failed: ' + listed.stderr.decode(errors='replace'))
    return [root / name for name in listed.stdout.decode().split('\0') if name and (root / name).is_file()]


def candidates(root, bundles):
    """(label, path) for every file this check covers."""
    found = [('git', path) for path in tracked_files(root)]
    for resources in sorted(root.glob('Sources/*/Resources')):
        found += [('package resources', path) for path in files_under(resources)]
    if bundles.is_dir():
        for app in sorted(bundles.glob('*/*.app')):
            found += [(f'app bundle {app.relative_to(bundles)}', path) for path in files_under(app)]
    return found


class PrivateFiles:
    """Private files by size, hashed only when a candidate of the same size appears."""

    def __init__(self, directory):
        self.by_size = {}
        self.hashes = {}
        if directory.is_dir():
            for path in files_under(directory):
                if STAGING.isdisjoint(path.relative_to(directory).parts[:-1]):
                    self.by_size.setdefault(path.stat().st_size, []).append(path)

    def match(self, path):
        size = path.stat().st_size
        if size == 0 or size not in self.by_size:
            return None
        digest = sha256(path)
        for private in self.by_size[size]:
            if private not in self.hashes:
                self.hashes[private] = sha256(private)
            if self.hashes[private] == digest:
                return private
        return None


def check(root, private_dir, bundles):
    private = PrivateFiles(private_dir)
    problems = []
    covered = candidates(root, bundles)
    for label, path in covered:
        relative = path.relative_to(root) if path.is_relative_to(root) else path
        if any(fnmatch.fnmatch(path.name, pattern) for pattern in NAME_PATTERNS):
            problems.append(f'{label}: {relative} is named like release data')
            continue
        same = private.match(path)
        if same:
            problems.append(f'{label}: {relative} has the same bytes as {same.relative_to(private_dir)}')
    return covered, problems


def self_test():
    with tempfile.TemporaryDirectory(prefix='fb-native-artwork-') as scratch:
        root = Path(scratch) / 'repo'
        private_dir = root / 'private-assets'
        bundles = root / '.cache/xcode/Build/Products'
        (private_dir / '2.1.24').mkdir(parents=True)
        app = bundles / 'Debug/Test.app/Contents/Resources'
        app.mkdir(parents=True)
        atlas = private_dir / '2.1.24/atlas.0123.webp'
        atlas.write_bytes(b'RIFF private atlas bytes')
        (private_dir / 'game-work/mods').mkdir(parents=True)
        (private_dir / 'game-work/mods/control.lua').write_text('-- project-written mod\n')
        (root / 'control.lua').write_text('-- project-written mod\n')
        subprocess.run(['git', 'init', '-q', str(root)], check=True)
        (root / '.gitignore').write_text('private-assets/\n.cache/\n')
        (root / 'notes.txt').write_text('ordinary tracked file\n')
        subprocess.run(['git', '-C', str(root), 'add', '.gitignore', 'notes.txt', 'control.lua'], check=True)
        _, clean = check(root, private_dir, bundles)
        if clean:
            raise SystemExit(f'self-test: a clean tree was reported: {clean}')
        shutil.copyfile(atlas, app / 'renamed.bin')
        shutil.copyfile(atlas, app / 'atlas.0123.webp')
        _, planted = check(root, private_dir, bundles)
        if len(planted) != 2 or not any('same bytes' in p for p in planted) or not any('named' in p for p in planted):
            raise SystemExit(f'self-test: the planted copies were not both found: {planted}')
    print('Artwork check self-test passed: planted copies found by name and by bytes.')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--self-test', action='store_true', help='check the check on a scratch tree')
    options = parser.parse_args()
    if options.self_test:
        self_test()
        return 0
    covered, problems = check(ROOT, ROOT / 'private-assets', BUNDLES)
    if problems:
        print('Factorio artwork or release data found where it must not be:')
        for problem in problems:
            print('  ' + problem)
        return 1
    hashed = 'compared with private-assets' if (ROOT / 'private-assets').is_dir() else 'no private-assets to compare'
    print(f'Artwork check passed: {len(covered)} files checked ({hashed}).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
