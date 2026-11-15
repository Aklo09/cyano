#!/usr/bin/env python3
"""Scripted smoke run of the macOS app (milestone 3, A17).

Launches a scratch copy of the built app offline, on a scratch library made from committed fixtures and a separate
preferences domain, drives it with keystrokes and menu commands through System Events, checks each step, and saves
window captures and a report under the output directory (default `.cache/smoke/<time>`, ignored by Git).

It takes over the keyboard and brings the app forward for a few minutes: keep hands off while it runs. The terminal
needs Accessibility and Screen Recording access. The clipboard text is saved first and restored at the end.
Without `--assets`, the checks that need a verified release are reported as skipped.
"""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = 'Factorio Blueprint Library'
FIXTURES = ROOT / 'Tests/LibraryCoreTests/Fixtures/Blueprints'
PLANNER_BOOK = ROOT / 'tools/vendor/fpsr/fixtures/decode/06-book-with-planner.txt'

# Native helper (System Events reports some SwiftUI button labels as empty):
#   windows <pid>               document-sized windows (layer 0, >= 100 pt) on any Space, with on-screen state
#   titles <pid>                titles of the app's accessibility windows (visible ones), as JSON
#   press <pid> <window> <label>  presses the first button titled or described <label> in that window
#   texts <pid> <window>        the window's static texts and labels, one per line
#   select <pid> <window> <text>  clicks the first row (in the window or its sheets) showing <text>
#   pasteboard-png <pid> <file>   writes the clipboard's PNG data to <file>; fails when there is none
HELPER_SOURCE = r'''
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
let pid = Int32(arguments[2])!
let app = AXUIElementCreateApplication(pid)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func window(_ title: String) -> AXUIElement? {
    (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).first { string($0, kAXTitleAttribute) == title }
}
func json(_ value: Any) { print(String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!) }

switch arguments[1] {
case "windows":
    let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    json(all.compactMap { info -> [String: Any]? in
        guard (info[kCGWindowOwnerPID as String] as? Int32) == pid, (info[kCGWindowLayer as String] as? Int) == 0,
            let bounds = info[kCGWindowBounds as String] as? [String: Any], (bounds["Height"] as? Double ?? 0) >= 100
        else { return nil }
        return ["id": info[kCGWindowNumber as String] as? Int ?? 0, "title": info[kCGWindowName as String] as? String ?? "",
                "onscreen": info[kCGWindowIsOnscreen as String] as? Bool ?? false]
    })
case "titles":
    json((attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).map { string($0, kAXTitleAttribute) })
case "press":
    func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 16 { return nil }
        if string(element, kAXRoleAttribute) == "AXButton",
            [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute)].contains(arguments[4])
        { return element }
        for child in children(element) { if let found = find(child, depth: depth + 1) { return found } }
        return nil
    }
    guard let target = window(arguments[3]), let button = find(target, depth: 0),
        AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    else { print("not pressed"); exit(1) }
    print("pressed")
case "select":
    func row(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 16 { return nil }
        if string(element, kAXRoleAttribute) == "AXRow" {
            func shows(_ element: AXUIElement, _ depth: Int) -> Bool {
                if (attribute(element, kAXValueAttribute) as? String) == arguments[4] { return true }
                return depth < 4 && children(element).contains { shows($0, depth + 1) }
            }
            if shows(element, 0) { return element }
        }
        for child in children(element) { if let found = row(child, depth: depth + 1) { return found } }
        return nil
    }
    // A real click: setting the row's selected attribute is not seen by SwiftUI's selection.
    // An open sheet first: the same text can also be in the window behind it (a sidebar folder).
    let sheets = window(arguments[3]).map { children($0).filter { string($0, kAXRoleAttribute) == "AXSheet" } } ?? []
    guard let target = window(arguments[3]),
        let found = sheets.lazy.compactMap({ row($0, depth: 0) }).first ?? row(target, depth: 0),
        let position = attribute(found, kAXPositionAttribute), let size = attribute(found, kAXSizeAttribute)
    else { print("not found"); exit(1) }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    let point = CGPoint(x: origin.x + min(60, extent.width / 2), y: origin.y + extent.height / 2)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(60_000)
    }
    print("clicked")
case "pasteboard-png":
    guard let data = NSPasteboard.general.data(forType: .png) else { print("no png"); exit(1) }
    try! data.write(to: URL(fileURLWithPath: arguments[3]))
    print(data.count)
case "texts":
    func collect(_ element: AXUIElement, depth: Int) {
        if depth > 16 { return }
        if string(element, kAXRoleAttribute) == "AXStaticText", let value = attribute(element, kAXValueAttribute) as? String {
            print(value)
        }
        // Rows such as comments carry their text as a label.
        let label = string(element, kAXDescriptionAttribute)
        if !label.isEmpty { print(label) }
        for child in children(element) { collect(child, depth: depth + 1) }
    }
    if let target = window(arguments[3]) { collect(target, depth: 0) }
default:
    exit(2)
}
'''

KEY = {'tab': 48, 'return': 36, 'escape': 53, 'space': 49, 'down': 125, 'up': 126, 'delete': 51, 'f': 3, 'a': 0,
       'c': 8, 'k': 40, 'm': 46, 'n': 45, 'w': 13, 'q': 12, 'v': 9, 'y': 16, '1': 18, '9': 25, 'plus': 24, 'comma': 43}


def sandbox_literal(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


class Smoke:
    def __init__(self, args):
        self.args = args
        self.out = args.output
        self.results = []
        self.process = None
        self.suite = f'local.fb.library.smoke-{uuid.uuid4()}'
        self.app = self.out / f'{APP_NAME}.app'
        self.library = self.out / 'Library'
        self.helper = self.out / 'smoke-helper'
        self.capture_count = 0
        self.saved_clipboard = None

    # Recording

    def record(self, name, ok, detail=''):
        status = 'SKIP' if ok is None else ('PASS' if ok else 'FAIL')
        self.results.append({'check': name, 'status': status, 'detail': detail})
        print(f'{status:4}  {name}' + (f' — {detail}' if detail else ''), flush=True)
        return ok

    # Processes and windows

    def run(self, command, **kwargs):
        return subprocess.run(command, capture_output=True, text=True, **kwargs)

    def cli(self, *arguments):
        result = self.run([str(self.args.cli), *arguments])
        if result.returncode != 0:
            raise SystemExit(f'fb-native {" ".join(arguments)} failed: {result.stderr.strip()}')
        return json.loads(result.stdout) if result.stdout.startswith('{') else result.stdout

    def windows(self):
        if not self.process or self.process.poll() is not None:
            return []
        result = self.run([str(self.helper), 'windows', str(self.process.pid)])
        return json.loads(result.stdout) if result.returncode == 0 else []

    def titles(self):
        """Titles of the visible windows (the window-server list also has hidden ones, such as a closed library)."""
        if not self.process or self.process.poll() is not None:
            return []
        result = self.run([str(self.helper), 'titles', str(self.process.pid)])
        return sorted(json.loads(result.stdout)) if result.returncode == 0 else []

    def wait(self, condition, timeout=10.0, interval=0.25):
        deadline = time.monotonic() + timeout
        while True:
            value = condition()
            if value or time.monotonic() >= deadline:
                return value
            time.sleep(interval)

    def workers(self):
        result = self.run(['/usr/bin/pgrep', '-f', str(self.app / 'Contents/MacOS/preview-worker')])
        return [line for line in result.stdout.split() if line.strip()]

    # Input

    def system_events(self, script, delay=0.6):
        target = f'tell application "System Events" to tell (first process whose unix id is {self.process.pid})'
        result = self.run(['/usr/bin/osascript', '-e', f'{target} to {script}'])
        time.sleep(delay)
        return result

    def front(self):
        self.system_events('set frontmost to true', delay=1.0)

    def key(self, name, *modifiers, delay=0.6):
        using = f' using {{{", ".join(m + " down" for m in modifiers)}}}' if modifiers else ''
        self.run(['/usr/bin/osascript', '-e', f'tell application "System Events" to key code {KEY[name]}{using}'])
        time.sleep(delay)

    def type(self, text, delay=0.8):
        self.run(['/usr/bin/osascript', '-e', f'tell application "System Events" to keystroke {json.dumps(text)}'])
        time.sleep(delay)

    def raise_window(self, title):
        self.system_events(f'perform action "AXRaise" of window {json.dumps(title)}', delay=0.4)
        self.front()

    def find(self, text):
        """Selects the first item whose name matches `text` (or the current folder's first row for ""), through Find
        and Tab, with the main window key."""
        self.raise_window('Library')
        self.key('escape', delay=0.4)  # cancels a sheet a failed step left open, so failures don't cascade
        self.key('f', 'command', delay=0.5)
        self.key('a', 'command', delay=0.3)
        if text:
            self.type(text, delay=1.0)
        else:
            self.key('delete', delay=1.0)  # an empty search shows the current folder
        self.key('tab', delay=1.5)

    def static_texts(self, title):
        return self.run([str(self.helper), 'texts', str(self.process.pid), title]).stdout

    def press(self, window, label, delay=1.0):
        pressed = self.run([str(self.helper), 'press', str(self.process.pid), window, label]).returncode == 0
        time.sleep(delay)
        return pressed

    def capture(self, label, title):
        # On-screen first: a dismissed window can stay in the window-server list, hidden.
        matching = sorted((w for w in self.windows() if w['title'] == title), key=lambda w: not w['onscreen'])
        window = matching[0] if matching else None
        if not window:
            return None
        self.capture_count += 1
        path = self.out / f'{self.capture_count:02d}-{label}.png'
        self.run(['/usr/sbin/screencapture', '-x', '-o', f'-l{window["id"]}', str(path)])
        return path if path.exists() else None

    # Launch and quit

    def launch(self):
        denied = [path.resolve() for path in self.args.deny_path]
        # A GUI app needs local window-server connections, so only IP networking is denied (as the independence
        # check did when it launched the app).
        profile = '(version 1) (allow default) (deny network* (remote ip) (local ip)) ' + ' '.join(
            f'(deny file-read* (subpath {sandbox_literal(path)}))' for path in denied)
        executable = self.app / 'Contents/MacOS' / APP_NAME
        # Replaced and deleted originals go to a scratch directory, never the owner's Trash.
        environment = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin',
                           FB_NATIVE_TRASH_DIRECTORY=str(self.out / 'trash'))
        self.process = subprocess.Popen(
            ['/usr/bin/sandbox-exec', '-p', profile, str(executable), '-FBNativeDefaultsSuite', self.suite],
            env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def quit(self):
        if not self.process or self.process.poll() is not None:
            return True
        self.front()
        self.key('q', 'command', delay=0.5)
        try:
            self.process.wait(timeout=15)
            return True
        except subprocess.TimeoutExpired:
            return False

    def defaults(self, **values):
        for key, value in values.items():
            self.run(['/usr/bin/defaults', 'write', self.suite, key, str(value)])

    # Steps

    def prepare(self):
        self.out.mkdir(parents=True, exist_ok=False)
        (self.out / 'trash').mkdir()
        if not self.args.app.exists():
            raise SystemExit(f'No app at {self.args.app}: run `just app-build` first.')
        shutil.copytree(self.args.app, self.app, symlinks=True)
        source = self.out / 'smoke-helper.swift'
        source.write_text(HELPER_SOURCE)
        compiled = self.run(['/usr/bin/xcrun', 'swiftc', '-o', str(self.helper), str(source)],
                            env={'PATH': '/usr/bin:/bin', 'HOME': str(Path.home()),
                                 'CLANG_MODULE_CACHE_PATH': str(self.out / '.clang')})
        if compiled.returncode != 0:
            raise SystemExit('Could not build the smoke helper: ' + compiled.stderr)
        self.cli('init', str(self.library))
        self.cli('folder-create', str(self.library), '', 'Books')
        self.cli('import', str(self.library), str(FIXTURES / 'RS.txt'))
        for name in ['2i', '4i', '6i']:
            self.cli('import', str(self.library), str(FIXTURES / f'{name}_Assembler.txt'), '--name', f'Assembler {name}')
        self.cli('import', str(self.library), str(FIXTURES / 'v0.59.0.txt'), '--folder', 'Books')
        self.cli('import-unpacked', str(self.library), str(PLANNER_BOOK), '--folder', 'Books')
        # Milestone 4: a root label with a rich-text tag, and a leaf whose render reports a warning (a modded entity).
        self.cli('import', str(self.library), str(FIXTURES / 'bp.txt'), '--folder', 'Books')
        books = next(i for i in self.cli('list', str(self.library))['result']['items'] if i['name'] == 'Tileable factories')
        leaf = self.out / 'warning-leaf.txt'
        self.cli('export', str(self.library), books['id'], '--entry', '1.1', '--output', str(leaf))
        self.cli('import', str(self.library), str(leaf), '--name', 'Warning leaf')
        latch = next(i for i in self.cli('list', str(self.library))['result']['items'] if i['name'] == 'Simple RS Latch')
        self.cli('comment-add', str(self.library), latch['id'], 'Smoke-run comment')
        self.saved_clipboard = self.run(['/usr/bin/pbpaste']).stdout

    def first_launch(self):
        """The check that the independence check used to make: the app launches offline and shows a window."""
        self.launch()
        shown = self.wait(lambda: self.windows(), timeout=10)  # any Space: the app is not activated yet
        exited = self.process.poll() is not None
        self.record('Launches offline with scratch preferences and shows a window', bool(shown) and not exited,
                    f'windows {[w["title"] for w in shown]}' if shown else 'no window within 10 s')
        if not shown:
            return False
        self.front()
        self.record('With no library, the window is library selection', self.titles() == [APP_NAME],
                    f'{self.titles()}')
        self.capture('selection', APP_NAME)
        self.record('Quits cleanly from selection', self.quit())
        return True

    def select_row(self, window, text, delay=0.8):
        selected = self.run([str(self.helper), 'select', str(self.process.pid), window, text]).returncode == 0
        time.sleep(delay)
        return selected

    def library_texts(self):
        return self.static_texts('Library')

    def relaunch_library(self, label):
        self.launch()
        reopened = self.wait(lambda: 'Library' in self.titles(), timeout=10)
        self.record(label, bool(reopened), f'{self.titles()}')
        if reopened:
            self.front()
        return reopened

    def everyday_workflows(self, assets):
        """Library workflows that need no assets (exit condition: they work offline, with or without a release)."""
        self.find('latch')
        if assets:
            time.sleep(3)
        self.capture('inspector', 'Library')
        self.key('1', 'command', delay=2 if assets else 0.8)
        self.capture('statistics', 'Library')
        if not assets:
            texts = self.library_texts()
            self.record('Without assets, the preview and statistics say what they need (PRV-9, STA-4)',
                        'No asset release is configured' in texts and 'Statistics need the game data' in texts)

        # Copy String gives the exact imported bytes (EXP).
        self.find('assembler 2i')
        self.run(['/usr/bin/pbcopy'], input='')
        self.key('c', 'command', delay=1.0)
        # Bytes, not text: text mode would turn the fixture's CRLF into LF.
        copied = subprocess.run(['/usr/bin/pbpaste'], capture_output=True).stdout
        self.record('Copy String copies the exact original string', copied == (FIXTURES / '2i_Assembler.txt').read_bytes(),
                    f'{len(copied)} bytes')

        # Import from the clipboard (IMP).
        self.run(['/usr/bin/pbcopy'], input=(FIXTURES / 'Hazard_Patterns.txt').read_text())
        self.raise_window('Library')
        self.key('v', 'command', 'shift', delay=1.5)
        self.key('return', 'command', delay=3)
        self.record('Import from Clipboard adds and selects the item', 'concrete patterns' in self.library_texts())

        # Add a comment (COM).
        self.find('latch')
        self.key('k', 'command', 'option', delay=1.0)
        self.type('Added by the smoke run', delay=0.5)
        self.key('return', 'command', delay=2)
        texts = self.library_texts()
        self.record('Add Comment adds a comment', 'Added by the smoke run' in texts and 'Smoke-run comment' in texts)
        self.key('escape', delay=0.5)

        # New folder, move into it, move to Trash (ORG).
        self.find('')
        self.key('n', 'command', 'shift', delay=1.5)
        self.key('a', 'command', delay=0.3)
        self.type('Smoke folder', delay=0.5)
        self.key('return', delay=2)
        self.record('New Folder creates and names a folder', 'Smoke folder' in self.library_texts())
        self.find('assembler 6i')
        self.key('m', 'command', 'control', delay=1.5)
        chosen = self.select_row('Library', 'Smoke folder')
        self.key('return', delay=2.5)
        sheet_closed = 'Cancel' not in self.library_texts()
        self.record('Move To moves the item into the chosen folder', chosen and sheet_closed,
                    f'folder clicked {chosen}; sheet closed {sheet_closed} (the disk check after quit confirms)')
        self.find('assembler 4i')
        self.key('delete', 'command', delay=1.5)
        pressed = self.press('Library', 'Move to Trash', delay=2)
        self.record('Move to Trash removes the item after confirmation', pressed)
        self.capture('organized', 'Library')

        # Books open like folders by stored index (BOOK).
        self.find('tileable')
        self.key('down', 'command', delay=3)
        texts = self.library_texts()
        self.record('Open (⌘↓) shows a book\'s entries', 'Tileable factories' in texts and ', entry ' in texts)
        self.capture('book', 'Library')
        self.key('up', 'command', delay=1.5)

    def milestone4(self, assets):
        """Icons in names and rows, render warnings, and Copy Image (milestone 4, R5 to R9)."""
        # ICN-1: rows name their entry icons for VoiceOver, with or without a release.
        self.find('latch')
        texts = self.library_texts()
        self.record('Rows name their entry icons (ICN-1)', 'icons: signal R; signal S' in texts,
                    'row label ends with the icon names' if 'icons: signal R' in texts else 'no icon names')
        self.capture('entry-icons', 'Library')

        # ICN-5, ICN-6, ICN-8: the imported tagged label keeps its tag; with a release the tag is an icon, read by name.
        self.find('2026-06')
        time.sleep(1.5)
        texts = self.library_texts()
        spoken = 'legendary (2026-06)' in texts
        written = '[quality=legendary](2026-06)' in texts
        self.record('A tagged root label is kept as the item name; its tag shows as an icon only with a release '
                    '(ICN-5, ICN-6, ICN-8)', spoken if assets else written,
                    f'read as {"icon name" if spoken else "tag text" if written else "neither"}')
        self.capture('tagged-name', 'Library')
        self.key('down', 'command', delay=3)
        self.capture('tagged-book', 'Library')
        self.key('up', 'command', delay=1.5)

        # ICN-9: Statistics rows draw item icons (visual check in the capture).
        self.find('assembler 2i')
        self.key('1', 'command', delay=3 if assets else 0.8)
        self.capture('statistics-icons', 'Library')

        if not assets:
            for name in ['A preview with warnings shows their count and list (WRN-1, WRN-2)',
                         'Copy Image puts the cached PNG on the clipboard (IMG-1)']:
                self.record(name, None, 'needs --assets')
            return
        # WRN-1, WRN-2: the leaf renders with one warning; the button opens the list.
        self.find('warning leaf')
        shown = self.wait(lambda: '1 render warning' in self.library_texts(), timeout=60, interval=1)
        opened = shown and self.press('Library', '1 render warning', delay=1.5)
        # The popover may be its own untitled accessibility window.
        listed = any('Unsupported entity: ee-infinity-loader' in self.static_texts(title) for title in ['Library', ''])
        self.capture('render-warnings', 'Library')
        self.key('escape', delay=0.6)
        self.record('A preview with warnings shows their count and list (WRN-1, WRN-2)', bool(shown and listed),
                    f'button {bool(shown)}, pressed {bool(opened)}, listed {listed}')

        # IMG-1: Copy Image gives exactly the cached PNG.
        self.raise_window('Library')
        self.key('c', 'command', 'option', delay=1.5)
        copied = self.out / 'copied-image.png'
        got = self.run([str(self.helper), 'pasteboard-png', str(self.process.pid), str(copied)]).returncode == 0
        item = next(i for i in self.cli_list_unowned() if i['name'] == 'Warning leaf') if got else None
        cached = sorted((self.library / 'cache' / item['id']).glob('*.png')) if item else []
        same = got and any(path.read_bytes() == copied.read_bytes() for path in cached)
        self.record('Copy Image puts the cached PNG on the clipboard (IMG-1)', same,
                    f'clipboard PNG {copied.stat().st_size if got else 0} bytes; {len(cached)} cached images')

    def cli_list_unowned(self):
        """Items from the library's files, read without the CLI (the app owns the library while it runs)."""
        items = []
        for metadata in self.library.rglob('*.json'):
            if metadata.parent.name in ('cache', 'operations') or metadata.name.startswith('.'):
                continue
            try:
                record = json.loads(metadata.read_text())
            except (OSError, ValueError):
                continue
            if 'sourceSha256' in record:
                items.append({'id': record['id'], 'name': record.get('displayNameOverride') or metadata.stem})
        return items

    def worker_check(self, assets):
        """One worker at most under real renders (deferred from A12): three previews opened in a row before anything
        is cached (selecting an item renders it for the inspector, so this runs first)."""
        if not assets:
            self.record('At most one preview worker while three windows render', None, 'needs --assets')
            return
        peak, seen = 0, 0
        self.find('assembler')
        for step in range(3):
            if step:
                self.raise_window('Library')
                self.key('down', delay=0.3)
            self.key('space', delay=0.2)
            count = len(self.workers())
            peak, seen = max(peak, count), seen + count
        deadline = time.monotonic() + 60
        idle_since = None
        while time.monotonic() < deadline:
            count = len(self.workers())
            peak, seen = max(peak, count), seen + count
            idle_since = (idle_since or time.monotonic()) if count == 0 else None
            if idle_since and time.monotonic() - idle_since > 3:
                break
            time.sleep(0.05)
        self.record('At most one preview worker while three windows render', peak <= 1 and seen > 0,
                    f'peak {peak}; windows {self.titles()}')
        for title in ['Assembler 2i', 'Assembler 4i', 'Assembler 6i']:
            self.capture('preview-' + title.split()[-1], title)

    def preview_windows(self, assets):
        # Space in the list opens a preview window (PRV-3; deferred from A12); opening it again reuses it (PRV-4).
        self.find('latch')
        self.key('space', delay=0.5)
        opened = self.wait(lambda: 'Simple RS Latch' in self.titles(), timeout=10)
        self.record('Space in the list opens a preview window', bool(opened), f'{self.titles()}')
        self.find('latch')
        self.key('space', delay=1.5)
        count = self.titles().count('Simple RS Latch')
        self.record('Opening the same item again brings its window forward (PRV-4)', count == 1, f'{count} windows')
        if assets:
            time.sleep(3)
        before = self.capture('preview-window', 'Simple RS Latch')

        if assets:
            # Changing the background keeps the zoom and starts no render (PRV-8a).
            self.raise_window('Simple RS Latch')
            zoom = [t for t in self.static_texts('Simple RS Latch').split('\n') if t.startswith('Zoom ')]
            self.system_events('click menu item "Transparent" of menu 1 of menu item "Background" of menu 1 of '
                               'menu bar item "View" of menu bar 1', delay=1.0)
            after_zoom = [t for t in self.static_texts('Simple RS Latch').split('\n') if t.startswith('Zoom ')]
            self.record('Changing the background keeps the zoom and starts no render (PRV-8a)',
                        zoom == after_zoom and not self.workers(), f'{zoom} → {after_zoom}')
            self.capture('preview-transparent', 'Simple RS Latch')
        else:
            self.record('Changing the background keeps the zoom and starts no render (PRV-8a)', None,
                        'needs --assets')

        # Rename with a preview window open: the window follows (deferred from A12).
        self.find('latch')
        self.key('return', delay=0.8)
        self.key('a', 'command', delay=0.3)
        self.type('Latch renamed', delay=0.5)
        self.key('return', delay=1.5)
        renamed = self.wait(lambda: 'Latch renamed' in self.titles(), timeout=5)
        self.record('Renaming the item renames its open preview window', bool(renamed), f'{self.titles()}')

        # Replace with a preview window open: the window shows the new source (deferred from A12).
        self.find('latch renamed')
        self.system_events('click menu item "Replace Source…" of menu 1 of menu bar item "Library" of menu bar 1',
                           delay=1.5)
        self.run(['/usr/bin/pbcopy'], input=(FIXTURES / '4x_Rocket_Silo.txt').read_text())
        self.key('v', 'command', delay=1.0)
        self.key('return', 'command', delay=3 if assets else 1.5)
        replaced = 'Latch renamed' in self.titles()
        after = self.capture('preview-replaced', 'Latch renamed')
        if assets and before and after:
            differs = hashlib.sha256(before.read_bytes()).digest() != hashlib.sha256(after.read_bytes()).digest()
            self.record('Replacing the source keeps the window open and shows the new image', replaced and differs,
                        f'window open {replaced}; image changed {differs}')
        else:
            self.record('Replacing the source keeps the window open', replaced, f'{self.titles()}')

        # A release change reaches open preview windows (deferred from A12).
        if assets:
            settings = f'{APP_NAME} Settings'
            self.key('comma', 'command', delay=1.5)
            pressed = self.press(settings, 'Clear', delay=1.5)
            self.raise_window(settings)
            self.key('w', 'command', delay=1.0)
            texts = self.static_texts('Latch renamed')
            cleared = 'No asset release is configured' in texts
            self.record('Clearing the asset release updates open preview windows', pressed and cleared,
                        f'Clear pressed {pressed}; window text: ' + ' / '.join(texts.split('\n')[:3]))
            self.capture('preview-no-assets', 'Latch renamed')
        else:
            self.record('Clearing the asset release updates open preview windows', None, 'needs --assets')

    def library_session(self):
        self.defaults(reopenLibraryPath=self.library.resolve())
        if self.args.assets:
            self.defaults(assetReleasePath=self.args.assets.resolve())
        assets = self.args.assets is not None
        if not self.relaunch_library('Relaunch reopens the last library'):
            return
        self.capture('library', 'Library')
        self.worker_check(assets)
        self.everyday_workflows(assets)
        self.milestone4(assets)
        self.preview_windows(assets)

        # Quitting with preview windows open; they are not restored (PRV-13).
        open_before = self.titles()
        self.record('Quits cleanly with preview windows open', self.quit(), f'{open_before}')
        if not self.relaunch_library('Relaunch reopens the library'):
            return
        self.record('Preview windows are not restored after a relaunch (PRV-13)', self.titles() == ['Library'],
                    f'{self.titles()}')

        # Closing the library closes its preview windows (deferred from A12).
        self.find('latch renamed')
        self.key('space', delay=2)
        self.raise_window('Library')
        self.key('w', 'command', 'shift', delay=2)
        closed = self.wait(lambda: self.titles() == [APP_NAME], timeout=8)
        self.record('Closing the library closes its preview windows and shows selection', bool(closed),
                    f'{self.titles()}')
        self.capture('closed', APP_NAME)
        self.record('Quits cleanly', self.quit())
        self.record('No preview worker remains after quit', not self.workers(), f'{len(self.workers())} left')
        state = self.cli('owner', str(self.library))['result']['state']
        self.record('The library is idle after quit', state == 'idle', state)

        # The library on disk agrees with what the app showed.
        items = {i['name']: i['folder'] for i in self.cli('list', str(self.library))['result']['items']}
        expected = {'concrete patterns': '', 'Assembler 6i': 'Smoke folder', 'Latch renamed': ''}
        wrong = {name: items.get(name) for name, folder in expected.items() if items.get(name) != folder}
        self.record('fb-native list matches: imported, moved, renamed, and deleted items',
                    not wrong and 'Assembler 4i' not in items, f'unexpected {wrong}' if wrong else '')
        trashed = sorted(p.name for p in (self.out / 'trash').iterdir())
        self.record('Deleted and replaced originals went to the run\'s trash, not the owner\'s', len(trashed) >= 2,
                    f'{trashed}')

    def cleanup(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
        if self.saved_clipboard is not None:
            self.run(['/usr/bin/pbcopy'], input=self.saved_clipboard)
        self.run(['/usr/bin/defaults', 'delete', self.suite])
        Path.home().joinpath('Library/Preferences', self.suite + '.plist').unlink(missing_ok=True)

    def report(self):
        failed = [r for r in self.results if r['status'] == 'FAIL']
        lines = [f'# App smoke run {self.out.name}', '', f'App: `{self.args.app}`',
                 f'Assets: `{self.args.assets}`' if self.args.assets else 'Assets: none', '',
                 '| Check | Result | Detail |', '| --- | --- | --- |']
        lines += [f'| {r["check"]} | {r["status"]} | {r["detail"]} |' for r in self.results]
        lines += ['', 'Captures: ' + ', '.join(sorted(p.name for p in self.out.glob('*.png')))]
        (self.out / 'report.md').write_text('\n'.join(lines) + '\n')
        (self.out / 'results.json').write_text(json.dumps(self.results, indent=2) + '\n')
        print(f'\n{len(self.results) - len(failed)} of {len(self.results)} checks did not fail; report: '
              f'{self.out / "report.md"}')
        return not failed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', type=Path,
                        default=ROOT / '.cache/xcode/Build/Products/Debug' / f'{APP_NAME}.app')
    parser.add_argument('--cli', type=Path, default=ROOT / '.build/debug/fb-native')
    parser.add_argument('--assets', type=Path, help='a verified asset release, for the preview and worker checks')
    parser.add_argument('--deny-path', type=Path, action='append', default=[],
                        help='paths the app may not read, such as the original web checkout')
    parser.add_argument('--output', type=Path, help='a new directory (default .cache/smoke/<time>)')
    args = parser.parse_args()
    if not Path('/usr/bin/sandbox-exec').exists():
        parser.error('The smoke run requires macOS sandbox-exec.')
    if not args.cli.exists():
        parser.error(f'No CLI at {args.cli}: run `just build` first.')
    args.output = (args.output or ROOT / '.cache/smoke' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')).resolve()
    smoke = Smoke(args)
    try:
        smoke.prepare()
        if smoke.first_launch():
            smoke.library_session()
    finally:
        smoke.cleanup()
    sys.exit(0 if smoke.report() else 1)


main()
