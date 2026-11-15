#!/usr/bin/env python3
"""Copy prepared private sprites/statistics into a new offline release; never overwrite a destination."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sprites', type=Path, required=True)
parser.add_argument('--prototype-map', type=Path, required=True)
parser.add_argument('--destination', type=Path, required=True)
parser.add_argument('--id', required=True)
args = parser.parse_args()

def require(condition, message):
    if not condition:
        raise ValueError(message)

def json_bytes(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False) + '\n').encode()

def open_source(path, maximum):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'Unsafe or shared source file')
        require(0 <= info.st_size <= maximum, 'Source exceeds its byte limit')
        return os.fdopen(descriptor, 'rb'), info
    except BaseException:
        os.close(descriptor)
        raise

def unchanged(stream, before, count):
    after = os.fstat(stream.fileno())
    require(count == before.st_size == after.st_size and before.st_mtime_ns == after.st_mtime_ns
            and before.st_ctime_ns == after.st_ctime_ns, 'Source changed during assembly')

def read_json(path, maximum):
    stream, before = open_source(path, maximum)
    with stream:
        data = stream.read(maximum + 1)
        require(len(data) <= maximum, 'Source exceeds its byte limit')
        unchanged(stream, before, len(data))
    return json.loads(data)

require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,99}', args.id), 'Invalid release id')
sprites = args.sprites.resolve(strict=True)
prototype_map = args.prototype_map.resolve(strict=True)
destination = args.destination.absolute()
require(sprites.is_dir(), 'Sprites must be a directory')
require(destination.parent.is_dir(), 'Destination parent must exist')
destination = destination.parent.resolve() / destination.name
require(destination != sprites and sprites not in destination.parents, 'Destination cannot overlap source sprites')
require(not destination.exists() and not destination.is_symlink(), 'Destination already exists')
require(prototype_map.stat().st_size <= 16 * 1024**2, 'Prototype JSON exceeds its limit')
manifest_path = sprites / 'manifest.json'
require(manifest_path.lstat().st_size <= 4 * 1024**2, 'Sprite manifest exceeds its limit')

members = []
directories = []
total = 0
def inspect(path, relative):
    global total
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'Unsafe or shared source file')
    require(info.st_size >= 0 and info.st_size <= 2 * 1024**3 - total, 'Asset release exceeds 2 GiB')
    total += info.st_size
    members.append((path, relative))
    require(len(members) <= 10000, 'Too many files')

def visit(directory, prefix='', depth=0):
    require(depth <= 32, 'Sprite hierarchy is too deep')
    with os.scandir(directory) as stream:
        for entry in stream:
            require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,254}', entry.name), 'Unsafe sprite member name')
            relative = prefix + entry.name
            if entry.is_dir(follow_symlinks=False):
                directories.append(relative)
                require(len(directories) <= 10000, 'Too many directories')
                visit(Path(entry.path), relative + '/', depth + 1)
            else:
                inspect(Path(entry.path), 'sprites/' + relative)

visit(sprites)
inspect(prototype_map, 'statistics/prototype-map.json')
names = [name for _, name in members]
require(len(set(name.lower() for name in names)) == len(names), 'Colliding asset paths')
manifest = read_json(manifest_path, 4 * 1024**2)
prototype = read_json(prototype_map, 16 * 1024**2)
mods = ['base', 'elevated-rails', 'quality', 'recycler', 'space-age']
require(manifest.get('schema') == 2 and prototype.get('schema') == 1, 'Unsupported asset schemas')
require(manifest.get('gameVersion') == prototype.get('gameVersion') == '2.1.24', 'Unsupported game version')
require(sorted(manifest['mods']) == mods and sorted(prototype['mods']) == mods, 'Unsupported mod profile')
require(all(prototype['mods'][mod] == '2.1.24' for mod in mods), 'Unsupported mod version')

# Exclusive directory creation claims this build target. Failures leave partial evidence for inspection.
destination.mkdir(mode=0o700)
(destination / 'sprites').mkdir()
(destination / 'statistics').mkdir()
for name in sorted(directories, key=lambda name: (name.count('/'), name)):
    (destination / 'sprites' / name).mkdir()
files = []
copied_bytes = 0
for source, relative in sorted(members, key=lambda entry: entry[1]):
    stream, info = open_source(source, 2 * 1024**3 - copied_bytes)
    target = destination / relative
    digest = hashlib.sha256()
    count = 0
    with stream, target.open('xb') as output:
        for chunk in iter(lambda: stream.read(65536), b''):
            count += len(chunk)
            require(count <= info.st_size, 'Source grew during assembly')
            output.write(chunk)
            digest.update(chunk)
        unchanged(stream, info, count)
    copied_bytes += count
    files.append(dict(path=relative, bytes=count, sha256=digest.hexdigest()))

profile = dict(gameVersion='2.1.24', mods=[dict(name=mod, version=prototype['mods'][mod]) for mod in manifest['mods']])
inventory = {file['path']: file for file in files}
provenance = dict(assembly='fb-asset-release-schema-1', source='existing-private-exports',
    spriteManifestSha256=inventory['sprites/manifest.json']['sha256'],
    prototypeMapSha256=inventory['statistics/prototype-map.json']['sha256'])
identity_fields = dict(schema=1, profile=profile, provenance=provenance, files=files)
release = dict(identity_fields, id=args.id, identity=hashlib.sha256(json_bytes(identity_fields)).hexdigest())
with (destination / 'release.json').open('xb') as output:
    output.write(json_bytes(release))
print(json.dumps(dict(root=str(destination), files=len(files), totalBytes=sum(file['bytes'] for file in files))))
