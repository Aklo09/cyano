import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { calculateBlueprintStatistics } from '../reference/blueprint-statistics.mjs';
import { createPrototypeMap } from './prototype-map.mjs';

const { values } = parseArgs({ options: { reference: { type: 'string' }, report: { type: 'string' } } });
for (const key of ['reference', 'report']) if (!values[key]) throw new Error(`Missing --${key}`);
const directory = path.resolve(values.reference);
const referenceBytes = await readFile(path.join(directory, 'reference.json'));
const reference = JSON.parse(referenceBytes);
const { cases, inputs } = JSON.parse(await readFile(path.join(directory, 'cases.json'), 'utf8'));
const map = createPrototypeMap(reference);
const mapBytes = JSON.stringify(map, null, 2) + '\n';
await writeFile(path.join(directory, 'prototype-map.json'), mapBytes);
const sorted = items => (Array.isArray(items) ? items : Object.values(items ?? {})).map(item => ({ name: item.name, quality: item.quality ?? 'normal', count: item.count }))
  .sort((a, b) => a.name.localeCompare(b.name) || a.quality.localeCompare(b.quality));
const results = [];
for (const job of cases) {
  const row = { id: job.id, source: job.source, path: job.path, label: job.label ?? null };
  try {
    const game = reference.cases.find(item => item.id === job.id);
    assert.ok(game, 'Missing game reference');
    assert.ok(!game.error, game.error);
    assert.ok(!game.footprint.error, game.footprint.error);
    assert.notEqual(game.importResult, 1, 'Game rejected import');
    const before = JSON.stringify(job.blueprint);
    const stats = calculateBlueprintStatistics(job.blueprint, map);
    assert.equal(JSON.stringify(job.blueprint), before, 'Statistics changed the input');
    assert.equal(stats.footprint.complete, true, stats.warnings.join('; '));
    const imported = { entities: Array.isArray(game.entities) ? game.entities : [], tiles: Array.isArray(game.tiles) ? game.tiles : [] };
    const normalizedStats = calculateBlueprintStatistics(imported, map);
    assert.equal(normalizedStats.complete, true, normalizedStats.warnings.join('; '));
    assert.deepEqual(normalizedStats.constructionItems, sorted(game.costToBuild), 'Imported construction items differ from game cost_to_build');
    for (const [actual, expected] of [[stats.footprint, game.sourceFootprint], [normalizedStats.footprint, game.footprint]]) {
      for (const dimension of ['width', 'height']) assert.ok(Math.abs(actual[dimension] - expected[dimension]) < 1e-7,
        `Footprint ${dimension}: JS ${actual[dimension]}, game ${expected[dimension]}`);
    }
    const sourceMatchesGameCost = JSON.stringify(stats.constructionItems) === JSON.stringify(sorted(game.costToBuild));
    const importDiagnostics = {
      result: game.importResult, sourceEntities: stats.entities, importedEntities: imported.entities.length,
      sourceMatchesGameCost,
      dimensionsChanged: Math.abs(stats.footprint.width - normalizedStats.footprint.width) > 1e-7 || Math.abs(stats.footprint.height - normalizedStats.footprint.height) > 1e-7,
    };
    Object.assign(row, { status: 'passed', statistics: stats, importDiagnostics, gameCostToBuild: sorted(game.costToBuild), importedFootprint: game.footprint });
  } catch (error) {
    Object.assign(row, { status: 'failed', error: String(error) });
    console.error(job.id, row.error);
  }
  results.push(row);
}
const report = { schema: 1, evaluatedAt: new Date().toISOString(), gameVersion: reference.gameVersion, mods: reference.mods,
  footprintDefinition: map.footprintDefinition,
  validationLevel: 'Game runtime placement/geometry export; normalized-input JS totals compared with Factorio cost_to_build; original and imported dimensions compared with independent Lua calculation using measured engine boxes',
  referenceSha256: createHash('sha256').update(referenceBytes).digest('hex'), prototypeMapSha256: createHash('sha256').update(mapBytes).digest('hex'),
  limitations: ['Footprint is an agreed tile-enclosing building rectangle, not a Factorio blueprint-width API', 'Game imports can snap individual positions, discard fields, or remove entities; original and normalized input are tested separately', 'Geometry export includes entity ghosts for rolling stock and an actual platform hub', 'Statistics do not calculate raw-material crafting costs or validate placement legality'],
  summary: { passed: results.filter(row => row.status === 'passed').length, failed: results.filter(row => row.status === 'failed').length,
    corpusLeaves: cases.filter(row => row.source !== 'synthetic').length, syntheticCases: cases.filter(row => row.source === 'synthetic').length,
    entityPrototypes: Object.keys(map.entities).length, tilePrototypes: Object.keys(map.tiles).length,
    importWarnings: results.filter(row => row.importDiagnostics?.result === -1).length,
    sourceCostDifferences: results.filter(row => row.importDiagnostics && !row.importDiagnostics.sourceMatchesGameCost).length,
    importedDimensionChanges: results.filter(row => row.importDiagnostics?.dimensionsChanged).length }, inputs, cases: results };
await writeFile(values.report, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report.summary, null, 2));
if (report.summary.failed) process.exitCode = 1;
