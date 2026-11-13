# Construction statistics and footprint

Status: approved by the owner on 2026-11-13 ([milestone 2](../planning/Milestone-2.md), subtask S1).

Report what a saved blueprint needs to be built and how much ground it covers, from the saved source itself,
without game-import normalization. Statistics are derived and read-only: they never change sources, metadata,
or recovery state, and source operations never depend on them.

## Scope

Statistics apply to one selected blueprint entry: a root blueprint, or a blueprint inside a book addressed by its
actual stored indices, as for export and previews.

- **Books** have no statistics of their own; a book shows its contents, and each blueprint leaf has its own statistics.
  Nothing is aggregated across a book.
- **Upgrade and deconstruction planners** are configuration, not construction: they have no statistics or footprint.
- Requesting statistics for a book or planner returns a "not applicable" result, not an error.

Requirements are construction requirements: the items placed or inserted when building.
They are not raw-material crafting costs or production simulation.
"Complete" means the saved data was fully understood; it does not promise lossless import into another game version.

## Prototype data

Statistics use the prototype map in a verified asset release (`statistics/prototype-map.json`).
No other map source is accepted, and no game process runs.
Every result records the release's asset identity and the map's game version, so a result is tied to exact data.

The map is read only after the release verifies, and only if its bytes still match the verified inventory.
It must have `schema` 1 and a game version. Parsing is strict: every field has a known type, unknown fields are
refused, and every placement item and equipment item must resolve within the map, so a statistics warning
always concerns the blueprint, never the map. A direction entry's key is the requested blueprint direction;
its `direction` field is the engine-resolved direction (a chest resolves all 16 to 0). The initial release profile is Factorio 2.1.23 with
base, space-age, elevated-rails, quality, and recycler: 146 entity prototypes, 342 items, 23 placeable tiles,
and 6 qualities. The map holds engine-resolved placement choices, item types, equipment items,
and per-direction collision geometry; renderer sprite bounds are never used.

## Construction requirements

Items are grouped by item name and quality. Results contain five groups:

| Group | Contents |
| --- | --- |
| `placement` | For each entity and tile, the first placement choice and its count, matching construction-robot behavior. Entity quality is the entity's `quality`, default `normal`; tiles are `normal`. A curved rail needs 3 rail items, a half-diagonal rail 2 |
| `modules` | Items inserted into an entity whose item type is `module` |
| `equipment` | Equipment already installed in an entity's `grid`, counted once each, mapped to its single equipment item |
| `otherInserted` | Other inserted items, such as fuel |
| `equipmentRequests` | Bare `grid_count` requests; reported but excluded from totals |

`constructionItems` is the sum of `placement`, `modules`, `equipment`, and `otherInserted`.

Inserted items come from each entity's `items` array. Each request's `in_inventory` stacks add their `count`,
which defaults to 1 when omitted. Logistics request filters, targets, and section stock are not requirements.

Counts are integers from 0 to 2⁵³ − 1; a zero count adds nothing.

## Footprint

The footprint is the axis-aligned rectangle covering buildings, placed tiles, and the gaps between them,
in game tiles. An assembling machine measures 3 × 3. Shadows, wires, sprite overhang, and empty snap-grid
repetition are excluded; image pixels and raw collision-box sizes are different measurements.

- **Grid entities:** take the collision geometry for the entity's direction (default 0).
  Expand the box to enclosing tile edges in the entity's placement phase
  (half a tile when the direction's tile width or height is odd), with a 10⁻⁹ tolerance,
  then translate it to the saved position. Saved positions are never snapped to game-normalized positions.
- **Off-grid entities** (vehicles, robots, plants, land mines): use direction 0 geometry and keep fractional extents.
- **Rotation:** geometry rotates by the entity's `orientation`, defaulting to `direction / 16`, only when the
  prototype says orientation affects collision. In the 2.1.23 map that is true only for off-grid vehicles:
  cars, tanks, locomotives, and wagons rotate; a spidertron's torso orientation does not rotate its square body.
- **Secondary collision boxes** also contribute (in the 2.1.23 map, legacy curved rails);
  rail snapping sizes alone cannot enclose all rail geometry. A rail ramp measures 16 × 4 or 4 × 16 by direction.
- **Tiles:** each tile covers `[x, y]` to `[x + 1, y + 1]`, even when its placement item is unknown.

```text
width  = maximum right edge  - minimum left edge
height = maximum bottom edge - minimum top edge
```

Bounds, widths, and heights are rounded to 10⁻⁹, with halves rounding toward positive infinity.
An empty blueprint measures 0 × 0 with `bounds: null`.

## Completeness, warnings, and errors

Unknown or unsupported data produces a warning and marks part of the result incomplete.
Warnings are structured: a stable `code`, the `name` involved (an entity, item, tile, or equipment name, or the
quality for `UNKNOWN_QUALITY`), the `direction` for `UNMEASURED_GEOMETRY`, the part it makes incomplete
(`affects`: `requirements`, `footprint`, or `both`), and how many times it occurred (`count`).
Identical warnings are reported once with their count, in order of first occurrence: entities first, then tiles.
Interfaces word the message; results carry no prose.

| `code` | Meaning | `affects` |
| --- | --- | --- |
| `UNKNOWN_ENTITY` | Entity not in the prototype map | `both` |
| `UNMEASURED_GEOMETRY` | No collision geometry for the entity's direction | `footprint` |
| `UNKNOWN_ITEM` | Placement or inserted item not in the map | `requirements` |
| `UNKNOWN_QUALITY` | Quality not in the map | `requirements` |
| `NO_PLACEMENT_ITEM` | The prototype has no placement item | `requirements` |
| `NOT_BLUEPRINT_BUILDABLE` | Robots and other entities construction robots cannot build | `requirements` |
| `LEGACY_ITEM_FORMAT` | `items` in the pre-2.0 object format; its contents are not counted | `requirements` |
| `UNKNOWN_EQUIPMENT` | Installed equipment with no single matching item | `requirements` |
| `UNKNOWN_TILE` | Tile not in the map; its 1 × 1 geometry still counts | `requirements` |
`complete` is true only when both requirements and footprint are complete.
When the footprint is incomplete, `bounds`, `width`, and `height` are `null`,
and `knownBounds` reports the rectangle of the geometry that was understood, or `null` if none was.

Data that would make totals misleading is an error, and no result is returned:

- a direction that is not an integer from 0 to 15;
- an orientation that is not finite or lies outside 0 to 1;
- a negative, fractional, or larger-than-2⁵³ − 1 count, or a total that would exceed 2⁵³ − 1;
- non-finite positions or geometry;
- an unsupported prototype map.

## Result

Results are versioned JSON. Items are `{ "name", "quality", "count" }`, sorted by the UTF-8 bytes of the name,
then of the quality.

A root blueprint holding one wooden chest at (0.5, 0.5), as the reference calculator computes it
with the 2.1.23 map, plus the native fields:

```json
{
  "schemaVersion": 1,
  "applicable": true,
  "entryPath": [],
  "entryKind": "blueprint",
  "gameVersion": "2.1.23",
  "assetIdentity": "<64 lowercase hex>",
  "basis": "source-blueprint",
  "entities": 1,
  "tiles": 0,
  "complete": true,
  "requirementsComplete": true,
  "warnings": [],
  "footprint": {
    "units": "game tiles",
    "complete": true,
    "bounds": { "minX": 0, "minY": 0, "maxX": 1, "maxY": 1 },
    "width": 1,
    "height": 1
  },
  "constructionItems": [{ "name": "wooden-chest", "quality": "normal", "count": 1 }],
  "placement": [{ "name": "wooden-chest", "quality": "normal", "count": 1 }],
  "modules": [],
  "equipment": [],
  "otherInserted": [],
  "equipmentRequests": []
}
```

`knownBounds` appears only when the footprint is incomplete. A warning looks like:

```json
{ "code": "UNKNOWN_ENTITY", "name": "ee-infinity-loader", "affects": "both", "count": 8 }
```
For a book or planner the result is only:

```json
{ "schemaVersion": 1, "applicable": false, "entryPath": [], "entryKind": "blueprint_book" }
```

## Source and game imports

Game import can snap positions, drop fields, and remove entities. Statistics describe the saved source and
never replace an original with a game-normalized export. Reference comparisons do not establish terrain,
surface, or building legality. Factorio has no blueprint-width API implementing this exact footprint definition.

## Differences from the web application

The reference calculator (`tools/reference/blueprint-statistics.mjs`) is the starting point, not a constraint:
the native app departs from it wherever a different behavior makes more sense. Current differences:

- Warnings are structured and grouped with an occurrence count instead of one prose string per occurrence.
- Items sort by UTF-8 bytes, not JavaScript `localeCompare`.
- Results add `schemaVersion`, `applicable`, `entryPath`, `entryKind`, and `assetIdentity`.
- Errors are typed library errors rather than JavaScript exceptions.

Parity with reference outputs generated from the private map (subtask S5) is checked on these native semantics:
identical items, completeness, and footprint, and the same warnings once reference strings are mapped to codes and
counted. The reference itself was compared with the game's `cost_to_build` in the original project;
milestone 2 does not repeat that comparison.
