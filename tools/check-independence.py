#!/usr/bin/env python3
"""Build and test a relocated native scaffold and app with selected paths and networking denied."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

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

    # Launch the built app offline. A GUI app cannot connect to the window server under a blanket
    # `deny network*`, which also covers local sockets, so the launch denies IP networking only.
    app = destination / '.cache/xcode/Build/Products/Debug/Factorio Blueprint Library.app'
    executable = app / 'Contents/MacOS/Factorio Blueprint Library'
    launch_profile = '(version 1) (allow default) (deny network* (remote ip) (local ip)) ' + ' '.join(
        f'(deny file-read* (subpath {sandbox_literal(path)}))' for path in denied
    )
    counter_source = destination / 'window-count.swift'
    counter_source.write_text(
        'import CoreGraphics\n'
        'let pid = Int32(CommandLine.arguments[1])!\n'
        'let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []\n'
        'print(all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid'
        ' && ($0[kCGWindowLayer as String] as? Int) == 0 }.count)\n'
    )
    counter = destination / 'window-count'
    subprocess.run(['/usr/bin/xcrun', 'swiftc', '-o', str(counter), str(counter_source)], env=environment, check=True)
    process = subprocess.Popen(
        ['/usr/bin/sandbox-exec', '-p', launch_profile, str(executable)],
        cwd=destination, env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        windows = 0
        for _ in range(20):
            time.sleep(0.5)
            if process.poll() is not None:
                raise SystemExit(f'FAIL: the app exited during launch with status {process.returncode}.')
            windows = int(subprocess.run(
                [str(counter), str(process.pid)], capture_output=True, text=True, check=True).stdout)
            if windows:
                break
        if not windows:
            raise SystemExit('FAIL: the app showed no window within 10 seconds.')
    finally:
        process.terminate()
        process.wait(timeout=10)
    print('PASS: relocated native build, tests, executables, and app build; original checkout and requested paths '
          'unreadable; networking denied (IP only for the app launch, which showed its window); no Node on PATH.')
