#!/usr/bin/env python3
"""Corpus qualification run (milestone 4, R1).

Imports the full supplied corpus (the nine committed fixtures and the vendored fpsr visual tests) into a scratch
library, renders every blueprint and planner leaf through `fb-native preview` with a verified private release, and
writes under the output directory (default `.cache/qualification/<time>`, ignored by Git):

- `report.json`: one record per leaf with its outcome, dimensions, timings, memory, warnings, and rail count;
- `index.html`: a contact sheet for the owner's review, with filters and a viewer that zooms to 100% and 400%;
- `images/`: copies of the rendered PNGs, derived from private artwork, so they never leave `.cache/`.

The library's own cache keeps the published previews. Exit status 1 means at least one leaf failed to render.
"""

import argparse
import base64
import datetime
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import time
import zlib

ROOT = Path(__file__).resolve().parent.parent
CORPUS = [
    *sorted((ROOT / 'Tests/LibraryCoreTests/Fixtures/Blueprints').glob('*.txt')),
    *sorted((ROOT / 'tools/vendor/fpsr/fixtures/visual-tests').glob('*/*.txt')),
]
LEAF_KINDS = ('blueprint', 'upgrade_planner', 'deconstruction_planner')
RAIL = re.compile(r'(^|-)rail($|-)')


def run_cli(cli, *args):
    """Runs one CLI command and returns its JSON envelope (the CLI reports failures in it, never only on stderr)."""
    done = subprocess.run([str(cli), *args], capture_output=True, text=True)
    try:
        return json.loads(done.stdout)
    except json.JSONDecodeError:
        return {'ok': False, 'error': {'code': 'NO_JSON', 'message': (done.stderr or done.stdout).strip()[:2000]}}


def decode(path):
    """Decodes a supplied string for enumeration only; the library stores and renders the exact bytes."""
    text = path.read_bytes().strip()
    return json.loads(zlib.decompress(base64.b64decode(text[1:])))


def leaves(document, path=()):
    """Yields (stored index path, kind, entry) for every blueprint and planner, following stored indices."""
    for kind in LEAF_KINDS:
        if kind in document:
            yield path, kind, document[kind]
            return
    book = document.get('blueprint_book')
    if book is None:
        return
    for child in book.get('blueprints', []):
        if isinstance(child.get('index'), int):
            yield from leaves(child, (*path, child['index']))


def rail_count(kind, entry):
    if kind != 'blueprint':
        return 0
    return sum(1 for e in entry.get('entities', []) if RAIL.search(e.get('name', '')) and 'railgun' not in e['name'])


def render_corpus(cli, assets, run_dir):
    library = run_dir / 'library'
    images = run_dir / 'images'
    images.mkdir(parents=True)
    initialized = run_cli(cli, 'init', str(library))
    if not initialized.get('ok'):
        sys.exit(f'init failed: {initialized}')
    records = []
    for source in CORPUS:
        relative = source.relative_to(ROOT).as_posix()
        imported = run_cli(cli, 'import', str(library), str(source))
        if not imported.get('ok'):
            records.append({'source': relative, 'ok': False, 'error': imported.get('error')})
            continue
        item = imported['result']['id']
        for path, kind, entry in leaves(decode(source)):
            entry_text = '.'.join(map(str, path))
            args = ['preview', str(library), item, '--assets', str(assets)]
            if path:
                args += ['--entry', entry_text]
            started = time.perf_counter()
            result = run_cli(cli, *args)
            wall = (time.perf_counter() - started) * 1000
            record = {
                'number': len(records) + 1, 'source': relative, 'entry': entry_text, 'kind': kind,
                'label': entry.get('label', ''), 'entities': len(entry.get('entities', [])),
                'tiles': len(entry.get('tiles', [])), 'rails': rail_count(kind, entry),
                'commandWallMs': round(wall, 1), 'ok': bool(result.get('ok')),
            }
            if record['ok']:
                preview = result['result']
                report = preview['report']
                image = f"images/{record['number']:03}.png"
                shutil.copyfile(library / preview['cachePath'], run_dir / image)
                record.update({
                    'image': image, 'width': report['width'], 'height': report['height'],
                    'pixelsPerTile': report.get('pixelsPerTile'),
                    'renderMs': round(preview['durationMs'], 1),
                    'supervisorWallMs': round(report['timingsMs'].get('supervisorWall', 0), 1),
                    'peakResidentBytes': report.get('peakResidentBytes'), 'warnings': report['warnings'],
                    'commandKinds': report.get('commandKinds', {}),
                })
            else:
                record['error'] = result.get('error')
            records.append(record)
            state = 'ok' if record['ok'] else f"FAILED {record['error'].get('code')}"
            print(f"{record['number']:3} {relative} {entry_text or 'root'}: {state}", flush=True)
    return records


def summary(records, assets_identity):
    rendered = [r for r in records if r.get('ok')]
    times = sorted(r['renderMs'] for r in rendered)
    memory = [r['peakResidentBytes'] for r in rendered if r.get('peakResidentBytes')]
    warned = [r for r in rendered if r['warnings']]
    return {
        'leaves': len(records), 'rendered': len(rendered), 'failed': len(records) - len(rendered),
        'withWarnings': len(warned), 'warnings': sum(len(r['warnings']) for r in warned),
        'withRails': sum(1 for r in records if r.get('rails')),
        'renderMs': {
            'min': times[0], 'median': round(statistics.median(times), 1), 'max': times[-1],
        } if times else None,
        'peakResidentMiB': round(max(memory) / 2**20, 1) if memory else None,
        'slowest': [
            {'source': r['source'], 'entry': r['entry'], 'renderMs': r['renderMs']}
            for r in sorted(rendered, key=lambda r: -r['renderMs'])[:5]
        ],
        'assetIdentity': assets_identity,
    }


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Corpus qualification</title>
<style>
:root { --bg: #f5f5f7; --card: #fff; --text: #1d1d1f; --muted: #555; --line: #d2d2d7; --bad: #b3261e; --warn: #8a5a00; }
@media (prefers-color-scheme: dark) { :root { --bg: #121212; --card: #1e1e1e; --text: #f2f2f2; --muted: #b0b0b0;
  --line: #3a3a3a; --bad: #ff8a80; --warn: #ffcc66; } }
body { margin: 0; padding: 16px; background: var(--bg); color: var(--text); font: 14px -apple-system, sans-serif; }
header { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: baseline; margin-bottom: 12px; }
h1 { font-size: 20px; margin: 0; } .muted { color: var(--muted); }
.controls { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
button, input { font: inherit; padding: 4px 10px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--card); color: var(--text); }
button[aria-pressed="true"] { border-color: currentColor; font-weight: 600; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 8px; cursor: pointer; }
.card:focus-visible { outline: 3px solid #0a84ff; }
.thumb { height: 180px; display: flex; align-items: center; justify-content: center; border-radius: 4px;
  background: repeating-conic-gradient(#8884 0 25%, transparent 0 50%) 0 0 / 16px 16px; }
.thumb img { max-width: 100%; max-height: 100%; }
.title { margin-top: 6px; font-weight: 600; overflow-wrap: anywhere; }
.meta { color: var(--muted); font-size: 12px; overflow-wrap: anywhere; }
.bad { color: var(--bad); font-weight: 600; } .warn { color: var(--warn); font-weight: 600; }
#viewer { position: fixed; inset: 0; display: none; flex-direction: column; background: var(--bg); z-index: 2; }
#viewer.open { display: flex; }
#viewer .bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; padding: 8px 16px;
  border-bottom: 1px solid var(--line); }
#stage { flex: 1; overflow: auto; background: repeating-conic-gradient(#8884 0 25%, transparent 0 50%) 0 0 / 16px 16px; }
#stage img { display: block; margin: auto; image-rendering: pixelated; }
#notes { padding: 8px 16px; max-height: 25vh; overflow: auto; border-top: 1px solid var(--line); font-size: 12px; }
</style></head><body>
<header><h1>Corpus qualification</h1><span class="muted" id="totals"></span></header>
<div class="controls" role="toolbar" aria-label="Filter">
  <button data-filter="all" aria-pressed="true">All</button><button data-filter="failed">Failed</button>
  <button data-filter="warnings">Warnings</button><button data-filter="rails">Rails</button>
  <button data-filter="planners">Planners</button>
  <input id="search" type="search" placeholder="Filter by file, entry, or label" aria-label="Filter by text">
</div>
<main class="grid" id="grid"></main>
<div id="viewer" role="dialog" aria-modal="true" aria-label="Preview">
  <div class="bar"><strong id="vtitle"></strong>
    <button data-zoom="fit">Fit</button><button data-zoom="1">100%</button><button data-zoom="4">400%</button>
    <button id="prev">Previous</button><button id="next">Next</button><button id="close">Close (Esc)</button></div>
  <div id="stage"><img id="vimg" alt=""></div><div id="notes"></div>
</div>
<script>
const DATA = __DATA__;
const grid = document.getElementById('grid'); let filter = 'all', shown = [], current = -1, zoom = 'fit';
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const t = DATA.summary;
document.getElementById('totals').textContent = `${t.rendered} of ${t.leaves} leaves rendered, ${t.failed} failed, ` +
  `${t.withWarnings} with warnings, ${t.withRails} with rails; median render ${t.renderMs ? t.renderMs.median : '-'} ms`;
function matches(r) {
  const q = document.getElementById('search').value.toLowerCase();
  if (q && !`${r.source} ${r.entry} ${r.label}`.toLowerCase().includes(q)) return false;
  if (filter === 'failed') return !r.ok;
  if (filter === 'warnings') return r.ok && r.warnings.length > 0;
  if (filter === 'rails') return r.rails > 0;
  if (filter === 'planners') return r.kind !== 'blueprint';
  return true;
}
function render() {
  shown = DATA.records.filter(r => r.number && matches(r));
  grid.innerHTML = shown.map((r, i) => `<div class="card" tabindex="0" data-i="${i}">
    <div class="thumb">${r.ok ? `<img loading="lazy" src="${r.image}" alt="">` : '<span class="bad">Failed</span>'}</div>
    <div class="title">${r.number}. ${esc(r.label) || '<span class="muted">(no label)</span>'}</div>
    <div class="meta">${esc(r.source.split('/').pop())} ${esc(r.entry || 'root')} · ${esc(r.kind.replaceAll('_', ' '))}</div>
    <div class="meta">${r.ok ? `${r.width} × ${r.height} · ${r.pixelsPerTile ?? '?'} px/tile · ${Math.round(r.renderMs)} ms` : `<span class="bad">${esc(r.error?.code)}</span>`}
    ${r.ok && r.warnings.length ? ` · <span class="warn">${r.warnings.length} warnings</span>` : ''}
    ${r.rails ? ` · ${r.rails} rails` : ''}</div></div>`).join('');
}
function open(i) {
  current = i; const r = shown[i]; if (!r) return;
  document.getElementById('vtitle').textContent = `${r.number}. ${r.label || '(no label)'} — ${r.source} ${r.entry || 'root'}`;
  const img = document.getElementById('vimg'); img.src = r.ok ? r.image : ''; img.alt = r.label || 'preview';
  const notes = r.ok ? (r.warnings.length ? r.warnings.map(w => `<div class="warn">${esc(w)}</div>`).join('') : 'No warnings.')
    : `<div class="bad">${esc(r.error?.code)}: ${esc(r.error?.message)}</div>`;
  document.getElementById('notes').innerHTML = notes;
  document.getElementById('viewer').classList.add('open'); applyZoom();
}
function applyZoom() {
  const img = document.getElementById('vimg'), r = shown[current]; if (!r || !r.ok) return;
  if (zoom === 'fit') { img.style.width = ''; img.style.maxWidth = '100%'; img.style.maxHeight = '100%'; }
  else { img.style.maxWidth = 'none'; img.style.maxHeight = 'none';
    img.style.width = `${r.width * Number(zoom) / devicePixelRatio}px`; }
}
document.querySelectorAll('[data-filter]').forEach(b => b.onclick = () => { filter = b.dataset.filter;
  document.querySelectorAll('[data-filter]').forEach(x => x.setAttribute('aria-pressed', x === b)); render(); });
document.getElementById('search').oninput = render;
document.querySelectorAll('[data-zoom]').forEach(b => b.onclick = () => { zoom = b.dataset.zoom; applyZoom(); });
grid.onclick = e => { const c = e.target.closest('.card'); if (c) open(Number(c.dataset.i)); };
grid.onkeydown = e => { const c = e.target.closest('.card'); if (c && e.key === 'Enter') open(Number(c.dataset.i)); };
document.getElementById('close').onclick = () => document.getElementById('viewer').classList.remove('open');
document.getElementById('prev').onclick = () => open(Math.max(0, current - 1));
document.getElementById('next').onclick = () => open(Math.min(shown.length - 1, current + 1));
document.onkeydown = e => { if (!document.getElementById('viewer').classList.contains('open')) return;
  if (e.key === 'Escape') document.getElementById('close').click();
  if (e.key === 'ArrowRight') document.getElementById('next').click();
  if (e.key === 'ArrowLeft') document.getElementById('prev').click(); };
render();
</script></body></html>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--assets', type=Path, default=ROOT / '.cache/renderer-assets',
                        help='verified private asset release (default .cache/renderer-assets)')
    parser.add_argument('--cli', type=Path, default=ROOT / '.build/release/fb-native',
                        help='fb-native executable (default: the release build)')
    parser.add_argument('--output', type=Path, default=ROOT / '.cache/qualification',
                        help='parent of the run directory (default .cache/qualification)')
    options = parser.parse_args()

    verified = run_cli(options.cli, 'assets-verify', str(options.assets))
    if not verified.get('ok'):
        sys.exit(f'The asset release does not verify: {verified.get("error")}')
    run_dir = options.output / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    run_dir.mkdir(parents=True)
    print(f'Corpus: {len(CORPUS)} files; run directory {run_dir}', flush=True)

    records = render_corpus(options.cli, options.assets, run_dir)
    result = {
        'schema': 1, 'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'corpus': [p.relative_to(ROOT).as_posix() for p in CORPUS],
        'summary': summary([r for r in records if 'number' in r], verified['result']['identity']),
        'importFailures': [r for r in records if 'number' not in r], 'records': [r for r in records if 'number' in r],
    }
    (run_dir / 'report.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    data = json.dumps({'summary': result['summary'], 'records': result['records']}, ensure_ascii=False)
    (run_dir / 'index.html').write_text(PAGE.replace('__DATA__', data.replace('</', '<\\/')))
    print(json.dumps(result['summary'], indent=2))
    print(f'Contact sheet: {run_dir / "index.html"}')
    return 1 if result['summary']['failed'] or result['importFailures'] else 0


if __name__ == '__main__':
    sys.exit(main())
