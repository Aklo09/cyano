#!/usr/bin/env python3
"""Build and test a relocated native scaffold and app with selected paths and networking denied."""

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
    for directory in ['Sources', 'Tests', 'App']:
        shutil.copytree(root / directory, destination / directory)
    (destination / 'tools').mkdir()
    for tool in ['swift.sh', 'xcode.sh']:
        shutil.copy2(root / 'tools' / tool, destination / 'tools' / tool)
    denied = [root] + [path.resolve() for path in args.deny_path]
    profile = '(version 1) (allow default) (deny network*) ' + ' '.join(
        f'(deny file-read* (subpath {sandbox_literal(path)}))' for path in denied
    )
    environment = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin')
    for command in [
        ['sh', 'tools/swift.sh', 'test', '--filter', 'OriginalSourceTests|BlueprintCodecTests|NativeLibraryTests|LibraryCommandTests|AssetReleaseTests|PlannerRuntimeTests|NativePainterTests|PreviewProcessTests|PreviewIntegrationTests|LibraryPreviewTests'],
        ['.build/debug/fb-native', 'release'],
        ['.build/debug/preview-probe', '--self-test'],
        ['sh', 'tools/xcode.sh', 'Debug'],
    ]:
        subprocess.run(
            ['/usr/bin/sandbox-exec', '-p', profile, *command],
            cwd=destination, env=environment, check=True,
        )

    # Launching the app moved to the scripted smoke run (`just app-smoke`, milestone 3 A17).
    print('PASS: relocated native build, tests, executables, and app build; original checkout and requested paths '
          'unreadable; networking denied; no Node on PATH.')
