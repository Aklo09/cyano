#!/usr/bin/env python3
"""Build and test a relocated native scaffold with selected paths and networking denied."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--deny-path', type=Path, action='append', default=[])
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
if not Path('/usr/bin/sandbox-exec').exists():
    parser.error('This qualification requires macOS sandbox-exec.')

def sandbox_literal(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

with tempfile.TemporaryDirectory(prefix='fb-native-independent-') as temporary:
    destination = Path(temporary)
    shutil.copy2(root / 'Package.swift', destination / 'Package.swift')
    for directory in ['Sources', 'Tests']:
        shutil.copytree(root / directory, destination / directory)
    (destination / 'tools').mkdir()
    shutil.copy2(root / 'tools/swift.sh', destination / 'tools/swift.sh')
    denied = [root] + [path.resolve() for path in args.deny_path]
    profile = '(version 1) (allow default) (deny network*) ' + ' '.join(
        f'(deny file-read* (subpath {sandbox_literal(path)}))' for path in denied
    )
    environment = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin')
    for command in [
        ['sh', 'tools/swift.sh', 'test', '--filter', 'OriginalSourceTests|BlueprintCodecTests|NativeLibraryTests|LibraryCommandTests|AssetReleaseTests|PlannerRuntimeTests|NativePainterTests|PreviewProcessTests|PreviewIntegrationTests|LibraryPreviewTests'],
        ['.build/debug/fb-native', 'release'],
        ['.build/debug/preview-probe', '--self-test'],
    ]:
        subprocess.run(
            ['/usr/bin/sandbox-exec', '-p', profile, *command],
            cwd=destination, env=environment, check=True,
        )
    print('PASS: relocated native build, tests, and executables; original checkout and requested paths unreadable; networking denied; no Node on PATH.')
