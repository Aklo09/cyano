export function createPrototypeMap(reference) {
  if (reference.schema !== 2 || !reference.gameVersion) throw new Error('Unsupported game reference');
  const equipmentItems = {};
  for (const [name, item] of Object.entries(reference.items)) {
    if (item.equipment) (equipmentItems[item.equipment] ??= []).push(name);
  }
  return { schema: 2, gameVersion: reference.gameVersion, mods: reference.mods, qualities: reference.qualities,
    entities: reference.entities, tiles: reference.tiles, items: reference.items, itemGroups: reference.itemGroups,
    itemSubgroups: reference.itemSubgroups, equipmentItems,
    footprintDefinition: 'Axis-aligned union of tile-enclosing collision geometry for grid buildings and exact oriented collision geometry for off-grid entities, plus 1x1 blueprint tiles; units are game tiles.' };
}
