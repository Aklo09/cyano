import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { decode, encode, listBlueprints, selectBlueprint } from '@rickyzhangca/fpsr';

export const version = 2 * 2 ** 48 + 1 * 2 ** 32 + 23 * 2 ** 16;
export const blueprint = (entities = [], extra = {}) => ({ item: 'blueprint', version, entities, ...extra });
export const entity = (name, x = 0.5, y = 0.5, extra = {}) => ({ entity_number: 1, name, position: { x, y }, ...extra });

export function syntheticCases() {
  const cases = [
    ['empty', blueprint()],
    ['chest', blueprint([entity('wooden-chest')])],
    ['assembler-3x3', blueprint([entity('assembling-machine-3')])],
    ['negative-position-and-gap', blueprint([entity('wooden-chest', -5.5, -2.5), entity('wooden-chest', 4.5, -2.5, { entity_number: 2 })])],
    ['tile-only', blueprint([], { tiles: [{ name: 'stone-path', position: { x: -2, y: 3 } }, { name: 'concrete', position: { x: 2, y: 5 } }] })],
    ['mixed-entity-and-tile', blueprint([entity('wooden-chest')], { tiles: [{ name: 'concrete', position: { x: 4, y: 2 } }] })],
    ['quality-and-modules', blueprint([
      entity('assembling-machine-3', 0.5, 0.5, { quality: 'legendary', items: [
        { id: { name: 'speed-module-3', quality: 'epic' }, items: { in_inventory: [{ inventory: 4, stack: 0 }, { inventory: 4, stack: 1 }] } },
      ] }),
      entity('assembling-machine-3', 5.5, 0.5, { entity_number: 2 }),
    ])],
    ['logistics-stock-excluded', blueprint([entity('requester-chest', 0.5, 0.5, { request_filters: { sections: [{ index: 1, filters: [{ index: 1, value: { type: 'item', name: 'iron-plate', quality: 'normal', comparator: '=' }, min: 100 }] }] } })])],
    ['equipment-grid', blueprint([entity('spidertron', 0, 0, { grid: [{ equipment: { name: 'battery-equipment', quality: 'rare' }, position: { x: 0, y: 0 } }] })])],
    ['equipment-insert-plan', blueprint([entity('spidertron', 0, 0, { items: [{ id: { name: 'battery-equipment', quality: 'rare' }, items: { grid_count: 1 } }] })])],
    ['inserted-fuel', blueprint([entity('locomotive', 0, 0, { items: [{ id: { name: 'coal' }, items: { in_inventory: [{ inventory: 1, stack: 0, count: 5 }] } }] })])],
  ];
  for (const name of ['boiler', 'straight-rail', 'curved-rail-a', 'curved-rail-b', 'half-diagonal-rail', 'elevated-curved-rail-a', 'rail-ramp']) {
    for (let direction = 0; direction < 16; direction += name === 'boiler' ? 4 : 1) cases.push([`${name}-direction-${direction}`, blueprint([entity(name, 0, 0, { direction })])]);
  }
  for (const orientation of [0, 0.125, 0.25]) cases.push([`off-grid-car-${orientation}`, blueprint([entity('car', 0.25, -0.125, { orientation })])]);
  return cases.map(([name, bp]) => ({ id: `synthetic/${name}`, source: 'synthetic', path: [], blueprint: bp, string: encode({ blueprint: bp }) }));
}

export async function loadStatisticsCases({ examples, upstream }) {
  const sources = (await readdir(examples)).filter(name => name.endsWith('.txt')).sort().map(name => ({ file: `test-bp/${name}`, filename: path.join(examples, name) }));
  for (const file of [
    'decode/01-minimal-chest.txt', 'decode/02-entities-direction-quality.txt', 'decode/03-tiles-snap-grid.txt', 'decode/04-wires.txt', 'decode/05-nested-book.txt', 'decode/06-book-with-planner.txt',
    'visual-tests/base-game/book.bp.txt', 'visual-tests/official-mods/space-age.bp.txt', 'visual-tests/official-mods/quality.bp.txt', 'visual-tests/official-mods/elevated-rails.bp.txt', 'visual-tests/official-mods/recycler.bp.txt',
  ]) sources.push({ file: `fixtures/${file}`, filename: path.join(upstream, 'fixtures', file) });
  const cases = [];
  const inputs = [];
  for (const source of sources) {
    const bytes = await readFile(source.filename);
    inputs.push({ file: source.file, sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length });
    const doc = decode(bytes.toString('utf8'));
    for (const ref of listBlueprints(doc)) {
      const bp = selectBlueprint(doc, ref.path);
      cases.push({ id: `${source.file}#${ref.path.join('/') || 'root'}`, source: source.file, path: ref.path, label: bp.label ?? null, blueprint: bp, string: encode({ blueprint: bp }) });
    }
  }
  return { inputs, cases: [...cases, ...syntheticCases()] };
}
