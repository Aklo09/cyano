import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { calculateBlueprintStatistics as stats } from '../reference/blueprint-statistics.mjs';
import { blueprint, entity, syntheticCases } from './statistics-cases.mjs';

const map = JSON.parse(await readFile(process.env.FB_STATISTICS_MAP ?? new URL('../../private-assets/statistics-reference/prototype-map.json', import.meta.url), 'utf8'));
const calculate = bp => stats(bp, map);
const synthetic = id => syntheticCases().find(item => item.id === `synthetic/${id}`).blueprint;
const dimensions = bp => { const { width, height } = calculate(bp).footprint; return [width, height]; };

test('building footprint uses game units, not collision-box width or image pixels', () => {
  assert.deepEqual(dimensions(blueprint([entity('wooden-chest')])), [1, 1]);
  assert.deepEqual(dimensions(blueprint([entity('assembling-machine-3')])), [3, 3]);
  assert.deepEqual(dimensions(blueprint()), [0, 0]);
});
test('building dimensions account for cardinal rotation', () => {
  assert.deepEqual(dimensions(synthetic('boiler-direction-0')), [3, 2]);
  assert.deepEqual(dimensions(synthetic('boiler-direction-4')), [2, 3]);
});
test('rectangle contains gaps, negative coordinates, and tiles', () => {
  assert.deepEqual(dimensions(synthetic('negative-position-and-gap')), [11, 1]);
  assert.deepEqual(dimensions(synthetic('tile-only')), [5, 3]);
  assert.deepEqual(dimensions(synthetic('mixed-entity-and-tile')), [5, 3]);
});
test('source dimensions are invariant under arbitrary translation', () => {
  const bp = synthetic('quality-and-modules');
  const shifted = structuredClone(bp);
  for (const e of shifted.entities) { e.position.x += 0.125; e.position.y -= 100.75; }
  assert.deepEqual(dimensions(shifted), dimensions(bp));
});
test('rail costs use prototype quantities and diagonal geometry uses engine boxes', () => {
  const items = id => calculate(synthetic(id)).constructionItems;
  assert.deepEqual(items('curved-rail-a-direction-0'), [{ name: 'rail', quality: 'normal', count: 3 }]);
  assert.deepEqual(items('half-diagonal-rail-direction-0'), [{ name: 'rail', quality: 'normal', count: 2 }]);
  assert.deepEqual(dimensions(synthetic('straight-rail-direction-2')), [4, 4]);
  assert.deepEqual(dimensions(synthetic('rail-ramp-direction-4')), [16, 4]);
});
test('secondary collision boxes contribute to a rail footprint', () => {
  const name = 'legacy-curved-rail';
  const direction = Object.keys(map.entities[name].directions).find(d => map.entities[name].directions[d].secondaryCollisionBox);
  assert.ok(direction, 'Runtime export must contain a secondary rail box');
  const bp = blueprint([entity(name, 0, 0, { direction: Number(direction) })]);
  const withoutSecondary = structuredClone(map);
  delete withoutSecondary.entities[name].directions[direction].secondaryCollisionBox;
  assert.notDeepEqual(dimensions(bp), [stats(bp, withoutSecondary).footprint.width, stats(bp, withoutSecondary).footprint.height]);
});
test('qualities remain distinct and inserted module count defaults to one per slot', () => {
  const result = calculate(synthetic('quality-and-modules'));
  assert.deepEqual(result.modules, [{ name: 'speed-module-3', quality: 'epic', count: 2 }]);
  assert.equal(result.placement.filter(item => item.name === 'assembling-machine-3').length, 2);
});
test('installed equipment is counted once; bare equipment requests stay separate', () => {
  assert.deepEqual(calculate(synthetic('equipment-grid')).equipment, [{ name: 'battery-equipment', quality: 'rare', count: 1 }]);
  const result = calculate(synthetic('equipment-insert-plan'));
  assert.equal(result.constructionItems.some(item => item.name === 'battery-equipment'), false);
  assert.deepEqual(result.equipmentRequests, [{ name: 'battery-equipment', quality: 'rare', count: 1 }]);
});
test('inserted fuel is counted; logistics targets and filters are excluded', () => {
  assert.deepEqual(calculate(synthetic('inserted-fuel')).otherInserted, [{ name: 'coal', quality: 'normal', count: 5 }]);
  assert.deepEqual(calculate(synthetic('logistics-stock-excluded')).constructionItems, [{ name: 'requester-chest', quality: 'normal', count: 1 }]);
});
test('off-grid vehicles retain fractional extents and spider body ignores torso orientation', () => {
  const a = dimensions(synthetic('off-grid-car-0'));
  const b = dimensions(synthetic('off-grid-car-0.25'));
  assert.equal(a[0], 1.3984375);
  assert.equal(a[0], b[1]); assert.equal(a[1], b[0]);
  assert.deepEqual(dimensions(blueprint([entity('spidertron', 0, 0, { orientation: 0.125 })])), [2, 2]);
});
test('unknown prototypes yield incomplete results without guessed dimensions', () => {
  const result = calculate(blueprint([entity('fb-unknown')]));
  assert.equal(result.complete, false); assert.equal(result.footprint.width, null);
  const tile = calculate(blueprint([], { tiles: [{ name: 'fb-unknown', position: { x: 0, y: 0 } }] }));
  assert.equal(tile.requirementsComplete, false); assert.deepEqual([tile.footprint.width, tile.footprint.height], [1, 1]);
});
test('invalid counts, directions, and positions fail rather than producing misleading totals', () => {
  assert.throws(() => calculate(blueprint([entity('wooden-chest', Infinity)])));
  assert.throws(() => calculate(blueprint([entity('wooden-chest', 0, 0, { direction: 16 })])));
  const bp = synthetic('quality-and-modules');
  bp.entities[0].items[0].items.in_inventory[0].count = -1;
  assert.throws(() => calculate(bp));
});
test('non-buildable robots are reported as incomplete; input remains unchanged', () => {
  const bp = blueprint([entity('construction-robot')]); const before = JSON.stringify(bp);
  assert.equal(calculate(bp).requirementsComplete, false);
  assert.equal(JSON.stringify(bp), before);
});
