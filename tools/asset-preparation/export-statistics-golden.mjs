// Writes reference statistics for every case the original evaluation used, for the native parity test (S5).
// Output is derived from the private prototype map, so it stays in the ignored .cache/ directory.
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { calculateBlueprintStatistics } from '../reference/blueprint-statistics.mjs';
import { loadStatisticsCases } from './statistics-cases.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const { values } = parseArgs({
  options: {
    map: { type: 'string', default: path.join(root, 'private-assets/statistics-reference/prototype-map.json') },
    output: { type: 'string', default: path.join(root, '.cache/statistics-golden.json') },
  },
});
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const mapBytes = await readFile(values.map);
const map = JSON.parse(mapBytes);
const referenceBytes = await readFile(new URL('../reference/blueprint-statistics.mjs', import.meta.url));
const { inputs, cases } = await loadStatisticsCases({
  examples: path.join(root, 'Tests/LibraryCoreTests/Fixtures/Blueprints'),
  upstream: path.join(root, 'tools/vendor/fpsr'),
});

const rows = cases.map(job => {
  // `string` is the standalone blueprint the native side decodes; `path` is the JS library's array position.
  const row = { id: job.id, source: job.source, path: job.path, label: job.label ?? null, string: job.string };
  const before = JSON.stringify(job.blueprint);
  try {
    row.expected = calculateBlueprintStatistics(job.blueprint, map);
  } catch (error) {
    row.error = error.message;
  }
  if (JSON.stringify(job.blueprint) !== before) throw new Error(`Reference changed its input: ${job.id}`);
  return row;
});
rows.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
if (new Set(rows.map(row => row.id)).size !== rows.length) throw new Error('Duplicate case identifiers');

// No timestamps or machine paths: identical inputs produce identical bytes.
const golden = {
  schema: 1,
  generator: 'tools/asset-preparation/export-statistics-golden.mjs',
  referenceSha256: sha256(referenceBytes),
  prototypeMapSha256: sha256(mapBytes),
  gameVersion: map.gameVersion,
  inputs,
  cases: rows,
};
const bytes = JSON.stringify(golden, null, 1) + '\n';
await mkdir(path.dirname(values.output), { recursive: true });
await writeFile(values.output, bytes);
const failed = rows.filter(row => row.error).length;
console.log(
  `Wrote ${rows.length} cases (${failed} reference errors) to ${path.relative(root, values.output)}; sha256 ${sha256(bytes)}`,
);
