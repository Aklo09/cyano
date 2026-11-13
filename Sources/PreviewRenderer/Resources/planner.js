// Generated from fpsr 2f7dc70f2681de530402556f757006e904e692d5 (MIT). See tools/vendor/fpsr/LICENSE.
var FBPlanner = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // tools/planner-entry.ts
  var planner_entry_exports = {};
  __export(planner_entry_exports, {
    nativePlan: () => nativePlan,
    planDeconstructionPlannerDrawList: () => planDeconstructionPlannerDrawList,
    planDrawList: () => planDrawList,
    planDrawListWithOptions: () => planDrawListWithOptions,
    planUpgradePlannerDrawList: () => planUpgradePlannerDrawList,
    plannerRevision: () => plannerRevision,
    resolve: () => resolve,
    selfTest: () => selfTest
  });

  // tools/vendor/fpsr/packages/renderer/src/types/draw-list.ts
  var FACTORIO_RENDER_LAYERS = {
    zero: 0,
    "background-transitions": 1,
    "under-tiles": 2,
    decals: 3,
    "above-tiles": 4,
    "ground-layer-1": 5,
    "ground-layer-2": 6,
    "ground-layer-3": 7,
    "ground-layer-4": 8,
    "ground-layer-5": 9,
    "lower-radius-visualization": 10,
    "radius-visualization": 11,
    "transport-belt-integration": 12,
    resource: 13,
    "building-smoke": 14,
    "rail-stone-path-lower": 15,
    "rail-stone-path": 16,
    "rail-tie": 17,
    decorative: 18,
    "ground-patch": 19,
    "ground-patch-higher": 20,
    "ground-patch-higher2": 21,
    "rail-chain-signal-metal": 22,
    "rail-screw": 23,
    "rail-metal": 24,
    remnants: 25,
    floor: 26,
    "transport-belt": 27,
    "transport-belt-endings": 28,
    "floor-mechanics-under-corpse": 29,
    corpse: 30,
    "floor-mechanics": 31,
    item: 32,
    "transport-belt-reader": 33,
    "lower-object": 34,
    "transport-belt-circuit-connector": 35,
    "lower-object-above-shadow": 36,
    "lower-object-overlay": 37,
    "object-under": 38,
    object: 39,
    "cargo-hatch": 40,
    "higher-object-under": 41,
    "higher-object-above": 42,
    "train-stop-top": 43,
    "item-in-inserter-hand": 44,
    "above-inserters": 45,
    wires: 46,
    "under-elevated": 47,
    "elevated-rail-stone-path-lower": 48,
    "elevated-rail-stone-path": 49,
    "elevated-rail-tie": 50,
    "elevated-rail-screw": 51,
    "elevated-rail-metal": 52,
    "elevated-lower-object": 53,
    "elevated-object": 54,
    "elevated-higher-object": 55,
    "fluid-visualization": 56,
    "wires-above": 57,
    "entity-info-icon": 58,
    "entity-info-icon-above": 59,
    explosion: 60,
    projectile: 61,
    smoke: 62,
    "air-object": 63,
    "air-entity-info-icon": 64,
    "light-effect": 65,
    "selection-box": 66,
    "higher-selection-box": 67,
    "collision-selection-box": 68,
    arrow: 69,
    cursor: 70
  };
  var FPSR_RENDER_LAYERS = {
    /** ≈ `background-transitions` */
    "tile-transition": 1,
    /** ≈ `under-tiles` */
    "ground-tile": 2,
    "water-tile": 2,
    /** alias of `rail-tie` */
    "rail-ties": 17,
    /** Dedicated `draw_as_shadow` pass (no Factorio RenderLayer for this) */
    shadow: 37,
    /** alias of `elevated-rail-tie` */
    "elevated-rail-ties": 50,
    /** alias of `entity-info-icon` */
    icons: 58
  };
  var RENDER_LAYERS = {
    ...FACTORIO_RENDER_LAYERS,
    ...FPSR_RENDER_LAYERS
  };
  function compareDrawCmd(a, b) {
    return a.layer - b.layer || a.sortY - b.sortY || a.sortX - b.sortX || a.entity - b.entity || a.sub - b.sub;
  }

  // tools/vendor/fpsr/packages/renderer/src/plan-diagnostics.ts
  var countUnsupported = (values, isSupported) => {
    const counts = /* @__PURE__ */ new Map();
    for (const value of values) {
      if (isSupported(value.name)) continue;
      const entry = counts.get(value.name) ?? { count: 0, entityNumbers: [] };
      entry.count += 1;
      if (value.entity_number != null) entry.entityNumbers.push(value.entity_number);
      counts.set(value.name, entry);
    }
    return [...counts.entries()].map(([name, value]) => ({
      name,
      count: value.count,
      ...value.entityNumbers.length > 0 ? { entityNumbers: value.entityNumbers } : {}
    })).sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  };
  var hasOnlyFiniteNumbers = (value) => {
    if (typeof value === "number") return Number.isFinite(value);
    if (Array.isArray(value)) return value.every(hasOnlyFiniteNumbers);
    if (value && typeof value === "object") {
      return Object.values(value).every(hasOnlyFiniteNumbers);
    }
    return true;
  };
  var countValues = (values) => {
    return values.reduce((sum, value) => sum + value.count, 0);
  };
  function analyzePlan(blueprint, drawList, db) {
    const entities = blueprint.entities ?? [];
    const tiles = blueprint.tiles ?? [];
    const unsupportedEntities = countUnsupported(entities, (name) => db.entities[name] != null);
    const unsupportedTiles = countUnsupported(tiles, (name) => db.tiles[name] != null);
    const byKind = {};
    const frames = /* @__PURE__ */ new Set();
    const layers = /* @__PURE__ */ new Set();
    const atlases = /* @__PURE__ */ new Set();
    let validFrameReferences = true;
    for (const command of drawList.commands) {
      byKind[command.kind] = (byKind[command.kind] ?? 0) + 1;
      layers.add(command.layer);
      if (command.kind !== "sprite" && command.kind !== "icon") continue;
      const frameIds = [command.frame];
      if (command.kind === "icon" && command.backingFrame != null) {
        frameIds.push(command.backingFrame);
      }
      for (const frameId of frameIds) {
        frames.add(frameId);
        const frame = db.frames[frameId];
        if (!frame) {
          validFrameReferences = false;
          continue;
        }
        atlases.add(frame.a);
      }
    }
    const { bounds } = drawList;
    const finiteBounds = hasOnlyFiniteNumbers(bounds) && bounds.minX <= bounds.maxX && bounds.minY <= bounds.maxY;
    const sortedCommands = drawList.commands.every((command, index) => {
      const previous = drawList.commands[index - 1];
      return !previous || compareDrawCmd(previous, command) <= 0;
    });
    return {
      entities: {
        total: entities.length,
        resolved: entities.length - countValues(unsupportedEntities),
        unsupported: unsupportedEntities
      },
      tiles: {
        total: tiles.length,
        resolved: tiles.length - countValues(unsupportedTiles),
        unsupported: unsupportedTiles
      },
      drawList: {
        commandCount: drawList.commands.length,
        byKind,
        uniqueFrames: frames.size,
        uniqueLayers: layers.size,
        atlasIndices: [...atlases].sort((a, b) => a - b)
      },
      checks: {
        finiteBounds,
        finiteCommands: drawList.commands.every(hasOnlyFiniteNumbers),
        sortedCommands,
        validFrameReferences
      }
    };
  }

  // tools/vendor/fpsr/packages/renderer/src/alt-mode-signals.ts
  var SIGNAL_PREFIX = {
    item: "item",
    fluid: "fluid",
    virtual: "virtual-signal",
    "virtual-signal": "virtual-signal",
    entity: "entity",
    recipe: "recipe",
    quality: "quality",
    tile: "tile",
    "space-location": "space-location",
    "asteroid-chunk": "asteroid-chunk"
  };
  function asSignal(value, defaultType = "item") {
    if (typeof value === "string") return { name: value, type: defaultType };
    if (!value || typeof value !== "object") return void 0;
    const obj = value;
    if (obj.id && typeof obj.id === "object") return asSignal(obj.id, defaultType);
    if (obj.value && typeof obj.value === "object") return asSignal(obj.value, defaultType);
    if (obj.signal && typeof obj.signal === "object") return asSignal(obj.signal, defaultType);
    if (typeof obj.name !== "string") return void 0;
    return {
      name: obj.name,
      type: typeof obj.type === "string" ? obj.type : defaultType,
      ...typeof obj.quality === "string" ? { quality: obj.quality } : {}
    };
  }
  function signalKey(signal) {
    return `${signal.type ?? "item"}/${signal.name}/${signal.quality ?? "normal"}`;
  }
  function collectSignals(value, defaultType = "item", out = []) {
    if (Array.isArray(value)) {
      for (const item of value) collectSignals(item, defaultType, out);
      return out;
    }
    if (!value || typeof value !== "object") return out;
    const obj = value;
    const direct = asSignal(obj, defaultType);
    if (direct) {
      out.push(direct);
      return out;
    }
    for (const [key, child] of Object.entries(obj)) {
      if (key === "index" || key === "count" || key === "comparator") continue;
      collectSignals(child, defaultType, out);
    }
    return out;
  }
  function filterSignals(filters, defaultType = "item") {
    return collectSignals(filters ?? [], defaultType);
  }
  function uniqueSignals(signals) {
    const seen = /* @__PURE__ */ new Set();
    return signals.filter((signal) => {
      const key = signalKey(signal);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }
  function signalIconKeys(signal) {
    const type = signal.type ?? "item";
    const prefix = SIGNAL_PREFIX[type] ?? type;
    const primary = `${prefix}/${signal.name}`;
    switch (type) {
      case "item":
        return [primary, `entity/${signal.name}`, `recipe/${signal.name}`];
      case "entity":
        return [primary, `item/${signal.name}`];
      case "recipe":
        return [primary, `item/${signal.name}`];
      case "tile":
        return [primary];
      default:
        return [primary];
    }
  }
  function altSignalFrame(db, signal) {
    for (const key of signalIconKeys(signal)) {
      const frame = db.icons[key];
      if (frame !== void 0) return frame;
    }
    return void 0;
  }
  function isSplitterType(def) {
    return def.protoType === "splitter" || def.protoType === "lane-splitter";
  }
  function splitterLaneFilter(entity, def) {
    if (!isSplitterType(def)) return void 0;
    if (!entity.output_priority || entity.output_priority === "none") return void 0;
    return asSignal(entity.filter) ?? filterSignals(entity.filters)[0];
  }
  function entitySignals(entity, def) {
    const signals = [];
    if (entity.recipe) {
      signals.push({ name: entity.recipe, type: "recipe", quality: entity.recipe_quality });
    }
    if (!splitterLaneFilter(entity, def)) {
      const directFilter = asSignal(
        entity.filter,
        def.protoType === "mining-drill" ? "entity" : "item"
      );
      if (directFilter) signals.push(directFilter);
      signals.push(...filterSignals(entity.filters));
    }
    signals.push(...filterSignals(entity["chunk-filter"], "asteroid-chunk"));
    if (entity.fluid_filter) signals.push({ name: entity.fluid_filter, type: "fluid" });
    for (const inventory of [
      entity.inventory,
      entity.trunk_inventory,
      entity.ammo_inventory,
      entity.burner_fuel_inventory,
      entity["result-inventory"]
    ]) {
      signals.push(...filterSignals(inventory?.filters));
    }
    if (entity.icon) signals.push({ ...entity.icon, type: entity.icon.type ?? "item" });
    return uniqueSignals(signals);
  }
  function resolveAltSignals(db, signals) {
    return signals.map((signal) => ({
      signal,
      frame: altSignalFrame(db, signal) ?? db.icons["utility/missing-icon"]
    })).filter((entry) => entry.frame !== void 0);
  }

  // tools/vendor/fpsr/packages/renderer/src/alt-mode-request-pin.ts
  var MAX_INSERT_PLAN_ICONS = 16;
  var INVENTORY_FUEL_OR_SHARED_1 = 1;
  var INVENTORY_MINING_DRILL_MODULES = 2;
  var INVENTORY_LAB_MODULES = 3;
  var INVENTORY_CRAFTER_MODULES = 4;
  function isModuleInventory(protoType, inventory) {
    if (inventory === INVENTORY_CRAFTER_MODULES) return true;
    if (inventory === INVENTORY_LAB_MODULES && protoType === "lab") return true;
    if (inventory === INVENTORY_MINING_DRILL_MODULES && protoType.includes("mining-drill")) {
      return true;
    }
    if (inventory === INVENTORY_FUEL_OR_SHARED_1 && protoType === "beacon") return true;
    return false;
  }
  function isFuelInventory(protoType, inventory) {
    if (inventory !== INVENTORY_FUEL_OR_SHARED_1) return false;
    if (isModuleInventory(protoType, inventory)) return false;
    if (protoType === "cargo-wagon") return false;
    return true;
  }
  function positiveInteger(value, fallback) {
    if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
    return Math.max(0, Math.floor(value));
  }
  function insertPlanSignals(items, def) {
    if (!Array.isArray(items)) return [];
    const protoType = def?.protoType ?? "";
    const slotted = [];
    const fuelByKind = /* @__PURE__ */ new Map();
    const fallback = [];
    let order = 0;
    for (const item of items) {
      const signal = asSignal(item.id);
      if (!signal) continue;
      const positions = Array.isArray(item.items?.in_inventory) ? item.items.in_inventory : [];
      if (positions.length > 0) {
        for (const position of positions) {
          const inventory = Number.isFinite(position.inventory) ? position.inventory : Number.MAX_SAFE_INTEGER;
          const stack = Number.isFinite(position.stack) ? position.stack : Number.MAX_SAFE_INTEGER;
          if (isFuelInventory(protoType, inventory)) {
            const key = signalKey(signal);
            if (!fuelByKind.has(key)) {
              fuelByKind.set(key, { signal: { ...signal }, order: order++ });
            }
            continue;
          }
          const count2 = Math.min(positiveInteger(position.count, 1), MAX_INSERT_PLAN_ICONS);
          for (let i = 0; i < count2; i++) {
            slotted.push({
              signal: { ...signal },
              inventory,
              stack,
              order: order++
            });
          }
        }
        continue;
      }
      const gridCount = positiveInteger(item.items?.grid_count, 0);
      const count = Math.min(gridCount > 0 ? gridCount : 1, MAX_INSERT_PLAN_ICONS);
      for (let i = 0; i < count; i++) fallback.push({ signal: { ...signal }, order: order++ });
    }
    slotted.sort((a, b) => a.inventory - b.inventory || a.stack - b.stack || a.order - b.order);
    const fuelSignals = [...fuelByKind.values()].sort((a, b) => a.order - b.order).map((entry) => entry.signal);
    return [
      ...slotted.map((entry) => entry.signal),
      ...fuelSignals,
      ...fallback.map((entry) => entry.signal)
    ].slice(0, MAX_INSERT_PLAN_ICONS);
  }
  var ASSEMBLER_INSERT_PLAN_Y_OFFSET = 0.2;
  var INSERT_PLAN_ICON_SCALE = 36 / 64;
  var INSERT_PLAN_GAP_TILES = 2 / 64;
  function insertPlanLayout(count) {
    if (count <= 0) return { scale: 0, xOffsets: [] };
    const scale = INSERT_PLAN_ICON_SCALE;
    const step = scale + INSERT_PLAN_GAP_TILES;
    return {
      scale,
      xOffsets: Array.from({ length: count }, (_, i) => (i - (count - 1) / 2) * step)
    };
  }
  var REQUEST_PIN_HEIGHT_OVER_WIDTH = 62 / 44;
  function trainInsertPlanShiftY(pinSize) {
    return pinSize * REQUEST_PIN_HEIGHT_OVER_WIDTH / 2;
  }
  function iconLayout(count, scale) {
    if (count <= 1) return [[0, 0]];
    if (count === 2)
      return [
        [-scale * 0.3, 0],
        [scale * 0.3, 0]
      ];
    const cols = Math.min(3, Math.ceil(Math.sqrt(count)));
    const rows = Math.ceil(count / cols);
    const spacing = scale * 0.62;
    const out = [];
    for (let i = 0; i < count; i++) {
      const col = i % cols;
      const row = Math.floor(i / cols);
      out.push([(col - (cols - 1) / 2) * spacing, (row - (rows - 1) / 2) * spacing]);
    }
    return out;
  }
  function iconDrawSpec(def) {
    return def.iconDrawSpecification ?? {
      shift: [0, 0],
      scale: def.kind === "inserter" ? 0.5 : 0.75,
      scaleForMany: 0.5,
      renderLayer: "entity-info-icon"
    };
  }
  function planRequestPinCommands(entity, def, db) {
    const insertPlans = resolveAltSignals(db, insertPlanSignals(entity.items, def));
    if (insertPlans.length === 0) return [];
    const spec = iconDrawSpec(def);
    const pinBackingFrame = db.icons["utility/item-request-slot"];
    const darkBackingFrame = db.icons["utility/entity-info-dark-background"];
    const useRequestPin = pinBackingFrame !== void 0;
    const layer = RENDER_LAYERS[spec.renderLayer];
    const insertLayout = insertPlanLayout(insertPlans.length);
    const insertAnchorY = def.kind === "train" ? entity.position.y + trainInsertPlanShiftY(insertLayout.scale) : entity.position.y + spec.shift[1];
    const primary = resolveAltSignals(db, entitySignals(entity, def));
    let insertY = insertAnchorY;
    if (primary.length > 0) {
      const primaryScale = primary.length > 1 ? spec.scaleForMany : spec.scale;
      const primaryOffsets = iconLayout(primary.length, primaryScale);
      const primaryBottom = primary.reduce((bottom, _entry, index) => {
        const y = entity.position.y + spec.shift[1] + (primaryOffsets[index]?.[1] ?? 0);
        return Math.max(bottom, y + primaryScale / 2);
      }, Number.NEGATIVE_INFINITY);
      const assemblerInsertYOffset = def.kind === "assembler" ? ASSEMBLER_INSERT_PLAN_Y_OFFSET : 0;
      insertY = primaryBottom + insertLayout.scale / 2 + assemblerInsertYOffset;
    }
    return insertPlans.map(({ frame }, index) => ({
      kind: "icon",
      layer,
      sortY: 0,
      sortX: 0,
      entity: entity.entity_number,
      sub: 20 + index,
      frame,
      x: entity.position.x + spec.shift[0] + (insertLayout.xOffsets[index] ?? 0),
      y: insertY,
      size: insertLayout.scale,
      ...useRequestPin ? { backingFrame: pinBackingFrame, backingStyle: "request-pin" } : darkBackingFrame !== void 0 ? { backingFrame: darkBackingFrame } : { backing: true }
    }));
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/shared.ts
  var DIR_DELTA = {
    0: [0, -1],
    4: [1, 0],
    8: [0, 1],
    12: [-1, 0]
  };
  function dir16ToIndex(direction, indexing) {
    const d = (direction % 16 + 16) % 16;
    switch (indexing) {
      case "single":
        return 0;
      case "direction4":
        return Math.floor(d / 4) % 4;
      case "direction8":
        return Math.floor(d / 2) % 8;
      case "direction16":
        return d;
      case "resolver":
        return 0;
    }
  }
  function cardinalDirection(direction) {
    const d = direction ?? 0;
    const snapped = Math.round(d / 4) * 4 % 16;
    if (snapped === 0 || snapped === 4 || snapped === 8 || snapped === 12) {
      return snapped;
    }
    return 0;
  }
  function opposite(dir) {
    return (dir + 8) % 16;
  }
  function rotateOffset(x, y, dir) {
    switch (dir) {
      case 0:
        return [x, y];
      case 4:
        return [-y, x];
      case 8:
        return [-x, -y];
      case 12:
        return [y, -x];
    }
  }
  function posKey(x, y) {
    return `${Math.round(x * 1e3) / 1e3},${Math.round(y * 1e3) / 1e3}`;
  }
  function hasNeighbor(grid, x, y, predicate) {
    const list = grid.get(posKey(x, y));
    if (!list) return false;
    return list.some(predicate);
  }
  function buildNeighborGrid(entities) {
    const grid = /* @__PURE__ */ new Map();
    for (const e of entities) {
      const key = posKey(e.position.x, e.position.y);
      const list = grid.get(key);
      if (list) list.push(e);
      else grid.set(key, [e]);
    }
    return grid;
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/fluid-ports.ts
  function snapFacing(n) {
    const v = n ?? 0;
    if (v === 4 || v === 8 || v === 12) return v;
    return 0;
  }
  function facingFromOffset(ox, oy) {
    if (Math.abs(ox) >= Math.abs(oy)) return ox > 0 ? 4 : 12;
    return oy > 0 ? 8 : 0;
  }
  function activeFluidPorts(entity, def, db) {
    const data = def.data;
    const fc = data?.fluidConnections;
    if (!fc) return [];
    const d = cardinalDirection(entity.direction ?? 0);
    const dirKey = String(d);
    const offsets = fc[dirKey] ?? [];
    if (offsets.length === 0) return [];
    const roles = data.fluidConnectionRoles?.[dirKey];
    const flows = data.fluidConnectionFlows?.[dirKey];
    const facings = data.fluidConnectionFacings?.[dirKey];
    const hideInfo = data.fluidConnectionHideInfo?.[dirKey];
    let indices;
    if (!data.fluidBoxesRequireFluidRecipe) {
      indices = offsets.map((_, i) => i);
    } else {
      const recipe = entity.recipe;
      if (!recipe) return [];
      const flags = db.fluidRecipes?.[recipe];
      if (!flags || !flags.ingredients && !flags.products) return [];
      if (!roles || roles.length !== offsets.length) {
        indices = offsets.map((_, i) => i);
      } else {
        indices = [];
        for (let i = 0; i < offsets.length; i++) {
          const role = roles[i];
          if (!role) continue;
          if (role === "input" && flags.ingredients) indices.push(i);
          else if (role === "output" && flags.products) indices.push(i);
        }
      }
    }
    const out = [];
    for (const i of indices) {
      if (hideInfo?.[i] === true) continue;
      const offset = offsets[i];
      if (!offset) continue;
      const flow = flows?.[i] === "input" || flows?.[i] === "output" || flows?.[i] === "input-output" ? flows[i] : roles?.[i] === "output" ? "output" : roles?.[i] === "input" ? "input" : "input-output";
      const facing = facings && facings.length === offsets.length ? snapFacing(facings[i]) : facingFromOffset(offset[0], offset[1]);
      out.push({ offset, flow, facing });
    }
    return out;
  }
  function activeFluidOffsetEntries(entity, def, db) {
    const fc = def.data?.fluidConnections;
    if (!fc) return [];
    const d = cardinalDirection(entity.direction ?? 0);
    const dirKey = String(d);
    const offsets = fc[dirKey] ?? [];
    if (offsets.length === 0) return [];
    const roles = def.data?.fluidConnectionRoles?.[dirKey];
    let indices;
    if (!def.data?.fluidBoxesRequireFluidRecipe) {
      indices = offsets.map((_, i) => i);
    } else {
      const recipe = entity.recipe;
      if (!recipe) return [];
      const flags = db.fluidRecipes?.[recipe];
      if (!flags || !flags.ingredients && !flags.products) return [];
      if (!roles || roles.length !== offsets.length) {
        indices = offsets.map((_, i) => i);
      } else {
        indices = [];
        for (let i = 0; i < offsets.length; i++) {
          const role = roles[i];
          if (!role) continue;
          if (role === "input" && flags.ingredients) indices.push(i);
          else if (role === "output" && flags.products) indices.push(i);
        }
      }
    }
    const out = [];
    for (const i of indices) {
      const offset = offsets[i];
      if (!offset) continue;
      out.push({ index: i, offset });
    }
    return out;
  }
  function activeFluidOffsets(entity, def, db) {
    return activeFluidOffsetEntries(entity, def, db).map((e) => e.offset);
  }
  function activeFluidRoles(entity, def, db) {
    const roles = /* @__PURE__ */ new Set();
    if (!def.data?.fluidBoxesRequireFluidRecipe) {
      roles.add("input");
      roles.add("output");
      return roles;
    }
    const recipe = entity.recipe;
    if (!recipe) return roles;
    const flags = db.fluidRecipes?.[recipe];
    if (!flags) return roles;
    if (flags.ingredients) roles.add("input");
    if (flags.products) roles.add("output");
    return roles;
  }
  function isFluidWorkingVisualisationGroupActive(entity, def, db, group) {
    const gated = def.data?.fluidWorkingVisualisationGroups;
    if (!gated) return true;
    const inInput = gated.input?.includes(group) === true;
    const inOutput = gated.output?.includes(group) === true;
    if (!inInput && !inOutput) return true;
    const active = activeFluidRoles(entity, def, db);
    if (inInput && active.has("input")) return true;
    if (inOutput && active.has("output")) return true;
    return false;
  }

  // tools/vendor/fpsr/packages/renderer/src/alt-mode.ts
  var ENTITY_QUALITY_BADGE_TILES = 0.5;
  var QUALITY_SIGNAL_OVERLAY_FRACTION = 0.5;
  function qualityIndicatorScale(def) {
    if (typeof def.qualityIndicatorScale === "number" && Number.isFinite(def.qualityIndicatorScale)) {
      return def.qualityIndicatorScale;
    }
    const [[x1, y1], [x2, y2]] = def.collisionBox;
    const tw = Math.max(1, Math.ceil(Math.abs(x2 - x1) - 1e-6));
    const th = Math.max(1, Math.ceil(Math.abs(y2 - y1) - 1e-6));
    return Math.min(1, Math.max(0.5, Math.min(tw, th) / 3));
  }
  function qualityBadgeCommands(resolved, parents, entityNumber, db, startSub) {
    const commands = [];
    for (let index = 0; index < resolved.length; index++) {
      const quality = resolved[index]?.signal.quality;
      if (!quality || quality === "normal") continue;
      const frame = db.icons[`quality/${quality}`] ?? db.icons["utility/missing-icon"];
      const parent = parents[index];
      if (frame === void 0 || !parent) continue;
      commands.push({
        kind: "icon",
        layer: RENDER_LAYERS["entity-info-icon-above"],
        sortY: 0,
        sortX: 0,
        entity: entityNumber,
        sub: startSub + index,
        frame,
        x: parent.x - parent.size * 0.3,
        y: parent.y + parent.size * 0.3,
        size: parent.size * QUALITY_SIGNAL_OVERLAY_FRACTION
      });
    }
    return commands;
  }
  function swapPriority(priority, mirrored) {
    if (!mirrored || priority === "none" || priority == null) return priority;
    return priority === "left" ? "right" : "left";
  }
  function splitterPriorityCommands(entity, def, db, startSub) {
    if (!isSplitterType(def)) return [];
    const arrowFrame = db.icons["utility/indication-arrow"];
    const direction = cardinalDirection(entity.direction ?? 0);
    const angle = direction * 22.5;
    const radians = angle * Math.PI / 180;
    const forward = [Math.sin(radians), -Math.cos(radians)];
    const right = [Math.cos(radians), Math.sin(radians)];
    const ARROW_SIDE_OFFSET = 0.25;
    const ARROW_LANE_OFFSET = 0.5;
    const FILTER_LANE_OFFSET = 0.5;
    const specs = [
      { priority: swapPriority(entity.input_priority, entity.mirror), side: -1 },
      { priority: swapPriority(entity.output_priority, entity.mirror), side: 1 }
    ];
    const filterSignal = splitterLaneFilter(entity, def);
    const filterFrame = filterSignal ? altSignalFrame(db, filterSignal) ?? db.icons["utility/missing-icon"] : void 0;
    const darkBackingFrame = db.icons["utility/entity-info-dark-background"];
    const filterSize = iconDrawSpec(def).scale;
    const commands = [];
    for (const spec of specs) {
      if (!spec.priority || spec.priority === "none") continue;
      const lane = spec.priority === "right" ? 1 : -1;
      const useFilter = spec.side > 0 && filterFrame !== void 0;
      const sideOffset = useFilter ? 0 : ARROW_SIDE_OFFSET;
      const laneOffset = useFilter ? FILTER_LANE_OFFSET : ARROW_LANE_OFFSET;
      const x = entity.position.x + forward[0] * sideOffset * spec.side + right[0] * laneOffset * lane;
      const y = entity.position.y + forward[1] * sideOffset * spec.side + right[1] * laneOffset * lane;
      if (useFilter) {
        const filterCmd = {
          kind: "icon",
          layer: RENDER_LAYERS["entity-info-icon-above"],
          sortY: 0,
          sortX: 0,
          entity: entity.entity_number,
          sub: startSub + commands.length,
          frame: filterFrame,
          x,
          y,
          size: filterSize,
          ...darkBackingFrame !== void 0 ? { backingFrame: darkBackingFrame } : { backing: true }
        };
        commands.push(filterCmd);
        if (entity.filter_mode === "blacklist") {
          const blacklistFrame = db.icons["utility/filter-blacklist"];
          if (blacklistFrame !== void 0) {
            commands.push({
              kind: "icon",
              layer: RENDER_LAYERS["entity-info-icon-above"],
              sortY: 0,
              sortX: 0,
              entity: entity.entity_number,
              sub: startSub + commands.length,
              frame: blacklistFrame,
              x: filterCmd.x + filterCmd.size * 0.28,
              y: filterCmd.y + filterCmd.size * 0.28,
              size: filterCmd.size * 0.45
            });
          }
        }
        continue;
      }
      if (arrowFrame === void 0) continue;
      const arrowSize = db.iconScales?.["utility/indication-arrow"];
      if (arrowSize === void 0) continue;
      commands.push({
        kind: "icon",
        layer: RENDER_LAYERS["entity-info-icon-above"],
        sortY: 0,
        sortX: 0,
        entity: entity.entity_number,
        sub: startSub + commands.length,
        frame: arrowFrame,
        x,
        y,
        size: arrowSize,
        rotation: angle
      });
    }
    return commands;
  }
  function isDirectionalCombinator(def) {
    return def.protoType === "arithmetic-combinator" || def.protoType === "decider-combinator" || def.protoType === "selector-combinator";
  }
  function combinatorFlowCommands(entity, def, db) {
    if (!isDirectionalCombinator(def)) return [];
    const frame = db.icons["utility/indication-arrow"];
    const spriteScale = db.iconScales?.["utility/indication-arrow"];
    if (frame === void 0 || spriteScale === void 0) return [];
    const size = spriteScale * 1.5;
    const direction = cardinalDirection(entity.direction ?? 0);
    const angle = direction * 22.5;
    const radians = angle * Math.PI / 180;
    const forward = [Math.sin(radians), -Math.cos(radians)];
    const halfSpan = Math.max(
      Math.abs(def.selectionBox[0][0]),
      Math.abs(def.selectionBox[0][1]),
      Math.abs(def.selectionBox[1][0]),
      Math.abs(def.selectionBox[1][1])
    );
    const frameMeta = db.frames[frame];
    const visibleArrowHeight = frameMeta ? size * (frameMeta.h / Math.max(1, frameMeta.sh)) : 0;
    const flowOffset = Math.max(0, halfSpan - visibleArrowHeight);
    return [-1, 1].map((side, index) => ({
      kind: "icon",
      layer: RENDER_LAYERS["entity-info-icon-above"],
      sortY: 0,
      sortX: 0,
      entity: entity.entity_number,
      sub: 110 + index,
      frame,
      x: entity.position.x + forward[0] * flowOffset * side,
      y: entity.position.y + forward[1] * flowOffset * side,
      size,
      rotation: angle
    }));
  }
  function skipsFluidIndication(def) {
    return def.kind === "pipe" || def.protoType === "pipe-to-ground" || def.protoType === "storage-tank";
  }
  function fluidPortIndicationCommands(entity, def, db, startSub) {
    if (skipsFluidIndication(def) || !def.data?.fluidConnections) return [];
    const oneWayFrame = db.icons["utility/fluid-indication-arrow"];
    const bothWaysFrame = db.icons["utility/fluid-indication-arrow-both-ways"];
    const oneWayScale = db.iconScales?.["utility/fluid-indication-arrow"];
    const bothWaysScale = db.iconScales?.["utility/fluid-indication-arrow-both-ways"];
    if (oneWayFrame === void 0 || oneWayScale === void 0) return [];
    const ports = activeFluidPorts(entity, def, db);
    const commands = [];
    for (let i = 0; i < ports.length; i++) {
      const port = ports[i];
      const bothWays = port.flow === "input-output";
      const frame = bothWays ? bothWaysFrame ?? oneWayFrame : oneWayFrame;
      const size = bothWays ? bothWaysScale ?? oneWayScale : oneWayScale;
      const [dx, dy] = DIR_DELTA[port.facing];
      const outward = size * 1.25;
      const x = entity.position.x + port.offset[0] - dx + dx * outward;
      const y = entity.position.y + port.offset[1] - dy + dy * outward;
      const rotation = port.facing * 22.5 + (port.flow === "input" ? 180 : 0);
      commands.push({
        kind: "icon",
        layer: RENDER_LAYERS["entity-info-icon-above"],
        sortY: 0,
        sortX: 0,
        entity: entity.entity_number,
        sub: startSub + i,
        frame,
        x,
        y,
        size,
        rotation
      });
    }
    return commands;
  }
  function emptyInserterFilterCommand(entity, def, db) {
    if (def.kind !== "inserter" || entity.use_filters !== true) return void 0;
    if (filterSignals(entity.filters).length > 0) return void 0;
    const frame = db.icons["virtual-signal/signal-no-entry"];
    if (frame === void 0) return void 0;
    const spec = iconDrawSpec(def);
    return {
      kind: "icon",
      layer: RENDER_LAYERS["entity-info-icon-above"],
      sortY: 0,
      sortX: 0,
      entity: entity.entity_number,
      sub: 112,
      frame,
      x: entity.position.x + spec.shift[0],
      y: entity.position.y + spec.shift[1],
      size: spec.scale,
      silhouette: true
    };
  }
  function planAltModeCommands(entity, def, db, opts) {
    const spec = iconDrawSpec(def);
    const primary = resolveAltSignals(db, entitySignals(entity, def));
    const primaryScale = primary.length > 1 ? spec.scaleForMany : spec.scale;
    const primaryOffsets = iconLayout(primary.length, primaryScale);
    const darkBackingFrame = db.icons["utility/entity-info-dark-background"];
    const layer = RENDER_LAYERS[spec.renderLayer];
    const primaryCommands = primary.map(({ frame }, index) => ({
      kind: "icon",
      layer,
      sortY: 0,
      sortX: 0,
      entity: entity.entity_number,
      sub: index,
      frame,
      x: entity.position.x + spec.shift[0] + (primaryOffsets[index]?.[0] ?? 0),
      y: entity.position.y + spec.shift[1] + (primaryOffsets[index]?.[1] ?? 0),
      size: primaryScale,
      ...darkBackingFrame !== void 0 ? { backingFrame: darkBackingFrame } : { backing: true }
    }));
    const insertCommands = opts?.insertCommands ?? [];
    const insertPlans = insertCommands.length > 0 ? resolveAltSignals(db, insertPlanSignals(entity.items, def)).slice(0, insertCommands.length) : [];
    const commands = [
      ...primaryCommands,
      ...qualityBadgeCommands(primary, primaryCommands, entity.entity_number, db, 50),
      ...insertCommands.length > 0 ? qualityBadgeCommands(insertPlans, insertCommands, entity.entity_number, db, 60) : []
    ];
    if (entity.filter_mode === "blacklist" && commands.length > 0 && !splitterLaneFilter(entity, def)) {
      const frame = db.icons["utility/filter-blacklist"];
      if (frame !== void 0) {
        commands.push({
          kind: "icon",
          layer: RENDER_LAYERS["entity-info-icon-above"],
          sortY: 0,
          sortX: 0,
          entity: entity.entity_number,
          sub: 80,
          frame,
          x: commands[0].x + commands[0].size * 0.28,
          y: commands[0].y + commands[0].size * 0.28,
          size: commands[0].size * 0.45
        });
      }
    }
    const quality = entity.quality;
    if (quality && quality !== "normal") {
      const frame = db.icons[`quality/${quality}`] ?? db.icons["utility/missing-icon"];
      if (frame !== void 0) {
        const size = ENTITY_QUALITY_BADGE_TILES * qualityIndicatorScale(def);
        const [x1] = def.selectionBox[0];
        const [, y2] = def.selectionBox[1];
        commands.push({
          kind: "icon",
          layer: RENDER_LAYERS["entity-info-icon-above"],
          sortY: 0,
          sortX: 0,
          entity: entity.entity_number,
          sub: 90,
          frame,
          x: entity.position.x + x1 + size / 2,
          y: entity.position.y + y2 - size / 2,
          size
        });
      }
    }
    commands.push(...splitterPriorityCommands(entity, def, db, 100));
    commands.push(...combinatorFlowCommands(entity, def, db));
    commands.push(...fluidPortIndicationCommands(entity, def, db, 120));
    const emptyFilter = emptyInserterFilterCommand(entity, def, db);
    if (emptyFilter) commands.push(emptyFilter);
    return commands;
  }

  // tools/vendor/fpsr/packages/renderer/src/cargo-bay-connections.ts
  var CONNECTABLE_PROTOS = /* @__PURE__ */ new Set(["space-platform-hub", "cargo-bay", "cargo-landing-pad"]);
  var CONNECTION_GRID_SIZE = 2;
  var NEIGHBOR8 = [
    [-1, -1],
    // 0 top-left
    [0, -1],
    // 1 top
    [1, -1],
    // 2 top-right
    [1, 0],
    // 3 right
    [1, 1],
    // 4 bottom-right
    [0, 1],
    // 5 bottom
    [-1, 1],
    // 6 bottom-left
    [-1, 0]
    // 7 left
  ];
  function tileKey(x, y) {
    return `${x},${y}`;
  }
  function hashTile(x, y) {
    let h = Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) | 0;
    h = Math.imul(h ^ h >>> 13, 1274126177);
    return (h ^ h >>> 16) >>> 0;
  }
  function footprintCells(entity, def) {
    const [[x1, y1], [x2, y2]] = def.collisionBox;
    const minX = Math.floor(entity.position.x + x1 + 1e-6);
    const maxX = Math.ceil(entity.position.x + x2 - 1e-6) - 1;
    const minY = Math.floor(entity.position.y + y1 + 1e-6);
    const maxY = Math.ceil(entity.position.y + y2 - 1e-6) - 1;
    const cells = [];
    for (let y = minY; y <= maxY; y += CONNECTION_GRID_SIZE) {
      for (let x = minX; x <= maxX; x += CONNECTION_GRID_SIZE) {
        const centerX = x + CONNECTION_GRID_SIZE / 2;
        const centerY = y + CONNECTION_GRID_SIZE / 2;
        cells.push({
          gridX: Math.floor(centerX / CONNECTION_GRID_SIZE),
          gridY: Math.floor(centerY / CONNECTION_GRID_SIZE),
          x: centerX,
          y: centerY
        });
      }
    }
    return cells;
  }
  function spriteDest(posX, posY, frame, variant) {
    const w = frame.sw * variant.scale / 32;
    const h = frame.sh * variant.scale * (variant.scaleY ?? 1) / 32;
    const cx = posX + variant.shift[0];
    const cy = posY + variant.shift[1];
    return { x: cx - w / 2, y: cy - h / 2, w, h };
  }
  function pickConnections(def, preferPlatform) {
    return preferPlatform ? def.data?.cargoBayConnectionsPlatform ?? def.data?.cargoBayConnections : def.data?.cargoBayConnections ?? def.data?.cargoBayConnectionsPlatform;
  }
  function pickCellVariation(groups, tx, ty) {
    if (groups.length === 0) return void 0;
    const groupIndex = groups.length > 1 ? tx + ty & 1 : 0;
    const group = groups[groupIndex] ?? groups[0];
    if (!group || group.length === 0) return void 0;
    const variation = group[hashTile(tx, ty) % group.length];
    return variation;
  }
  function emitCell(cell, cx, cy, db, entityNumber, subBase, sortY, sortX, commands) {
    let sub = subBase;
    for (const layer of cell.layers) {
      const frame = db.frames[layer.variant.frame];
      if (!frame) continue;
      const dest = spriteDest(cx, cy, frame, layer.variant);
      const layerName = layer.layer;
      const cmd = {
        kind: "sprite",
        layer: RENDER_LAYERS[layerName],
        sortY,
        sortX,
        entity: entityNumber,
        sub: sub++,
        frame: layer.variant.frame,
        x: dest.x,
        y: dest.y,
        w: dest.w,
        h: dest.h
      };
      if (layer.variant.drawAsShadow) cmd.shadow = true;
      if (layer.variant.tint) cmd.tint = layer.variant.tint;
      commands.push(cmd);
    }
    return sub;
  }
  function occupancyMask(occ, tx, ty) {
    let mask = 0;
    for (let bit = 0; bit < 8; bit++) {
      const [dx, dy] = NEIGHBOR8[bit];
      if (occ.has(tileKey(tx + dx, ty + dy))) mask |= 1 << bit;
    }
    return mask;
  }
  function buildConnectables(bp, db, preferPlatform) {
    const out = [];
    for (const entity of bp.entities ?? []) {
      const def = db.entities[entity.name];
      if (!def || !CONNECTABLE_PROTOS.has(def.protoType) && !CONNECTABLE_PROTOS.has(entity.name)) {
        continue;
      }
      if (entity.name !== "space-platform-hub" && entity.name !== "cargo-bay" && entity.name !== "cargo-landing-pad") {
        continue;
      }
      const connections = pickConnections(def, preferPlatform);
      if (!connections) continue;
      const cells = footprintCells(entity, def);
      if (cells.length === 0) continue;
      let minX = Infinity;
      let maxX = -Infinity;
      let minY = Infinity;
      let maxY = -Infinity;
      const [[x1, y1], [x2, y2]] = def.collisionBox;
      minX = Math.floor(entity.position.x + x1 + 1e-6);
      maxX = Math.ceil(entity.position.x + x2 - 1e-6) - 1;
      minY = Math.floor(entity.position.y + y1 + 1e-6);
      maxY = Math.ceil(entity.position.y + y2 - 1e-6) - 1;
      out.push({ entity, def, connections, cells, minX, maxX, minY, maxY });
    }
    return out;
  }
  function emitCargoBayConnections(bp, db, preferPlatform, commands) {
    const connectables = buildConnectables(bp, db, preferPlatform);
    if (connectables.length === 0) return;
    const occ = /* @__PURE__ */ new Set();
    const owner = /* @__PURE__ */ new Map();
    for (const c of connectables) {
      for (const cell of c.cells) {
        const k = tileKey(cell.gridX, cell.gridY);
        occ.add(k);
        owner.set(k, { connectable: c, cell });
      }
    }
    let sub = 1e4;
    const connRef = connectables[0].connections;
    for (const key of occ) {
      const [xs, ys] = key.split(",");
      const gridX = Number(xs);
      const gridY = Number(ys);
      const mask = occupancyMask(occ, gridX, gridY);
      const mapped = connRef.tilesetMapping[String(mask)];
      if (mapped == null || mapped === 0) continue;
      const indices = Array.isArray(mapped) ? mapped : [mapped];
      const owned = owner.get(key);
      if (!owned) continue;
      const { cell, connectable: cellOwner } = owned;
      const sortY = cellOwner.entity.position.y + cellOwner.def.collisionBox[1][1];
      const sortX = cellOwner.entity.position.x;
      for (const oneBased of indices) {
        if (oneBased === 0) continue;
        const groups = connRef.tileset[oneBased - 1];
        if (!groups) continue;
        const variation = pickCellVariation(groups, gridX, gridY);
        if (!variation) continue;
        sub = emitCell(
          variation,
          cell.x,
          cell.y,
          db,
          cellOwner.entity.entity_number,
          sub,
          sortY,
          sortX,
          commands
        );
      }
    }
    const hBridges = [];
    const vBridges = [];
    for (let i = 0; i < connectables.length; i++) {
      for (let j = i + 1; j < connectables.length; j++) {
        const emitted = emitBridgePair(connectables[i], connectables[j], db, commands, () => {
          const s = sub;
          sub += 20;
          return s;
        });
        if (emitted) {
          if (emitted.axis === "h") hBridges.push(emitted);
          else vBridges.push(emitted);
        }
      }
    }
    const crossingCells = connRef.bridges.crossing;
    if (crossingCells.length > 0) {
      const covered = (tx, ty) => connectables.some((c) => tx >= c.minX && tx <= c.maxX && ty >= c.minY && ty <= c.maxY);
      const crossingPoints = /* @__PURE__ */ new Map();
      for (const h of hBridges) {
        for (const v of vBridges) {
          const cx = h.midX;
          const cy = v.midY;
          if (cy < h.y0 || cy > h.y1 + 1) continue;
          if (cx < v.x0 || cx > v.x1 + 1) continue;
          if (!covered(cx - 1, cy - 1) || !covered(cx, cy - 1) || !covered(cx - 1, cy) || !covered(cx, cy)) {
            continue;
          }
          crossingPoints.set(tileKey(cx, cy), { x: cx, y: cy });
        }
      }
      for (const { x, y } of crossingPoints.values()) {
        const cell = crossingCells[hashTile(Math.floor(x), Math.floor(y)) % crossingCells.length];
        sub = emitCell(cell, x, y, db, connectables[0].entity.entity_number, sub, y, x, commands);
      }
    }
  }
  function sharedEdge(a, b) {
    if (a.maxX + 1 === b.minX || b.maxX + 1 === a.minX) {
      const left = a.maxX + 1 === b.minX ? a : b;
      const right = left === a ? b : a;
      const y0 = Math.max(left.minY, right.minY);
      const y1 = Math.min(left.maxY, right.maxY);
      if (y1 < y0) return null;
      const midX = left.maxX + 1;
      const midY = (y0 + y1 + 1) / 2;
      return { axis: "h", x0: left.maxX, x1: right.minX, y0, y1, midX, midY };
    }
    if (a.maxY + 1 === b.minY || b.maxY + 1 === a.minY) {
      const top = a.maxY + 1 === b.minY ? a : b;
      const bottom = top === a ? b : a;
      const x0 = Math.max(top.minX, bottom.minX);
      const x1 = Math.min(top.maxX, bottom.maxX);
      if (x1 < x0) return null;
      const midX = (x0 + x1 + 1) / 2;
      const midY = top.maxY + 1;
      return { axis: "v", x0, x1, y0: top.maxY, y1: bottom.minY, midX, midY };
    }
    return null;
  }
  function emitBridgePair(a, b, db, commands, nextSub) {
    const edge = sharedEdge(a, b);
    if (!edge) return null;
    const span = edge.axis === "h" ? edge.y1 - edge.y0 + 1 : edge.x1 - edge.x0 + 1;
    const bridges = a.connections.bridges;
    const wide = span >= 4;
    const cells = edge.axis === "h" ? wide ? bridges.horizontalWide : bridges.horizontalNarrow : wide ? bridges.verticalWide : bridges.verticalNarrow;
    if (cells.length === 0) return null;
    const cell = cells[hashTile(Math.floor(edge.midX), Math.floor(edge.midY)) % cells.length];
    const sortY = Math.max(
      a.entity.position.y + a.def.collisionBox[1][1],
      b.entity.position.y + b.def.collisionBox[1][1]
    );
    const sortX = (a.entity.position.x + b.entity.position.x) / 2;
    emitCell(
      cell,
      edge.midX,
      edge.midY,
      db,
      a.entity.entity_number,
      nextSub(),
      sortY,
      sortX,
      commands
    );
    return edge;
  }

  // tools/vendor/fpsr/packages/renderer/src/types/blueprint.ts
  function decodeVersion(v) {
    return {
      major: Math.floor(v / 2 ** 48) % 2 ** 16,
      minor: Math.floor(v / 2 ** 32) % 2 ** 16,
      patch: Math.floor(v / 2 ** 16) % 2 ** 16
    };
  }

  // tools/vendor/fpsr/packages/renderer/src/wire-connectors.ts
  var WIRE_CONNECTOR_ID = {
    circuit_red: 1,
    circuit_green: 2,
    combinator_input_red: 1,
    combinator_input_green: 2,
    combinator_output_red: 3,
    combinator_output_green: 4,
    pole_copper: 5,
    power_switch_left_copper: 5,
    power_switch_right_copper: 6
  };
  function wireConnectorColor(connectorId) {
    switch (connectorId) {
      case WIRE_CONNECTOR_ID.circuit_red:
      case WIRE_CONNECTOR_ID.combinator_output_red:
        return "red";
      case WIRE_CONNECTOR_ID.circuit_green:
      case WIRE_CONNECTOR_ID.combinator_output_green:
        return "green";
      case WIRE_CONNECTOR_ID.pole_copper:
      case WIRE_CONNECTOR_ID.power_switch_right_copper:
        return "copper";
      default:
        return void 0;
    }
  }

  // tools/vendor/fpsr/packages/renderer/src/migrate.ts
  var FACTORIO_2_VERSION_MAJOR = 2 * 2 ** 48;
  var scaleLegacyDirections = {
    id: "scale-legacy-directions",
    apply(bp) {
      if (!bp.entities?.length) return bp;
      return {
        ...bp,
        entities: bp.entities.map(
          (e) => e.direction == null ? e : { ...e, direction: e.direction * 2 % 16 }
        )
      };
    }
  };
  function legacyItemsObjectToInsertPlans(items) {
    if (items == null) return void 0;
    if (Array.isArray(items)) return items;
    if (typeof items !== "object") return void 0;
    const out = [];
    for (const [name, count] of Object.entries(items)) {
      if (!name) continue;
      const gridCount = typeof count === "number" && Number.isFinite(count) ? count : 1;
      out.push({
        id: { name, type: "item" },
        items: { grid_count: gridCount }
      });
    }
    return out;
  }
  var itemsObjectToArray = {
    id: "items-object-to-array",
    apply(bp) {
      if (!bp.entities?.length) return bp;
      let changed = false;
      const entities = bp.entities.map((e) => {
        const raw = e.items;
        if (raw == null || Array.isArray(raw)) return e;
        if (typeof raw !== "object") return e;
        changed = true;
        const next = {
          ...e,
          items: legacyItemsObjectToInsertPlans(raw)
        };
        return next;
      });
      return changed ? { ...bp, entities } : bp;
    }
  };
  function legacyCircuitConnectorId(point, color) {
    if (point === 2) {
      return color === "red" ? WIRE_CONNECTOR_ID.combinator_output_red : WIRE_CONNECTOR_ID.combinator_output_green;
    }
    return color === "red" ? WIRE_CONNECTOR_ID.circuit_red : WIRE_CONNECTOR_ID.circuit_green;
  }
  function canonicalizeWire(wire) {
    const [a, ac, b, bc] = wire;
    if (a < b || a === b && ac <= bc) return wire;
    return [b, bc, a, ac];
  }
  function wireKey(wire) {
    const [a, ac, b, bc] = canonicalizeWire(wire);
    return `${a},${ac},${b},${bc}`;
  }
  var connectionsNeighboursToWires = {
    id: "connections-neighbours-to-wires",
    apply(bp) {
      if (!bp.entities?.length) return bp;
      const seen = /* @__PURE__ */ new Set();
      const wires = [];
      const addWire = (wire) => {
        const key = wireKey(wire);
        if (seen.has(key)) return;
        seen.add(key);
        wires.push(canonicalizeWire(wire));
      };
      for (const existing of bp.wires ?? []) {
        if (Array.isArray(existing) && existing.length >= 4) {
          addWire([existing[0], existing[1], existing[2], existing[3]]);
        }
      }
      let converted = false;
      for (const entity of bp.entities) {
        const connections = entity.connections;
        if (connections && typeof connections === "object") {
          for (const [pointKey, colors] of Object.entries(connections)) {
            const point = Number(pointKey);
            if (point !== 1 && point !== 2) continue;
            if (!colors || typeof colors !== "object") continue;
            for (const color of ["red", "green"]) {
              const links = colors[color];
              if (!Array.isArray(links)) continue;
              const srcConnector = legacyCircuitConnectorId(point, color);
              for (const link of links) {
                const dstEntity = link?.entity_id;
                if (typeof dstEntity !== "number" || !Number.isFinite(dstEntity)) continue;
                const dstPoint = typeof link.circuit_id === "number" && Number.isFinite(link.circuit_id) ? link.circuit_id : 1;
                if (dstPoint !== 1 && dstPoint !== 2) continue;
                converted = true;
                addWire([
                  entity.entity_number,
                  srcConnector,
                  dstEntity,
                  legacyCircuitConnectorId(dstPoint, color)
                ]);
              }
            }
          }
        }
        const neighbours = entity.neighbours;
        if (Array.isArray(neighbours)) {
          for (const neighbor of neighbours) {
            if (typeof neighbor !== "number" || !Number.isFinite(neighbor)) continue;
            converted = true;
            addWire([
              entity.entity_number,
              WIRE_CONNECTOR_ID.pole_copper,
              neighbor,
              WIRE_CONNECTOR_ID.pole_copper
            ]);
          }
        }
      }
      if (!converted && wires.length === (bp.wires?.length ?? 0)) return bp;
      return { ...bp, wires };
    }
  };
  var LEGACY_ENTITY_RENAMES = {
    "straight-rail": "legacy-straight-rail",
    "curved-rail": "legacy-curved-rail",
    "filter-inserter": "fast-inserter",
    "stack-filter-inserter": "bulk-inserter",
    "stack-inserter": "bulk-inserter",
    "logistic-chest-passive-provider": "passive-provider-chest",
    "logistic-chest-active-provider": "active-provider-chest",
    "logistic-chest-storage": "storage-chest",
    "logistic-chest-buffer": "buffer-chest",
    "logistic-chest-requester": "requester-chest"
  };
  function renameLegacyEntityName(name) {
    return LEGACY_ENTITY_RENAMES[name] ?? name;
  }
  var renameLegacyEntities = {
    id: "rename-legacy-entities",
    apply(bp) {
      let changed = false;
      const entities = bp.entities?.map((e) => {
        const next = renameLegacyEntityName(e.name);
        if (next === e.name) return e;
        changed = true;
        return { ...e, name: next };
      });
      const icons = bp.icons?.map((icon) => {
        const signal = icon.signal;
        if (!signal?.name) return icon;
        const next = renameLegacyEntityName(signal.name);
        if (next === signal.name) return icon;
        changed = true;
        return { ...icon, signal: { ...signal, name: next } };
      });
      if (!changed) return bp;
      return {
        ...bp,
        ...entities ? { entities } : {},
        ...icons ? { icons } : {}
      };
    }
  };
  var BLUEPRINT_ADAPTERS = [
    scaleLegacyDirections,
    itemsObjectToArray,
    connectionsNeighboursToWires,
    renameLegacyEntities
  ];
  function bumpVersionMajorTo2(version) {
    return FACTORIO_2_VERSION_MAJOR + version % 2 ** 48;
  }
  function migrateTo2x(bp) {
    const ver = bp.version ?? 0;
    if (decodeVersion(ver).major >= 2) return bp;
    let out = { ...bp };
    for (const adapter of BLUEPRINT_ADAPTERS) {
      out = adapter.apply(out);
    }
    return { ...out, version: bumpVersionMajorTo2(ver) };
  }

  // tools/vendor/fpsr/packages/renderer/src/profile.ts
  function nowMs() {
    if (typeof performance !== "undefined" && typeof performance.now === "function") {
      return performance.now();
    }
    return Date.now();
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/belts.ts
  var BELT_STRAIGHT_INDEX = {
    0: 2,
    4: 0,
    8: 3,
    12: 1
  };
  var BELT_CURVE_RIGHT = {
    0: 4,
    // east_to_north
    4: 8,
    // south_to_east
    8: 11,
    // west_to_south
    12: 7
    // north_to_west
  };
  var BELT_CURVE_LEFT = {
    0: 6,
    // west_to_north
    4: 5,
    // north_to_east
    8: 9,
    // east_to_south
    12: 10
    // south_to_west
  };
  var BELT_START_INDEX = {
    0: 12,
    // starting_south
    4: 14,
    // starting_west
    8: 16,
    // starting_north
    12: 18
    // starting_east
  };
  var BELT_END_INDEX = {
    0: 17,
    // ending_north
    4: 19,
    // ending_east
    8: 13,
    // ending_south
    12: 15
    // ending_west
  };
  var BELT_CONNECTABLE = /* @__PURE__ */ new Set([
    "belt",
    "underground-belt",
    "splitter",
    "loader"
  ]);
  var UG_STRUCTURE_INDEX = [0, 1, 2, 3];
  function undergroundStructureIndex(direction, type) {
    const dir4 = dir16ToIndex(direction, "direction4");
    const structureDir4 = type === "output" ? (dir4 + 2) % 4 : dir4;
    return UG_STRUCTURE_INDEX[structureDir4] ?? structureDir4;
  }
  function buildBeltTileIndex(entities, db) {
    const index = /* @__PURE__ */ new Map();
    const add = (x, y, occ) => {
      const key = posKey(x, y);
      const list = index.get(key);
      if (list) list.push(occ);
      else index.set(key, [occ]);
    };
    for (const entity of entities) {
      const def = db.entities[entity.name];
      if (!def || !BELT_CONNECTABLE.has(def.kind)) continue;
      const occ = { entity, def };
      if (def.kind === "splitter") {
        const dir = cardinalDirection(entity.direction);
        const raw = def.data?.tileSize;
        const baseW = raw?.[0] ?? 2;
        const baseH = raw?.[1] ?? 1;
        const w = dir === 0 || dir === 8 ? baseW : baseH;
        const h = dir === 0 || dir === 8 ? baseH : baseW;
        const cx = entity.position.x;
        const cy = entity.position.y;
        for (let ix = 0; ix < w; ix++) {
          for (let iy = 0; iy < h; iy++) {
            add(cx - w / 2 + 0.5 + ix, cy - h / 2 + 0.5 + iy, occ);
          }
        }
      } else {
        add(entity.position.x, entity.position.y, occ);
      }
    }
    return index;
  }
  function rotatedNeighbors(beltIndex, x, y, dir) {
    const abs = [
      beltIndex.get(posKey(x, y - 1))?.[0],
      beltIndex.get(posKey(x + 1, y))?.[0],
      beltIndex.get(posKey(x, y + 1))?.[0],
      beltIndex.get(posKey(x - 1, y))?.[0]
    ];
    const start = dir / 4;
    return [abs[start], abs[(start + 1) % 4], abs[(start + 2) % 4], abs[(start + 3) % 4]];
  }
  function facesTowardBelt(occ, absRelDir) {
    if (!occ) return false;
    if ((occ.def.kind === "underground-belt" || occ.def.kind === "loader") && occ.entity.type === "input") {
      return false;
    }
    return cardinalDirection(occ.entity.direction) === opposite(absRelDir);
  }
  function beltCurveIndex(entity, beltIndex) {
    const dir = cardinalDirection(entity.direction);
    const { x, y } = entity.position;
    const C = rotatedNeighbors(beltIndex, x, y, dir);
    const absDirs = [
      dir,
      (dir + 4) % 16,
      opposite(dir),
      (dir + 12) % 16
    ];
    const C2 = C.map((occ, i) => {
      const abs = absDirs[i];
      return abs !== void 0 && facesTowardBelt(occ, abs) ? occ : void 0;
    });
    if (C2[1] && !C2[3] && !C2[2]) return BELT_CURVE_RIGHT[dir];
    if (C2[3] && !C2[1] && !C2[2]) return BELT_CURVE_LEFT[dir];
    return BELT_STRAIGHT_INDEX[dir];
  }
  function beltCircuitConnectorVariation(entity, beltIndex) {
    const dir = cardinalDirection(entity.direction);
    const { x, y } = entity.position;
    const C = rotatedNeighbors(beltIndex, x, y, dir);
    const absDirs = [
      dir,
      (dir + 4) % 16,
      opposite(dir),
      (dir + 12) % 16
    ];
    const C2 = C.map((occ, i) => {
      const abs = absDirs[i];
      return abs !== void 0 && facesTowardBelt(occ, abs) ? occ : void 0;
    });
    if (C2[1] && C2[3]) return 0;
    if (C2[1] && !C2[3] && !C2[2]) {
      return BELT_CURVE_ANIM_TO_CONNECTOR[BELT_CURVE_RIGHT[dir]] ?? 0;
    }
    if (C2[3] && !C2[1] && !C2[2]) {
      return BELT_CURVE_ANIM_TO_CONNECTOR[BELT_CURVE_LEFT[dir]] ?? 0;
    }
    return dir === 4 || dir === 12 ? 1 : 2;
  }
  var BELT_CURVE_ANIM_TO_CONNECTOR = {
    4: 5,
    // east_to_north → NE
    5: 5,
    // north_to_east → NE
    6: 6,
    // west_to_north → NW
    7: 6,
    // north_to_west → NW
    8: 3,
    // south_to_east → SE
    9: 3,
    // east_to_south → SE
    10: 4,
    // south_to_west → SW
    11: 4
    // west_to_south → SW
  };
  function beltConnectorBackPatchIndex(variation) {
    if (variation <= 2) return 0;
    if (variation <= 4) return 1;
    return 2;
  }
  var BELT_READER_BAND = {
    solid: 0,
    open: 1,
    curved: 2,
    ending: 3
  };
  var BELT_READER_FRAME = {
    north: 0,
    east: 1,
    south: 2,
    west: 3
  };
  var BELT_READER_FRAME_FROM_DIR = {
    0: BELT_READER_FRAME.north,
    4: BELT_READER_FRAME.east,
    8: BELT_READER_FRAME.south,
    12: BELT_READER_FRAME.west
  };
  var CONNECTOR_CORNER_TO_READER_FRAME = {
    5: BELT_READER_FRAME.north,
    // NE — arc along north+east
    3: BELT_READER_FRAME.east,
    // SE
    4: BELT_READER_FRAME.south,
    // SW
    6: BELT_READER_FRAME.west
    // NW — arc along west+north
  };
  function endingMirrorSlot(frame) {
    switch (frame) {
      case BELT_READER_FRAME.east:
        return { band: BELT_READER_BAND.ending, frame, flipX: true, shift: [1, 0] };
      case BELT_READER_FRAME.west:
        return { band: BELT_READER_BAND.ending, frame, flipX: true, shift: [-1, 0] };
      case BELT_READER_FRAME.north:
        return { band: BELT_READER_BAND.ending, frame, flipY: true, shift: [0, -1] };
      case BELT_READER_FRAME.south:
        return { band: BELT_READER_BAND.ending, frame, flipY: true, shift: [0, 1] };
      default:
        return { band: BELT_READER_BAND.ending, frame };
    }
  }
  function beltReaderSlots(entity, def, beltIndex, readerEntities) {
    const dir = cardinalDirection(entity.direction);
    const curve = beltCurveIndex(entity, beltIndex);
    const isCurve = curve >= 4 && curve <= 11;
    if (isCurve) {
      const corner = BELT_CURVE_ANIM_TO_CONNECTOR[curve] ?? 5;
      const frame = CONNECTOR_CORNER_TO_READER_FRAME[corner] ?? BELT_READER_FRAME.north;
      return [{ band: BELT_READER_BAND.curved, frame }];
    }
    const sides = dir === 4 || dir === 12 ? [BELT_READER_FRAME.north, BELT_READER_FRAME.south] : [BELT_READER_FRAME.east, BELT_READER_FRAME.west];
    const slots = sides.map((frame) => ({
      band: BELT_READER_BAND.solid,
      frame
    }));
    const forward = nextOnLine(entity, def, dir, beltIndex);
    const backward = nextOnLine(entity, def, opposite(dir), beltIndex);
    const forwardInLine = forward != null && readerEntities.has(forward.entity_number);
    const backwardInLine = backward != null && readerEntities.has(backward.entity_number);
    const pushEnding = (frame) => {
      slots.push({ band: BELT_READER_BAND.ending, frame });
      slots.push(endingMirrorSlot(frame));
    };
    if (!forwardInLine) pushEnding(BELT_READER_FRAME_FROM_DIR[dir]);
    if (!backwardInLine) pushEnding(BELT_READER_FRAME_FROM_DIR[opposite(dir)]);
    return slots;
  }
  var BELT_CONTENT_READ_ENTIRE = 2;
  function isBeltCircuitOutputEnabled(entity) {
    const cb = entity.control_behavior;
    if (!cb) return false;
    return cb.circuit_enabled === true || cb.circuit_enable_disable === true;
  }
  function isBeltCircuitInputEnabled(entity) {
    return entity.control_behavior?.circuit_read_hand_contents === true;
  }
  function beltCircuitConnectorFrame(entity) {
    return (isBeltCircuitOutputEnabled(entity) ? 1 : 0) | (isBeltCircuitInputEnabled(entity) ? 2 : 0);
  }
  function isEntireBeltHold(entity) {
    const cb = entity.control_behavior;
    if (!cb || cb.circuit_read_hand_contents !== true) return false;
    return cb.circuit_contents_read_mode === BELT_CONTENT_READ_ENTIRE;
  }
  function collectBeltReaderEntities(bp, db, beltIndex) {
    const out = /* @__PURE__ */ new Set();
    const entities = bp.entities ?? [];
    for (const e of entities) {
      const def = db.entities[e.name];
      if (!def || def.kind !== "belt") continue;
      if (!isEntireBeltHold(e)) continue;
      for (const id of walkTransportLine(e, beltIndex, db)) out.add(id);
    }
    return out;
  }
  function walkTransportLine(start, beltIndex, db) {
    const ids = [];
    const seen = /* @__PURE__ */ new Set();
    const queue = [start];
    while (queue.length > 0) {
      const cur = queue.pop();
      if (!cur || seen.has(cur.entity_number)) continue;
      seen.add(cur.entity_number);
      const def = db.entities[cur.name];
      if (!def) continue;
      if (def.kind === "belt" || def.kind === "underground-belt") {
        ids.push(cur.entity_number);
      }
      if (def.kind === "belt" || def.kind === "underground-belt") {
        const dir = cardinalDirection(cur.direction);
        const forward = nextOnLine(cur, def, dir, beltIndex);
        const backward = nextOnLine(cur, def, opposite(dir), beltIndex);
        if (forward) queue.push(forward);
        if (backward) queue.push(backward);
        if (def.kind === "belt") {
          const feeder = curvePerpendicularFeeder(cur, beltIndex);
          if (feeder) queue.push(feeder);
        }
      }
    }
    return ids;
  }
  function curvePerpendicularFeeder(entity, beltIndex) {
    const dir = cardinalDirection(entity.direction);
    const { x, y } = entity.position;
    const C = rotatedNeighbors(beltIndex, x, y, dir);
    const absDirs = [
      dir,
      (dir + 4) % 16,
      opposite(dir),
      (dir + 12) % 16
    ];
    const C2 = C.map((occ, i) => {
      const abs = absDirs[i];
      return abs !== void 0 && facesTowardBelt(occ, abs) ? occ : void 0;
    });
    if (C2[1] && !C2[3] && !C2[2]) return C2[1]?.entity;
    if (C2[3] && !C2[1] && !C2[2]) return C2[3]?.entity;
    return void 0;
  }
  function nextOnLine(cur, curDef, stepDir, beltIndex) {
    if (curDef.kind === "underground-belt") {
      const facing = cardinalDirection(cur.direction);
      const isOutput = cur.type === "output";
      if (!isOutput && stepDir === facing || isOutput && stepDir === opposite(facing)) {
        return findUndergroundPartner(cur, beltIndex) ?? void 0;
      }
    }
    const [dx, dy] = DIR_DELTA[stepDir];
    const occupants = beltIndex.get(posKey(cur.position.x + dx, cur.position.y + dy));
    if (!occupants?.length) return void 0;
    for (const occ of occupants) {
      if (occ.def.kind === "splitter") return void 0;
      if (occ.def.kind === "belt" || occ.def.kind === "underground-belt") {
        const od = cardinalDirection(occ.entity.direction);
        if (od === stepDir || od === opposite(stepDir)) return occ.entity;
        if (occ.def.kind === "belt") {
          const feeder = curvePerpendicularFeeder(occ.entity, beltIndex);
          if (feeder && feeder.entity_number === cur.entity_number) return occ.entity;
        }
        return void 0;
      }
    }
    return void 0;
  }
  function findUndergroundPartner(ug, beltIndex) {
    const facing = cardinalDirection(ug.direction);
    const isOutput = ug.type === "output";
    const step = isOutput ? opposite(facing) : facing;
    const [dx, dy] = DIR_DELTA[step];
    const maxDist = 10;
    for (let i = 1; i <= maxDist; i++) {
      const x = ug.position.x + dx * i;
      const y = ug.position.y + dy * i;
      const occupants = beltIndex.get(posKey(x, y));
      if (!occupants) continue;
      for (const occ of occupants) {
        if (occ.def.kind !== "underground-belt") continue;
        if (occ.entity.name !== ug.name) continue;
        if (cardinalDirection(occ.entity.direction) !== facing) continue;
        const partnerIsOutput = occ.entity.type === "output";
        if (partnerIsOutput === isOutput) continue;
        return occ.entity;
      }
    }
    return null;
  }
  function hasBeltFeederAt(x, y, dir, beltIndex) {
    const C = rotatedNeighbors(beltIndex, x, y, dir);
    const absDirs = [
      dir,
      (dir + 4) % 16,
      opposite(dir),
      (dir + 12) % 16
    ];
    for (let i = 1; i < 4; i++) {
      const abs = absDirs[i];
      if (abs !== void 0 && facesTowardBelt(C[i], abs)) return true;
    }
    return false;
  }
  function hasBeltFeeder(entity, beltIndex) {
    return hasBeltFeederAt(
      entity.position.x,
      entity.position.y,
      cardinalDirection(entity.direction),
      beltIndex
    );
  }
  function hasOpenSideFeeder(entity, beltIndex) {
    const dir = cardinalDirection(entity.direction);
    const { x, y } = entity.position;
    const C = rotatedNeighbors(beltIndex, x, y, dir);
    return facesTowardBelt(C[2], opposite(dir));
  }
  function hasBeltConsumerAt(x, y, dir, beltIndex) {
    const [dx, dy] = DIR_DELTA[dir];
    const occupants = beltIndex.get(posKey(x + dx, y + dy));
    if (!occupants) return false;
    for (const occ of occupants) {
      if (occ.def.kind === "belt" || occ.def.kind === "splitter") return true;
      if (occ.def.kind === "underground-belt" || occ.def.kind === "loader") {
        if (occ.entity.type === "output") continue;
        if (cardinalDirection(occ.entity.direction) === dir) return true;
      }
    }
    return false;
  }
  function hasBeltConsumer(entity, beltIndex) {
    return hasBeltConsumerAt(
      entity.position.x,
      entity.position.y,
      cardinalDirection(entity.direction),
      beltIndex
    );
  }
  function beltCapShift(dir, kind) {
    return kind === "start" ? rotateOffset(0, 1, dir) : rotateOffset(0, -1, dir);
  }

  // tools/vendor/fpsr/packages/renderer/src/pole-orientation.ts
  function getAngle(cX, cY, pX, pY) {
    const x = pX - cX;
    const y = pY - cY;
    if (x === 0 && y === 0) return 0;
    const angle = Math.acos(x / Math.sqrt(x * x + y * y)) * 180 / Math.PI;
    if (y < 0) return 360 - angle;
    return angle;
  }
  function angleToSector(angle) {
    const cwAngle = 360 - angle;
    const sectorAngle = 360 / 8;
    const offset = sectorAngle * 1.5;
    let newAngle = cwAngle - offset;
    if (Math.sign(newAngle) === -1) {
      newAngle = 360 + newAngle;
    }
    const sector = Math.floor(newAngle / sectorAngle);
    return sector % 4;
  }
  function powerPoleRotationFromNeighbors(centre, points) {
    if (points.length === 0) return 0;
    const sectorSum = points.map((p) => getAngle(0, 0, p.x - centre.x, (p.y - centre.y) * -1)).map(angleToSector).reduce((acc, sec) => acc + sec, 0);
    return Math.floor(sectorSum / points.length) * 4;
  }
  function wireNeighborNumbers(bp, entityNumber) {
    const wires = bp.wires;
    if (!wires?.length) return [];
    const out = [];
    for (const w of wires) {
      if (!Array.isArray(w) || w.length < 4) continue;
      const [a, , b] = w;
      if (a === entityNumber) out.push(b);
      else if (b === entityNumber) out.push(a);
    }
    return out;
  }
  function effectivePowerPoleDirection(entity, bp, byNumber) {
    if (entity.direction !== void 0 && entity.direction !== null) {
      return (entity.direction % 16 + 16) % 16;
    }
    const neighborNums = wireNeighborNumbers(bp, entity.entity_number);
    if (neighborNums.length === 0) return 0;
    const points = [];
    for (const n of neighborNums) {
      const other = byNumber.get(n);
      if (other) points.push(other.position);
    }
    if (points.length === 0) return 0;
    return powerPoleRotationFromNeighbors(entity.position, points);
  }
  function buildPowerPoleDirections(bp, entities, isElectricPole) {
    const byNumber = new Map(entities.map((e) => [e.entity_number, e]));
    const out = /* @__PURE__ */ new Map();
    for (const e of entities) {
      if (!isElectricPole(e)) continue;
      out.set(e.entity_number, effectivePowerPoleDirection(e, bp, byNumber));
    }
    return out;
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/pipes.ts
  function heatPortDirection(ox, oy) {
    if (Math.abs(ox) >= Math.abs(oy)) return ox >= 0 ? 4 : 12;
    return oy >= 0 ? 8 : 0;
  }
  function buildHeatPortGrid(entities, db) {
    const ports = /* @__PURE__ */ new Map();
    for (const entity of entities) {
      const def = db.entities[entity.name];
      const connections = def?.data?.heatConnections;
      if (!connections) continue;
      const d = cardinalDirection(entity.direction);
      for (const [ox, oy] of connections[String(d)] ?? []) {
        const direction = heatPortDirection(ox, oy);
        const [dx, dy] = DIR_DELTA[direction];
        const key = posKey(entity.position.x + ox - dx, entity.position.y + oy - dy);
        const list = ports.get(key);
        const occupant = { entityNumber: entity.entity_number, direction };
        if (list) list.push(occupant);
        else ports.set(key, [occupant]);
      }
    }
    return ports;
  }
  function heatPortConnected(entity, targetOffset, heatPorts, grid, db) {
    const [ox, oy] = targetOffset;
    const direction = heatPortDirection(ox, oy);
    const targetX = entity.position.x + ox;
    const targetY = entity.position.y + oy;
    if (hasNeighbor(grid, targetX, targetY, (n) => db.entities[n.name]?.kind === "heat-pipe")) {
      return true;
    }
    return (heatPorts.get(posKey(targetX, targetY)) ?? []).some(
      (port) => port.entityNumber !== entity.entity_number && port.direction === opposite(direction)
    );
  }
  function buildFluidPipeSides(entities, db) {
    const map = /* @__PURE__ */ new Map();
    for (const entity of entities) {
      const def = db.entities[entity.name];
      if (!def?.data?.fluidConnections) continue;
      if (def.kind === "pipe") continue;
      for (const [ox, oy] of activeFluidOffsets(entity, def, db)) {
        const pipeX = entity.position.x + ox;
        const pipeY = entity.position.y + oy;
        const pk = posKey(pipeX, pipeY);
        const dx = entity.position.x - pipeX;
        const dy = entity.position.y - pipeY;
        let side;
        if (Math.abs(dx) >= Math.abs(dy)) {
          side = dx > 0 ? "e" : "w";
        } else {
          side = dy > 0 ? "s" : "n";
        }
        let set = map.get(pk);
        if (!set) {
          set = /* @__PURE__ */ new Set();
          map.set(pk, set);
        }
        set.add(side);
      }
    }
    return map;
  }
  function buildHeatPipeSides(entities, db) {
    const map = /* @__PURE__ */ new Map();
    for (const entity of entities) {
      const def = db.entities[entity.name];
      if (!def?.data?.heatConnections || def.kind === "heat-pipe") continue;
      const d = cardinalDirection(entity.direction);
      for (const [ox, oy] of def.data.heatConnections[String(d)] ?? []) {
        const pipeX = entity.position.x + ox;
        const pipeY = entity.position.y + oy;
        const pk = posKey(pipeX, pipeY);
        const dx = entity.position.x - pipeX;
        const dy = entity.position.y - pipeY;
        const side = Math.abs(dx) >= Math.abs(dy) ? dx > 0 ? "e" : "w" : dy > 0 ? "s" : "n";
        let set = map.get(pk);
        if (!set) {
          set = /* @__PURE__ */ new Set();
          map.set(pk, set);
        }
        set.add(side);
      }
    }
    return map;
  }
  function pipeMask(entity, grid, db, fluidPipeSides) {
    const { x, y } = entity.position;
    const check = (nx, ny, side) => {
      if (hasNeighbor(grid, nx, ny, (n2) => db.entities[n2.name]?.kind === "pipe")) {
        return true;
      }
      if (fluidPipeSides.get(posKey(x, y))?.has(side)) return true;
      const neighbors = grid.get(posKey(nx, ny));
      if (neighbors) {
        for (const n2 of neighbors) {
          const nd = db.entities[n2.name];
          if (!nd) continue;
          if (nd.protoType === "pipe-to-ground" || n2.name === "pipe-to-ground") {
            const openDir = cardinalDirection(n2.direction);
            const [dx, dy] = DIR_DELTA[openDir];
            if (Math.abs(n2.position.x + dx - x) < 0.01 && Math.abs(n2.position.y + dy - y) < 0.01) {
              return true;
            }
          }
          const fc = nd.data?.fluidConnections;
          if (fc) {
            for (const [ox, oy] of activeFluidOffsets(n2, nd, db)) {
              if (Math.abs(n2.position.x + ox - x) < 0.01 && Math.abs(n2.position.y + oy - y) < 0.01) {
                return true;
              }
            }
          }
        }
      }
      return false;
    };
    const n = check(x, y - 1, "n") ? "1" : "0";
    const e = check(x + 1, y, "e") ? "1" : "0";
    const s = check(x, y + 1, "s") ? "1" : "0";
    const w = check(x - 1, y, "w") ? "1" : "0";
    return `${n}${e}${s}${w}`;
  }
  function heatPipeMask(entity, grid, db, heatPipeSides) {
    const { x, y } = entity.position;
    const check = (nx, ny, side) => {
      if (heatPipeSides.get(posKey(x, y))?.has(side)) return true;
      const neighbors = grid.get(posKey(nx, ny));
      if (!neighbors) return false;
      for (const n2 of neighbors) {
        const nd = db.entities[n2.name];
        if (!nd) continue;
        if (nd.kind === "heat-pipe") return true;
        const hc = nd.data?.heatConnections;
        if (!hc) continue;
        const d = cardinalDirection(n2.direction);
        for (const [ox, oy] of hc[String(d)] ?? []) {
          if (Math.abs(n2.position.x + ox - x) < 0.01 && Math.abs(n2.position.y + oy - y) < 0.01) {
            return true;
          }
        }
      }
      return false;
    };
    const n = check(x, y - 1, "n") ? "1" : "0";
    const e = check(x + 1, y, "e") ? "1" : "0";
    const s = check(x, y + 1, "s") ? "1" : "0";
    const w = check(x - 1, y, "w") ? "1" : "0";
    return `${n}${e}${s}${w}`;
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/context.ts
  function blueprintPrefersPlatformGraphics(blueprint, entities = blueprint.entities ?? []) {
    if (entities.some((e) => e.name === "space-platform-hub")) return true;
    return (blueprint.tiles ?? []).some((t) => t.name.startsWith("space-platform-"));
  }
  function createResolveContext(blueprint, db) {
    const entities = blueprint.entities ?? [];
    const grid = buildNeighborGrid(entities);
    const beltIndex = buildBeltTileIndex(entities, db);
    const fluidPipeSides = buildFluidPipeSides(entities, db);
    const heatPipeSides = buildHeatPipeSides(entities, db);
    const poleDirs = buildPowerPoleDirections(
      blueprint,
      entities,
      (entity) => db.entities[entity.name]?.protoType === "electric-pole"
    );
    const preferPlatformGraphics = blueprintPrefersPlatformGraphics(blueprint, entities);
    return {
      blueprint,
      db,
      entities,
      grid,
      beltIndex,
      fluidPipeSides,
      heatPipeSides,
      poleDirs,
      preferPlatformGraphics
    };
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/trains.ts
  function projectVehicleOrientation(orientation) {
    const turn = (orientation % 1 + 1) % 1;
    let x = Math.sin(turn * Math.PI * 2);
    const y = -Math.cos(turn * Math.PI * 2);
    x *= Math.SQRT1_2;
    let out = Math.atan2(x, -y) / (Math.PI * 2);
    if (out < 0) out += 1;
    return out;
  }
  function trainOrientationIndex(orientation, poseCount, backEqualsFront = false) {
    if (poseCount <= 0) return 0;
    const o = (orientation % 1 + 1) % 1;
    if (backEqualsFront) {
      return Math.round(o * poseCount * 2) % poseCount;
    }
    return Math.round(o * poseCount) % poseCount;
  }
  function projectTrainOrientation(orientation) {
    const turn = (orientation % 1 + 1) % 1;
    const x = Math.sin(turn * Math.PI * 2);
    let y = -Math.cos(turn * Math.PI * 2);
    y *= Math.SQRT1_2;
    let out = Math.atan2(x, -y) / (Math.PI * 2);
    if (out < 0) out += 1;
    return out;
  }
  function trainRailShiftY(orientation) {
    const o = (orientation % 1 + 1) % 1;
    const angle = o * Math.PI * 2;
    return -0.25 * Math.abs(Math.cos(angle + Math.PI / 2));
  }
  var TRAIN_PROJECTION = Math.SQRT1_2;
  function artilleryCannonShift(orientation, opts) {
    const o = (orientation % 1 + 1) % 1;
    const n = typeof opts.orientationCount === "number" && opts.orientationCount > 0 ? opts.orientationCount : 64;
    const projected = projectTrainOrientation(o);
    const aligned = trainOrientationIndex(projected, n) / n;
    const vf = Math.abs(Math.abs(aligned - 0.5) - 0.25) * 4;
    const vert = opts.cannonBaseShiftWhenVertical ?? 0;
    const horiz = opts.cannonBaseShiftWhenHorizontal ?? 0;
    const offsetForward = -(vert * vf + horiz * (1 - vf));
    const offsetHeight = opts.cannonBaseHeight ?? 0;
    const rotation = o * Math.PI * 2 + Math.PI / 2;
    const offsetX = offsetForward * Math.cos(rotation);
    const offsetY = offsetForward * Math.sin(rotation);
    return [offsetX, offsetY * TRAIN_PROJECTION - offsetHeight * TRAIN_PROJECTION];
  }
  function trainWheelShifts(orientation, jointDistance) {
    const o = (orientation % 1 + 1) % 1;
    const projected = projectTrainOrientation(o);
    const half = jointDistance / 2;
    const angle = o * Math.PI * 2;
    const ox = Math.sin(angle) * half;
    const oy = -Math.cos(angle) * half;
    const vert = trainRailShiftY(o);
    const flipped = projectTrainOrientation((o + 0.5) % 1);
    return [
      { shift: [ox, oy + vert], orientation: flipped },
      { shift: [-ox, -oy + vert], orientation: projected }
    ];
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/walls.ts
  function wallPictureKey(e, s, w) {
    if (s) {
      if (e && w) return "0111";
      if (e) return "0110";
      if (w) return "0011";
      return "1010";
    }
    if (e && w) return "0101";
    if (e) return "0100";
    if (w) return "0001";
    return "0000";
  }
  function wallMask(entity, grid, db) {
    const { x, y } = entity.position;
    const pred = (n) => {
      const nd = db.entities[n.name];
      return nd?.kind === "wall" || nd?.kind === "gate";
    };
    const e = hasNeighbor(grid, x + 1, y, pred);
    const s = hasNeighbor(grid, x, y + 1, pred);
    const w = hasNeighbor(grid, x - 1, y, pred);
    return wallPictureKey(e, s, w);
  }
  function gateVariantKey(entity) {
    const dir = cardinalDirection(entity.direction);
    return dir === 0 || dir === 8 ? "horizontal" : "vertical";
  }

  // tools/vendor/fpsr/packages/renderer/src/resolve/index.ts
  function variantKeyFor(entity, def, grid, db, fluidPipeSides, heatPipeSides, opts) {
    switch (def.kind) {
      case "underground-belt":
      case "loader":
        return entity.type === "output" ? "out" : "in";
      case "pipe":
        return pipeMask(entity, grid, db, fluidPipeSides);
      case "heat-pipe":
        return heatPipeMask(entity, grid, db, heatPipeSides);
      case "wall":
        return wallMask(entity, grid, db);
      case "gate":
        return gateVariantKey(entity);
      default:
        if (opts?.preferPlatformGraphics && def.graphics.some((g) => g.variants.platform !== void 0)) {
          return "platform";
        }
        return "default";
    }
  }
  function indexFor(entity, def, group, beltIndex, poleDirs) {
    if (def.kind === "vehicle") {
      const n = (typeof def.data?.orientationCount === "number" && def.data.orientationCount > 0 ? def.data.orientationCount : group.variants.default?.length) ?? 1;
      return trainOrientationIndex(projectVehicleOrientation(entity.orientation ?? 0), n);
    }
    if (def.kind === "train") {
      const n = (typeof def.data?.orientationCount === "number" && def.data.orientationCount > 0 ? def.data.orientationCount : group.variants.default?.length) ?? 1;
      const projected = projectTrainOrientation(entity.orientation ?? 0);
      const groupIndex = def.graphics.indexOf(group);
      const isWheels = typeof def.data?.wheelsGroupIndex === "number" && groupIndex === def.data.wheelsGroupIndex;
      return trainOrientationIndex(projected, n, def.data?.backEqualsFront === true && !isWheels);
    }
    const direction = def.protoType === "electric-pole" && poleDirs?.has(entity.entity_number) ? poleDirs.get(entity.entity_number) ?? 0 : entity.direction ?? 0;
    if (group.indexing === "resolver") {
      if (def.kind === "belt") {
        return beltCurveIndex(entity, beltIndex);
      }
      return dir16ToIndex(direction, "direction4");
    }
    if ((group.layer === "object" || group.layer === "object-under") && (def.kind === "underground-belt" || def.kind === "loader") && group.indexing === "direction4") {
      return undergroundStructureIndex(entity.direction ?? 0, entity.type);
    }
    if (def.kind === "inserter" && group.indexing === "direction4" && def.graphics[0] === group) {
      return (dir16ToIndex(entity.direction ?? 0, "direction4") + 2) % 4;
    }
    return dir16ToIndex(direction, group.indexing);
  }
  function resolveWithContext(context, warningsOut, opts) {
    const beltEndings = opts?.beltEndings ?? true;
    const { beltIndex, db, entities, fluidPipeSides, grid, poleDirs, preferPlatformGraphics } = context;
    const heatPipeSides = context.heatPipeSides ?? buildHeatPipeSides(entities, db);
    const heatPorts = buildHeatPortGrid(entities, db);
    const out = [];
    for (const entity of entities) {
      const def = db.entities[entity.name];
      if (!def) {
        warningsOut?.push(`Unknown entity "${entity.name}" (entity_number=${entity.entity_number})`);
        continue;
      }
      const variantKey = variantKeyFor(entity, def, grid, db, fluidPipeSides, heatPipeSides, {
        preferPlatformGraphics
      });
      const selections = [];
      for (let group = 0; group < def.graphics.length; group++) {
        const layerGroup = def.graphics[group];
        if (!layerGroup) continue;
        if (!isFluidWorkingVisualisationGroupActive(entity, def, db, group)) {
          continue;
        }
        if (def.data?.heatConnectionPatchGroupIndices?.includes(group)) {
          const d = cardinalDirection(entity.direction);
          for (const [portIndex, targetOffset] of (def.data.heatConnections?.[String(d)] ?? []).entries()) {
            const direction = heatPortDirection(targetOffset[0], targetOffset[1]);
            const [dx, dy] = DIR_DELTA[direction];
            selections.push({
              group,
              variantKey: heatPortConnected(entity, targetOffset, heatPorts, grid, db) ? "connected" : "disconnected",
              index: portIndex,
              shift: [targetOffset[0] - dx, targetOffset[1] - dy]
            });
          }
          continue;
        }
        const index = indexFor(entity, def, layerGroup, beltIndex, poleDirs);
        const key = layerGroup.variants[variantKey] !== void 0 ? variantKey : layerGroup.variants.default !== void 0 ? "default" : variantKey;
        if (def.kind === "train" && group === def.data?.wheelsGroupIndex) {
          const joint = typeof def.data?.jointDistance === "number" && def.data.jointDistance > 0 ? def.data.jointDistance : 4;
          const n = (typeof def.data?.orientationCount === "number" && def.data.orientationCount > 0 ? def.data.orientationCount : layerGroup.variants.default?.length) ?? 1;
          for (const bogie of trainWheelShifts(entity.orientation ?? 0, joint)) {
            selections.push({
              group,
              variantKey: key,
              index: trainOrientationIndex(bogie.orientation, n),
              shift: bogie.shift
            });
          }
          continue;
        }
        if (def.kind === "splitter" && layerGroup.layer === "transport-belt") {
          const dir = cardinalDirection(entity.direction);
          const dir4 = dir16ToIndex(entity.direction ?? 0, "direction4");
          const lanes = [rotateOffset(-0.5, 0, dir), rotateOffset(0.5, 0, dir)];
          for (const lane of lanes) {
            selections.push({
              group,
              variantKey: key,
              index,
              shift: lane
            });
            if (!beltEndings) continue;
            const lx = entity.position.x + lane[0];
            const ly = entity.position.y + lane[1];
            if (layerGroup.variants.start && !hasBeltFeederAt(lx, ly, dir, beltIndex)) {
              const [sx, sy] = beltCapShift(dir, "start");
              selections.push({
                group,
                variantKey: "start",
                index: dir4,
                shift: [lane[0] + sx, lane[1] + sy]
              });
            }
            if (layerGroup.variants.end && !hasBeltConsumerAt(lx, ly, dir, beltIndex)) {
              const [ex, ey] = beltCapShift(dir, "end");
              selections.push({
                group,
                variantKey: "end",
                index: dir4,
                shift: [lane[0] + ex, lane[1] + ey]
              });
            }
          }
          continue;
        }
        if ((def.kind === "underground-belt" || def.kind === "loader") && layerGroup.layer === "transport-belt") {
          selections.push({ group, variantKey: key, index });
          if (beltEndings) {
            const dir = cardinalDirection(entity.direction);
            const dir4 = dir16ToIndex(entity.direction ?? 0, "direction4");
            const isOutput = entity.type === "output";
            if (!isOutput && layerGroup.variants.start && !hasOpenSideFeeder(entity, beltIndex)) {
              selections.push({
                group,
                variantKey: "start",
                index: dir4,
                shift: beltCapShift(dir, "start")
              });
            }
            if (isOutput && layerGroup.variants.end && !hasBeltConsumer(entity, beltIndex)) {
              selections.push({
                group,
                variantKey: "end",
                index: dir4,
                shift: beltCapShift(dir, "end")
              });
            }
          }
          continue;
        }
        if (def.kind === "train") {
          const railY = trainRailShiftY(entity.orientation ?? 0);
          const cannonIdxs = def.data?.cannonGroupIndices;
          if (Array.isArray(cannonIdxs) && cannonIdxs.includes(group)) {
            const [cx, cy] = artilleryCannonShift(entity.orientation ?? 0, {
              cannonBaseHeight: typeof def.data?.cannonBaseHeight === "number" ? def.data.cannonBaseHeight : void 0,
              cannonBaseShiftWhenVertical: typeof def.data?.cannonBaseShiftWhenVertical === "number" ? def.data.cannonBaseShiftWhenVertical : void 0,
              cannonBaseShiftWhenHorizontal: typeof def.data?.cannonBaseShiftWhenHorizontal === "number" ? def.data.cannonBaseShiftWhenHorizontal : void 0,
              orientationCount: typeof def.data?.orientationCount === "number" ? def.data.orientationCount : void 0
            });
            selections.push({
              group,
              variantKey: key,
              index,
              shift: [cx, cy + railY]
            });
          } else {
            selections.push({ group, variantKey: key, index, shift: [0, railY] });
          }
          continue;
        }
        selections.push({ group, variantKey: key, index });
        if (beltEndings && def.kind === "belt" && layerGroup.indexing === "resolver" && (layerGroup.variants[key]?.length ?? 0) >= 20) {
          const dir = cardinalDirection(entity.direction);
          if (!hasBeltFeeder(entity, beltIndex)) {
            selections.push({
              group,
              variantKey: key,
              index: BELT_START_INDEX[dir],
              shift: beltCapShift(dir, "start")
            });
          }
          if (!hasBeltConsumer(entity, beltIndex)) {
            selections.push({
              group,
              variantKey: key,
              index: BELT_END_INDEX[dir],
              shift: beltCapShift(dir, "end")
            });
          }
        }
      }
      out.push({ entity, def, selections });
    }
    return out;
  }
  function resolve(bp, db, opts) {
    const warnings = [];
    const entities = resolveWithContext(createResolveContext(migrateTo2x(bp), db), warnings, opts);
    return { entities, warnings };
  }

  // tools/vendor/fpsr/packages/renderer/src/icon-silhouette.ts
  var ENTITY_INFO_SILHOUETTE_RADIUS_PX = 12;
  var ENTITY_INFO_SILHOUETTE_BLUR_PX = 16;
  function entityInfoSilhouettePadPx(dilateRadius = ENTITY_INFO_SILHOUETTE_RADIUS_PX, blurRadius = ENTITY_INFO_SILHOUETTE_BLUR_PX) {
    return dilateRadius + blurRadius;
  }

  // tools/vendor/fpsr/packages/renderer/src/train-chains.ts
  var DEFAULT_CONNECTION_DISTANCE = 3;
  var DEFAULT_JOINT_DISTANCE = 4;
  var TRAIN_CHAIN_JOINT_RADIUS = 0.3;
  var COUPLE_TOLERANCE = 0.25;
  function round4(n) {
    return Math.round(n * 1e4) / 1e4;
  }
  function jointDistanceOf(def) {
    const j = def.data?.jointDistance;
    return typeof j === "number" && j > 0 ? j : DEFAULT_JOINT_DISTANCE;
  }
  function connectionDistanceOf(def) {
    const c = def.data?.connectionDistance;
    return typeof c === "number" && c > 0 ? c : DEFAULT_CONNECTION_DISTANCE;
  }
  function trainJointWorldPoints(entity, jointDistance) {
    const bogies = trainWheelShifts(entity.orientation ?? 0, jointDistance);
    const front = bogies[0];
    const back = bogies[1];
    return {
      front: [round4(entity.position.x + front.shift[0]), round4(entity.position.y + front.shift[1])],
      back: [round4(entity.position.x + back.shift[0]), round4(entity.position.y + back.shift[1])]
    };
  }
  function dist(a, b) {
    return Math.hypot(a[0] - b[0], a[1] - b[1]);
  }
  function jointKey(x, y) {
    return `${Math.round(x * 1e4) / 1e4},${Math.round(y * 1e4) / 1e4}`;
  }
  function addSegment(segments, seen, a, b, endInset = 0) {
    const k1 = `${jointKey(a[0], a[1])}|${jointKey(b[0], b[1])}`;
    const k2 = `${jointKey(b[0], b[1])}|${jointKey(a[0], a[1])}`;
    if (seen.has(k1) || seen.has(k2)) return;
    seen.add(k1);
    let x1 = a[0];
    let y1 = a[1];
    let x2 = b[0];
    let y2 = b[1];
    if (endInset > 0) {
      const len = Math.hypot(x2 - x1, y2 - y1);
      if (len <= endInset * 2) return;
      const ux = (x2 - x1) / len;
      const uy = (y2 - y1) / len;
      x1 = round4(x1 + ux * endInset);
      y1 = round4(y1 + uy * endInset);
      x2 = round4(x2 - ux * endInset);
      y2 = round4(y2 - uy * endInset);
    }
    segments.push({ x1, y1, x2, y2 });
  }
  function addJoint(joints, seen, p) {
    const k = jointKey(p[0], p[1]);
    if (seen.has(k)) return;
    seen.add(k);
    joints.push({ x: p[0], y: p[1] });
  }
  function sideOfNeighbor(links, neighbor, stock, fallback) {
    const n = links.get(neighbor);
    if (n?.front === stock) return "front";
    if (n?.back === stock) return "back";
    return fallback;
  }
  function parseStockConnections(raw, trainNums) {
    if (!raw?.length) return [];
    const links = /* @__PURE__ */ new Map();
    for (const entry of raw) {
      if (!entry || typeof entry.stock !== "number") continue;
      if (!trainNums.has(entry.stock)) continue;
      const cur = links.get(entry.stock) ?? {};
      if (typeof entry.front === "number") cur.front = entry.front;
      if (typeof entry.back === "number") cur.back = entry.back;
      links.set(entry.stock, cur);
    }
    const edges = [];
    const seen = /* @__PURE__ */ new Set();
    for (const [stock, sides] of links) {
      for (const aSide of ["front", "back"]) {
        const neighbor = sides[aSide];
        if (typeof neighbor !== "number" || !trainNums.has(neighbor) || neighbor === stock) {
          continue;
        }
        const lo = Math.min(stock, neighbor);
        const hi = Math.max(stock, neighbor);
        const key = `${lo}-${hi}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const fallback = aSide === "front" ? "back" : "front";
        const bSide = sideOfNeighbor(links, neighbor, stock, fallback);
        edges.push({ a: stock, aSide, b: neighbor, bSide });
      }
    }
    return edges;
  }
  function inferCouplings(trains, jointsByNum) {
    const edges = [];
    const seen = /* @__PURE__ */ new Set();
    for (let i = 0; i < trains.length; i++) {
      const a = trains[i];
      const ja = jointsByNum.get(a.entity.entity_number);
      if (!ja) continue;
      const connA = connectionDistanceOf(a.def);
      for (let j = i + 1; j < trains.length; j++) {
        const b = trains[j];
        const jb = jointsByNum.get(b.entity.entity_number);
        if (!jb) continue;
        const connB = connectionDistanceOf(b.def);
        const expected = (connA + connB) / 2;
        const candidates = [
          { aSide: "front", bSide: "front", d: dist(ja.front, jb.front) },
          { aSide: "front", bSide: "back", d: dist(ja.front, jb.back) },
          { aSide: "back", bSide: "front", d: dist(ja.back, jb.front) },
          { aSide: "back", bSide: "back", d: dist(ja.back, jb.back) }
        ];
        let best;
        for (const c of candidates) {
          if (Math.abs(c.d - expected) > COUPLE_TOLERANCE) continue;
          if (!best || c.d < best.d) best = c;
        }
        if (!best) continue;
        const lo = Math.min(a.entity.entity_number, b.entity.entity_number);
        const hi = Math.max(a.entity.entity_number, b.entity.entity_number);
        const key = `${lo}-${hi}`;
        if (seen.has(key)) continue;
        seen.add(key);
        edges.push({
          a: a.entity.entity_number,
          aSide: best.aSide,
          b: b.entity.entity_number,
          bSide: best.bSide
        });
      }
    }
    return edges;
  }
  function pointOf(joints, side) {
    return side === "front" ? joints.front : joints.back;
  }
  function buildTrainChainGeometry(bp, byNumber) {
    const trains = [];
    for (const entry of byNumber.values()) {
      if (entry.def.kind === "train") trains.push(entry);
    }
    if (trains.length === 0) return null;
    const trainNums = new Set(trains.map((t) => t.entity.entity_number));
    const jointsByNum = /* @__PURE__ */ new Map();
    for (const t of trains) {
      jointsByNum.set(
        t.entity.entity_number,
        trainJointWorldPoints(t.entity, jointDistanceOf(t.def))
      );
    }
    let edges = parseStockConnections(bp.stock_connections, trainNums);
    if (edges.length === 0) {
      edges = inferCouplings(trains, jointsByNum);
    }
    if (edges.length === 0) return null;
    const segments = [];
    const joints = [];
    const segSeen = /* @__PURE__ */ new Set();
    const jointSeen = /* @__PURE__ */ new Set();
    for (const e of edges) {
      const ja = jointsByNum.get(e.a);
      const jb = jointsByNum.get(e.b);
      if (!ja || !jb) continue;
      const aPt = pointOf(ja, e.aSide);
      const bPt = pointOf(jb, e.bSide);
      addJoint(joints, jointSeen, aPt);
      addJoint(joints, jointSeen, bPt);
      addSegment(segments, segSeen, aPt, bPt, TRAIN_CHAIN_JOINT_RADIUS);
    }
    if (segments.length === 0 && joints.length === 0) return null;
    return { segments, joints };
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/bounds.ts
  function spriteDest2(posX, posY, frame, variant, extraShift) {
    const w = frame.sw * variant.scale / 32;
    const h = frame.sh * variant.scale * (variant.scaleY ?? 1) / 32;
    const sx = extraShift?.[0] ?? 0;
    const sy = extraShift?.[1] ?? 0;
    const cx = posX + variant.shift[0] + sx;
    const cy = posY + variant.shift[1] + sy;
    return { x: cx - w / 2, y: cy - h / 2, w, h };
  }
  function undergroundBeltUnderlayClip(dest, openDir) {
    switch (openDir) {
      case 4:
        return { x: dest.x + dest.w / 2, y: dest.y, w: dest.w / 2, h: dest.h };
      case 12:
        return { x: dest.x, y: dest.y, w: dest.w / 2, h: dest.h };
      case 8:
        return { x: dest.x, y: dest.y + dest.h / 2, w: dest.w, h: dest.h / 2 };
      case 0:
        return { x: dest.x, y: dest.y, w: dest.w, h: dest.h / 2 };
    }
  }
  function expandBounds(bounds, x, y, w, h) {
    const minX = x;
    const minY = y;
    const maxX = x + w;
    const maxY = y + h;
    if (!bounds) {
      return { minX, minY, maxX, maxY };
    }
    return {
      minX: Math.min(bounds.minX, minX),
      minY: Math.min(bounds.minY, minY),
      maxX: Math.max(bounds.maxX, maxX),
      maxY: Math.max(bounds.maxY, maxY)
    };
  }
  function spriteVisibleBounds(cmd, frame) {
    if (cmd.src) {
      return { x: cmd.x, y: cmd.y, w: cmd.w, h: cmd.h };
    }
    const scaleX = frame.sw === 0 ? 0 : cmd.w / frame.sw;
    const scaleY = frame.sh === 0 ? 0 : cmd.h / frame.sh;
    const cx = cmd.x + cmd.w / 2;
    const cy = cmd.y + cmd.h / 2;
    let left = cmd.x + frame.ox * scaleX;
    let top = cmd.y + frame.oy * scaleY;
    let right = left + frame.w * scaleX;
    let bottom = top + frame.h * scaleY;
    if (cmd.flipX) [left, right] = [2 * cx - right, 2 * cx - left];
    if (cmd.flipY) [top, bottom] = [2 * cy - bottom, 2 * cy - top];
    const rotation = cmd.rotation ?? 0;
    if (rotation % 360 !== 0) {
      const radians = rotation * Math.PI / 180;
      const cos = Math.cos(radians);
      const sin = Math.sin(radians);
      const corners = [
        [left, top],
        [right, top],
        [right, bottom],
        [left, bottom]
      ];
      const rotated = corners.map(([x, y]) => {
        const dx = x - cx;
        const dy = y - cy;
        return [cx + dx * cos - dy * sin, cy + dx * sin + dy * cos];
      });
      left = Math.min(...rotated.map(([x]) => x));
      top = Math.min(...rotated.map(([, y]) => y));
      right = Math.max(...rotated.map(([x]) => x));
      bottom = Math.max(...rotated.map(([, y]) => y));
    }
    if (cmd.clip) {
      left = Math.max(left, cmd.clip.x);
      top = Math.max(top, cmd.clip.y);
      right = Math.max(left, Math.min(right, cmd.clip.x + cmd.clip.w));
      bottom = Math.max(top, Math.min(bottom, cmd.clip.y + cmd.clip.h));
    }
    return { x: left, y: top, w: right - left, h: bottom - top };
  }
  function includeCmdBounds(bounds, cmd, frames, frameOverride) {
    switch (cmd.kind) {
      case "sprite": {
        const frame = frameOverride ?? frames?.[cmd.frame];
        const visible = frame ? spriteVisibleBounds(cmd, frame) : cmd;
        return expandBounds(bounds, visible.x, visible.y, visible.w, visible.h);
      }
      case "rect": {
        return expandBounds(bounds, cmd.x, cmd.y, cmd.w, cmd.h);
      }
      case "icon": {
        const backing = cmd.backingFrame == null ? void 0 : frames?.[cmd.backingFrame];
        const isRequestPin = cmd.backingStyle === "request-pin";
        const backingBasePx = isRequestPin ? Math.max(1, (backing?.w ?? 48) * (44 / 48)) : 32;
        const backingScale = cmd.size / backingBasePx;
        const silhouettePad = !isRequestPin && (cmd.backingFrame != null || cmd.backing === true || cmd.silhouette === true) ? entityInfoSilhouettePadPx() / 32 * cmd.size : 0;
        const width = Math.max(cmd.size + 2 * silhouettePad, (backing?.sw ?? 0) * backingScale);
        const height = Math.max(cmd.size + 2 * silhouettePad, (backing?.sh ?? 0) * backingScale);
        return expandBounds(bounds, cmd.x - width / 2, cmd.y - height / 2, width, height);
      }
      case "wire": {
        const minX = Math.min(cmd.x1, cmd.x2);
        const minY = Math.min(cmd.y1, cmd.y2);
        const maxX = Math.max(cmd.x1, cmd.x2);
        const maxY = Math.max(cmd.y1, cmd.y2);
        const mx = (cmd.x1 + cmd.x2) / 2;
        const my = (cmd.y1 + cmd.y2) / 2;
        const dist2 = Math.hypot(cmd.x2 - cmd.x1, cmd.y2 - cmd.y1);
        const sagY = my + 0.15 * dist2;
        return expandBounds(
          expandBounds(bounds, minX, minY, maxX - minX, maxY - minY),
          mx,
          sagY,
          0,
          0
        );
      }
      case "train-chain": {
        let b = bounds;
        for (const s of cmd.segments) {
          const minX = Math.min(s.x1, s.x2);
          const minY = Math.min(s.y1, s.y2);
          const maxX = Math.max(s.x1, s.x2);
          const maxY = Math.max(s.y1, s.y2);
          b = expandBounds(b, minX, minY, maxX - minX, maxY - minY);
        }
        for (const j of cmd.joints) {
          b = expandBounds(
            b,
            j.x - TRAIN_CHAIN_JOINT_RADIUS,
            j.y - TRAIN_CHAIN_JOINT_RADIUS,
            TRAIN_CHAIN_JOINT_RADIUS * 2,
            TRAIN_CHAIN_JOINT_RADIUS * 2
          );
        }
        return b ?? { minX: 0, minY: 0, maxX: 0, maxY: 0 };
      }
      case "snap-grid": {
        return expandBounds(bounds, cmd.x, cmd.y, cmd.w, cmd.h);
      }
      case "text": {
        const width = Math.max(cmd.size, cmd.text.length * cmd.size * 0.55);
        const height = cmd.size;
        const align = cmd.align ?? "left";
        const baseline = cmd.baseline ?? "top";
        const x = align === "center" ? cmd.x - width / 2 : align === "right" ? cmd.x - width : cmd.x;
        const y = baseline === "middle" ? cmd.y - height / 2 : baseline === "alphabetic" ? cmd.y - height : cmd.y;
        return expandBounds(bounds, x, y, width, height);
      }
    }
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/belt-readers.ts
  function paintBeltReaderLayer(official) {
    return RENDER_LAYERS[official] ?? RENDER_LAYERS["transport-belt-reader"];
  }
  function beltReaderLayerOrder(name) {
    return RENDER_LAYERS[name] ?? 0;
  }
  function emitBeltReaders(bp, db, byNumber, beltIndex, readerEntities, commands, bounds) {
    if (readerEntities.size === 0) return bounds;
    let b = bounds;
    for (const entityNumber of readerEntities) {
      const entry = byNumber.get(entityNumber);
      if (!entry) continue;
      const { entity, def } = entry;
      if (def.kind !== "belt" && def.kind !== "underground-belt") continue;
      const graphics = def.data?.beltReaderGraphics;
      if (!graphics?.layers?.length) continue;
      const slots = beltReaderSlots(entity, def, beltIndex, readerEntities);
      const layers = [...graphics.layers].sort(
        (a, b2) => beltReaderLayerOrder(a.layer) - beltReaderLayerOrder(b2.layer)
      );
      let sub = 10;
      for (const slot of slots) {
        for (const layer of layers) {
          const variant = layer.variants[slot.band]?.[slot.frame];
          if (!variant) continue;
          const frame = db.frames[variant.frame];
          if (!frame) continue;
          const dest = spriteDest2(entity.position.x, entity.position.y, frame, variant, slot.shift);
          const isShadow = variant.drawAsShadow === true;
          const cmd = {
            kind: "sprite",
            layer: isShadow ? RENDER_LAYERS.shadow : paintBeltReaderLayer(layer.layer),
            sortY: 0,
            sortX: 0,
            entity: entity.entity_number,
            sub: sub++,
            frame: variant.frame,
            x: dest.x,
            y: dest.y,
            w: dest.w,
            h: dest.h
          };
          if (variant.tint) cmd.tint = variant.tint;
          if (isShadow) cmd.shadow = true;
          if (Boolean(variant.flipX) !== Boolean(slot.flipX)) cmd.flipX = true;
          if (Boolean(variant.flipY) !== Boolean(slot.flipY)) cmd.flipY = true;
          if (variant.rotation) cmd.rotation = variant.rotation;
          commands.push(cmd);
          b = includeCmdBounds(b, cmd, db.frames);
        }
      }
    }
    return b;
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/circuit-connectors.ts
  function wiredEntityNumbers(bp) {
    const out = /* @__PURE__ */ new Set();
    for (const w of bp.wires ?? []) {
      if (!Array.isArray(w) || w.length < 4) continue;
      out.add(w[0]);
      out.add(w[2]);
    }
    return out;
  }
  function combinatorDisplayKey(entity, def) {
    const behavior = entity.control_behavior;
    if (!behavior) return void 0;
    if (def.protoType === "arithmetic-combinator") {
      const conditions = behavior.arithmetic_conditions;
      return typeof conditions?.operation === "string" ? conditions.operation : void 0;
    }
    if (def.protoType === "decider-combinator") {
      const conditions = behavior.decider_conditions;
      const nested = conditions?.conditions?.[0]?.comparator;
      const flat = conditions?.comparator;
      const comparator = typeof nested === "string" ? nested : typeof flat === "string" ? flat : void 0;
      if (typeof comparator !== "string") return void 0;
      return { "!=": "≠", "<=": "≤", ">=": "≥" }[comparator] ?? comparator;
    }
    if (def.protoType === "selector-combinator") {
      if (behavior.operation === "select") return behavior.select_max === false ? "min" : "max";
      return typeof behavior.operation === "string" ? behavior.operation : void 0;
    }
    return void 0;
  }
  function emitCombinatorDisplay(entity, def, db, commands, bounds) {
    const key = combinatorDisplayKey(entity, def);
    const graphics = def.data?.combinatorGraphics;
    const variants = key ? graphics?.symbols?.[key] : void 0;
    if (!variants) return bounds;
    const variant = variants[dir16ToIndex(entity.direction ?? 0, "direction4")] ?? variants[0];
    if (!variant) return bounds;
    const frame = db.frames[variant.frame];
    if (!frame) return bounds;
    const dest = spriteDest2(entity.position.x, entity.position.y, frame, variant);
    const cmd = {
      kind: "sprite",
      layer: RENDER_LAYERS["higher-object-above"],
      sortY: entity.position.y + def.collisionBox[1][1],
      sortX: entity.position.x,
      entity: entity.entity_number,
      sub: 90,
      frame: variant.frame,
      x: dest.x,
      y: dest.y,
      w: dest.w,
      h: dest.h
    };
    commands.push(cmd);
    return includeCmdBounds(bounds, cmd, db.frames);
  }
  var CCM_DRAW_ORDER = [
    "connector_shadow",
    "connector_main",
    "wire_pins_shadow",
    "wire_pins",
    "led_blue_off"
  ];
  function connectorDirIndex(entity, def, graphics, poleDirs) {
    const direction = def.protoType === "electric-pole" ? poleDirs.get(entity.entity_number) ?? entity.direction ?? 0 : entity.direction ?? 0;
    const indexing = graphics.indexing ?? "direction4";
    return dir16ToIndex(direction, indexing === "single" ? "direction4" : indexing);
  }
  function emitCircuitConnectors(bp, db, byNumber, poleDirs, commands, bounds) {
    const wired = wiredEntityNumbers(bp);
    if (wired.size === 0) return bounds;
    let b = bounds;
    for (const entityNumber of wired) {
      const entry = byNumber.get(entityNumber);
      if (!entry) continue;
      const { entity, def } = entry;
      const graphics = def.data?.wireConnectorGraphics;
      if (!graphics?.layers) continue;
      const index = connectorDirIndex(entity, def, graphics, poleDirs);
      const sortYObject = entity.position.y + def.collisionBox[1][1];
      const sortXObject = entity.position.x;
      let sub = 100;
      for (const key of CCM_DRAW_ORDER) {
        if (def.protoType === "logistic-container" && key !== "wire_pins" && key !== "wire_pins_shadow") {
          continue;
        }
        const variants = graphics.layers[key];
        if (!variants) continue;
        const variant = variants[index] ?? variants[0];
        if (!variant) continue;
        const frame = db.frames[variant.frame];
        if (!frame) continue;
        const dest = spriteDest2(entity.position.x, entity.position.y, frame, variant);
        const isShadow = key.endsWith("_shadow") || variant.drawAsShadow === true;
        const cmd = {
          kind: "sprite",
          layer: isShadow ? RENDER_LAYERS.shadow : RENDER_LAYERS["higher-object-above"],
          sortY: isShadow ? 0 : sortYObject,
          sortX: isShadow ? 0 : sortXObject,
          entity: entity.entity_number,
          sub: sub++,
          frame: variant.frame,
          x: dest.x,
          y: dest.y,
          w: dest.w,
          h: dest.h
        };
        if (variant.tint) cmd.tint = variant.tint;
        if (isShadow) cmd.shadow = true;
        if (variant.flipX) cmd.flipX = true;
        if (variant.flipY) cmd.flipY = true;
        if (variant.rotation) cmd.rotation = variant.rotation;
        commands.push(cmd);
        b = includeCmdBounds(b, cmd, db.frames);
      }
    }
    return b;
  }
  function emitBeltCircuitConnectors(bp, db, byNumber, beltVariations, commands, bounds) {
    const wired = wiredEntityNumbers(bp);
    if (wired.size === 0) return bounds;
    let b = bounds;
    const layer = RENDER_LAYERS["transport-belt-circuit-connector"];
    for (const entityNumber of wired) {
      const entry = byNumber.get(entityNumber);
      if (!entry || entry.def.kind !== "belt") continue;
      const { entity, def } = entry;
      const graphics = def.data?.beltConnectorGraphics;
      if (!graphics?.layers) continue;
      const variation = beltVariations.get(entityNumber) ?? 0;
      const connectorFrame = beltCircuitConnectorFrame(entity);
      let sub = 50;
      const outputOn = isBeltCircuitOutputEnabled(entity);
      const inputOn = isBeltCircuitInputEnabled(entity);
      const pushVariant = (variant) => {
        if (!variant) return;
        const frame = db.frames[variant.frame];
        if (!frame) return;
        const dest = spriteDest2(entity.position.x, entity.position.y, frame, variant);
        const isShadow = variant.drawAsShadow === true;
        const cmd = {
          kind: "sprite",
          layer,
          sortY: 0,
          sortX: 0,
          entity: entity.entity_number,
          sub: sub++,
          frame: variant.frame,
          x: dest.x,
          y: dest.y,
          w: dest.w,
          h: dest.h
        };
        if (variant.tint) cmd.tint = variant.tint;
        if (isShadow) cmd.shadow = true;
        if (variant.flipX) cmd.flipX = true;
        if (variant.flipY) cmd.flipY = true;
        if (variant.rotation) cmd.rotation = variant.rotation;
        commands.push(cmd);
        b = includeCmdBounds(b, cmd, db.frames);
      };
      const shadowRow = graphics.layers.frame_shadow?.[variation];
      pushVariant(shadowRow?.[connectorFrame] ?? shadowRow?.[0]);
      const backPatch = graphics.layers.frame_back_patch;
      if (backPatch) {
        pushVariant(backPatch[beltConnectorBackPatchIndex(variation)] ?? backPatch[0]);
      }
      const mainRow = graphics.layers.frame_main?.[variation];
      pushVariant(mainRow?.[connectorFrame] ?? mainRow?.[0]);
      const hRow = graphics.layers.wire_horizontal?.[variation];
      const vRow = graphics.layers.wire_vertical?.[variation];
      pushVariant(hRow?.[connectorFrame] ?? hRow?.[0]);
      pushVariant(vRow?.[connectorFrame] ?? vRow?.[0]);
      const ledKeys = [];
      if (outputOn) ledKeys.push("led_red", "led_green");
      if (inputOn) ledKeys.push("led_blue");
      for (const ledKey of ledKeys) {
        const leds = graphics.layers[ledKey];
        if (!leds) continue;
        pushVariant(leds[variation] ?? leds[0]);
      }
    }
    return b;
  }
  function buildBeltConnectorVariations(bp, byNumber, beltIndex) {
    const out = /* @__PURE__ */ new Map();
    for (const entityNumber of wiredEntityNumbers(bp)) {
      const entry = byNumber.get(entityNumber);
      if (!entry || entry.def.kind !== "belt") continue;
      out.set(entityNumber, beltCircuitConnectorVariation(entry.entity, beltIndex));
    }
    return out;
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/pipe-covers.ts
  function tileKey2(x, y) {
    return `${Math.round(x * 1e3) / 1e3},${Math.round(y * 1e3) / 1e3}`;
  }
  function buildEntityGrid(entities) {
    const grid = /* @__PURE__ */ new Map();
    for (const e of entities) {
      const key = tileKey2(e.position.x, e.position.y);
      const list = grid.get(key);
      if (list) list.push(e);
      else grid.set(key, [e]);
    }
    return grid;
  }
  function coverDirIndex(ox, oy) {
    if (Math.abs(ox) >= Math.abs(oy)) return ox > 0 ? 1 : 3;
    return oy > 0 ? 2 : 0;
  }
  function pipePictureDirIndex(facing) {
    return Math.floor(facing / 4) % 4;
  }
  function snapCardinalFacing(n, ox, oy) {
    if (n === 0 || n === 4 || n === 8 || n === 12) return n;
    if (Math.abs(ox) >= Math.abs(oy)) return ox > 0 ? 4 : 12;
    return oy > 0 ? 8 : 0;
  }
  function fluidPortOccupied(grid, db, pipeX, pipeY) {
    const neighbors = grid.get(tileKey2(pipeX, pipeY));
    if (!neighbors) return false;
    for (const n of neighbors) {
      const nd = db.entities[n.name];
      if (!nd) continue;
      if (nd.kind === "pipe") return true;
      if (nd.protoType === "pipe-to-ground" || n.name === "pipe-to-ground") return true;
      if (!nd.data?.fluidConnections) continue;
      for (const [ox, oy] of activeFluidOffsets(n, nd, db)) {
        if (Math.abs(n.position.x + ox - pipeX) < 0.01 && Math.abs(n.position.y + oy - pipeY) < 0.01) {
          return true;
        }
      }
    }
    return false;
  }
  function pushPipeCoverSprite(commands, bounds, entity, frame, variant, cx, cy, sortY, sortX, sub) {
    const dest = spriteDest2(cx, cy, frame, variant);
    const layerName = variant.drawAsShadow ? "shadow" : "object";
    const cmd = {
      kind: "sprite",
      layer: RENDER_LAYERS[layerName],
      sortY: variant.drawAsShadow ? 0 : sortY,
      sortX: variant.drawAsShadow ? 0 : sortX,
      entity: entity.entity_number,
      sub,
      frame: variant.frame,
      x: dest.x,
      y: dest.y,
      w: dest.w,
      h: dest.h
    };
    if (variant.drawAsShadow) cmd.shadow = true;
    commands.push(cmd);
    return includeCmdBounds(bounds, cmd, void 0, frame);
  }
  function emitPipeCovers(bp, db, byNumber, commands, bounds) {
    const grid = buildEntityGrid(bp.entities ?? []);
    let b = bounds;
    for (const { entity, def } of byNumber.values()) {
      if (def.kind === "pipe" || def.protoType === "pipe-to-ground") continue;
      const pc = def.data?.pipeCovers;
      if (!pc?.covers || !def.data?.fluidConnections) continue;
      const alwaysDraw = alwaysDrawPipeCovers(def);
      for (const [ox, oy] of activeFluidOffsets(entity, def, db)) {
        const pipeX = entity.position.x + ox;
        const pipeY = entity.position.y + oy;
        if (!alwaysDraw && fluidPortOccupied(grid, db, pipeX, pipeY)) continue;
        const di = coverDirIndex(ox, oy);
        const cover = pc.covers[di];
        if (!cover) continue;
        const sortY = pipeY + 0.5;
        const sortX = pipeX;
        const shadow = pc.shadows?.[di];
        if (shadow) {
          const sf = db.frames[shadow.frame];
          if (sf) {
            b = pushPipeCoverSprite(commands, b, entity, sf, shadow, pipeX, pipeY, sortY, sortX, 80);
          }
        }
        const cf = db.frames[cover.frame];
        if (cf) {
          b = pushPipeCoverSprite(commands, b, entity, cf, cover, pipeX, pipeY, sortY, sortX, 81);
        }
      }
    }
    return b;
  }
  function alwaysDrawPipeCovers(def) {
    if (def.data?.alwaysDrawPipeCovers === true) return true;
    if (def.data?.alwaysDrawPipeCovers === false) return false;
    return !def.data?.pipePictures?.some((p) => p != null);
  }
  function emitPipePictures(_bp, db, byNumber, commands, bounds) {
    let b = bounds;
    for (const { entity, def } of byNumber.values()) {
      if (def.kind === "pipe" || def.protoType === "pipe-to-ground") continue;
      const pictures = def.data?.pipePictures;
      if (!pictures || !def.data?.fluidConnections) continue;
      const sortY = entity.position.y + def.collisionBox[1][1];
      const sortX = entity.position.x;
      const dirKey = String(cardinalDirection(entity.direction ?? 0));
      const facings = def.data.fluidConnectionFacings?.[dirKey];
      for (const { index, offset } of activeFluidOffsetEntries(entity, def, db)) {
        const pc = pictures[index];
        if (!pc?.covers) continue;
        const facing = snapCardinalFacing(facings?.[index], offset[0], offset[1]);
        const di = pipePictureDirIndex(facing);
        const picture = pc.covers[di];
        if (!picture) continue;
        const cx = entity.position.x + offset[0];
        const cy = entity.position.y + offset[1];
        const shadow = pc.shadows?.[di];
        if (shadow) {
          const sf = db.frames[shadow.frame];
          if (sf) {
            b = pushPipeCoverSprite(commands, b, entity, sf, shadow, cx, cy, sortY, sortX, 70);
          }
        }
        const pf = db.frames[picture.frame];
        if (pf) {
          b = pushPipeCoverSprite(commands, b, entity, pf, picture, cx, cy, sortY, sortX, 71);
        }
      }
    }
    return b;
  }

  // tools/vendor/fpsr/packages/renderer/src/snap-grid.ts
  function snapGridRect(bp) {
    const snap = bp["snap-to-grid"];
    if (!snap || !isPositiveFinite(snap.x) || !isPositiveFinite(snap.y)) return null;
    return { x: 0, y: 0, w: snap.x, h: snap.y };
  }
  function isPositiveFinite(n) {
    return Number.isFinite(n) && n > 0;
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/snap-grid.ts
  function emitSnapGrid(bp, commands, bounds) {
    const rect = snapGridRect(bp);
    if (!rect) return bounds;
    const cmd = {
      kind: "snap-grid",
      layer: RENDER_LAYERS["selection-box"],
      sortY: 0,
      sortX: 0,
      entity: 0,
      sub: 0,
      x: rect.x,
      y: rect.y,
      w: rect.w,
      h: rect.h
    };
    commands.push(cmd);
    return includeCmdBounds(bounds, cmd);
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/tiles.ts
  function tileVariantHash(x, y) {
    let h = Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) | 0;
    h = Math.imul(h ^ h >>> 13, 1274126177);
    return (h ^ h >>> 16) >>> 0;
  }
  function tileMod(n, m) {
    return (n % m + m) % m;
  }
  function materialVariantOrigin(variantIdx, material) {
    const patchPxW = material.patchW * material.tilePx;
    const patchPxH = material.patchH * material.tilePx;
    const lineLength = material.lineLength ?? 0;
    const sheetX = material.sheetX ?? 0;
    const sheetY = material.sheetY ?? 0;
    if (lineLength > 0) {
      return {
        x: sheetX + variantIdx % lineLength * patchPxW,
        y: sheetY + Math.floor(variantIdx / lineLength) * patchPxH
      };
    }
    return { x: sheetX + variantIdx * patchPxW, y: sheetY };
  }
  function planMaterialTileSprite(tx, ty, material, layer, frames) {
    const { patchW, patchH, tilePx, count } = material;
    const bx = Math.floor(tx / patchW) * patchW;
    const by = Math.floor(ty / patchH) * patchH;
    const frameId = material.sheet;
    const frame = frames[frameId];
    if (!frame) return null;
    const variantIdx = tileVariantHash(bx, by) % count;
    const patchOrigin = materialVariantOrigin(variantIdx, material);
    const lx = tileMod(tx, patchW);
    const ly = tileMod(ty, patchH);
    return {
      kind: "sprite",
      layer,
      sortY: 0,
      sortX: 0,
      entity: 0,
      sub: 0,
      frame: frameId,
      x: tx,
      y: ty,
      w: 1,
      h: 1,
      src: {
        x: patchOrigin.x + lx * tilePx,
        y: patchOrigin.y + ly * tilePx,
        w: tilePx,
        h: tilePx
      }
    };
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/unsupported.ts
  var UNSUPPORTED_ENTITY_ICON_KEY = "utility/unsupported-entity";
  var UNSUPPORTED_ENTITY_BOX = [
    [-0.5, -0.5],
    [0.5, 0.5]
  ];
  var UNSUPPORTED_ENTITY_COLOR = [1, 0.55, 0, 1];
  var UNSUPPORTED_ENTITY_MARKER_SCALE = 0.5;
  function unsupportedEntityRect(entity) {
    const [[x1, y1], [x2, y2]] = UNSUPPORTED_ENTITY_BOX;
    return {
      kind: "rect",
      layer: RENDER_LAYERS.object,
      sortY: entity.position.y + y2,
      sortX: entity.position.x,
      entity: entity.entity_number,
      sub: 0,
      x: entity.position.x + x1,
      y: entity.position.y + y1,
      w: x2 - x1,
      h: y2 - y1,
      color: UNSUPPORTED_ENTITY_COLOR
    };
  }
  function unsupportedEntityCommand(entity, db) {
    const frameId = db.icons[UNSUPPORTED_ENTITY_ICON_KEY];
    if (frameId != null) {
      const frame = db.frames[frameId];
      if (frame) {
        const variant = {
          frame: frameId,
          scale: UNSUPPORTED_ENTITY_MARKER_SCALE,
          shift: [0, 0]
        };
        const [, [, y2]] = UNSUPPORTED_ENTITY_BOX;
        const dest = spriteDest2(entity.position.x, entity.position.y, frame, variant);
        return {
          kind: "sprite",
          layer: RENDER_LAYERS.object,
          sortY: entity.position.y + y2,
          sortX: entity.position.x,
          entity: entity.entity_number,
          sub: 0,
          frame: frameId,
          x: dest.x,
          y: dest.y,
          w: dest.w,
          h: dest.h
        };
      }
    }
    return unsupportedEntityRect(entity);
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/wires.ts
  function isDirection4AnchorMap(anchors) {
    const keys = Object.keys(anchors);
    return keys.length > 0 && keys.every((k) => k === "0" || k === "1" || k === "2" || k === "3");
  }
  function wireAnchorDirIndex(direction, anchors) {
    if (!anchors) return "0";
    const d = ((direction ?? 0) % 16 + 16) % 16;
    if (anchors[String(d)]) return String(d);
    const d4 = String(Math.floor(d / 4) % 4);
    if (isDirection4AnchorMap(anchors) && anchors[d4]) return d4;
    const d8 = String(dir16ToIndex(d, "direction8"));
    if (anchors[d8]) return d8;
    if (anchors[d4]) return d4;
    if (anchors["0"]) return "0";
    return Object.keys(anchors)[0] ?? "0";
  }
  function wireEndpoint(entity, def, color, connectorId, direction, beltVariation) {
    const useOutput = connectorId === WIRE_CONNECTOR_ID.combinator_output_red || connectorId === WIRE_CONNECTOR_ID.combinator_output_green || connectorId === WIRE_CONNECTOR_ID.power_switch_right_copper;
    const primary = useOutput ? def.data?.wireAnchorsOutput : def.data?.wireAnchors;
    const fallback = def.data?.wireAnchors;
    const anchors = primary && Object.keys(primary).length > 0 ? primary : fallback;
    const key = def.kind === "belt" && beltVariation !== void 0 ? String(beltVariation) : wireAnchorDirIndex(direction ?? entity.direction, anchors);
    const set = anchors?.[key] ?? (def.kind === "belt" ? anchors?.["0"] : void 0);
    const offset = set?.[color] ?? set?.copper ?? [0, -0.5];
    return [entity.position.x + offset[0], entity.position.y + offset[1]];
  }
  function emitWires(bp, byNumber, poleDirs, beltVariations, commands, bounds) {
    const wires = bp.wires;
    if (!wires?.length) return bounds;
    let b = bounds;
    let sub = 0;
    for (const w of wires) {
      if (!Array.isArray(w) || w.length < 4) continue;
      const [srcNum, srcConn, dstNum, dstConn] = w;
      const src = byNumber.get(srcNum);
      const dst = byNumber.get(dstNum);
      if (!src || !dst) continue;
      const color = wireConnectorColor(srcConn) ?? wireConnectorColor(dstConn);
      if (!color) continue;
      const srcDir = src.def.protoType === "electric-pole" ? poleDirs.get(srcNum) : src.entity.direction;
      const dstDir = dst.def.protoType === "electric-pole" ? poleDirs.get(dstNum) : dst.entity.direction;
      const [x1, y1] = wireEndpoint(
        src.entity,
        src.def,
        color,
        srcConn,
        srcDir,
        beltVariations.get(srcNum)
      );
      const [x2, y2] = wireEndpoint(
        dst.entity,
        dst.def,
        color,
        dstConn,
        dstDir,
        beltVariations.get(dstNum)
      );
      const cmd = {
        kind: "wire",
        layer: RENDER_LAYERS.wires,
        sortY: 0,
        sortX: 0,
        entity: srcNum,
        sub: sub++,
        wire: color,
        x1,
        y1,
        x2,
        y2
      };
      commands.push(cmd);
      b = includeCmdBounds(b, cmd);
    }
    return b;
  }
  function emitTrainChains(bp, byNumber, commands, bounds) {
    const geom = buildTrainChainGeometry(bp, byNumber);
    if (!geom) return bounds;
    const cmd = {
      kind: "train-chain",
      layer: RENDER_LAYERS["selection-box"],
      sortY: 0,
      sortX: 0,
      entity: 0,
      sub: 0,
      segments: geom.segments,
      joints: geom.joints
    };
    commands.push(cmd);
    return includeCmdBounds(bounds, cmd);
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/index.ts
  function normalizeEntityColor(color) {
    let r = color.r;
    let g = color.g;
    let b = color.b;
    let a = color.a ?? 1;
    if (r > 1 || g > 1 || b > 1 || a > 1) {
      r /= 255;
      g /= 255;
      b /= 255;
      if (a > 1) a /= 255;
    }
    return [r, g, b, a];
  }
  function isRuntimeColorMaskGroup(def, groupIndex) {
    const maskIndex = def.data?.colorMaskGroupIndex;
    const maskIndices = def.data?.colorMaskGroupIndices;
    return typeof maskIndex === "number" && groupIndex === maskIndex || Array.isArray(maskIndices) && maskIndices.includes(groupIndex);
  }
  function runtimeColorMaskTint(entity, def, groupIndex) {
    if (!isRuntimeColorMaskGroup(def, groupIndex)) return void 0;
    const fromEntity = entity.color;
    if (fromEntity) return normalizeEntityColor(fromEntity);
    const fallback = def.data?.defaultColor;
    if (Array.isArray(fallback) && fallback.length >= 3) {
      return [
        Number(fallback[0]) || 0,
        Number(fallback[1]) || 0,
        Number(fallback[2]) || 0,
        fallback[3] == null ? 1 : Number(fallback[3]) || 0
      ];
    }
    if (def.kind === "train") return [242 / 255, 0, 0, 1];
    return void 0;
  }
  var OBJECT_SORT_LAYERS = /* @__PURE__ */ new Set([
    "lower-object",
    "lower-object-above-shadow",
    "lower-object-overlay",
    "object-under",
    "object",
    "higher-object-under",
    "higher-object-above",
    "train-stop-top",
    "elevated-object"
  ]);
  function legacyRailBedAxis(protoType, cmd) {
    if (cmd.w === cmd.h) return "both";
    if (protoType === "legacy-curved-rail") return cmd.w > cmd.h ? "x" : "y";
    return cmd.w > cmd.h ? "y" : "x";
  }
  function markLegacyRailBedSeams(candidates) {
    const epsilon = 1e-6;
    const spansJoin = (a0, a1, b0, b1) => {
      const overlap = Math.min(a1, b1) - Math.max(a0, b0);
      return overlap >= Math.min(a1 - a0, b1 - b0) - epsilon;
    };
    const allows = (candidate, axis) => candidate.axis === axis || candidate.axis === "both";
    const mark = (cmd, edge) => {
      cmd.seamBleed ?? (cmd.seamBleed = {});
      cmd.seamBleed[edge] = true;
    };
    const top = /* @__PURE__ */ new Map();
    const right = /* @__PURE__ */ new Map();
    const bottom = /* @__PURE__ */ new Map();
    const left = /* @__PURE__ */ new Map();
    const index = (map, edge, spanStart, spanEnd, candidate) => {
      const edgeKey = Math.round(edge / epsilon);
      const firstCell = Math.floor(spanStart + epsilon);
      const lastCell = Math.ceil(spanEnd - epsilon);
      for (let cell = firstCell; cell < lastCell; cell++) {
        const key = `${edgeKey}:${cell}`;
        const bucket = map.get(key);
        if (bucket) bucket.push(candidate);
        else map.set(key, [candidate]);
      }
    };
    for (const candidate of candidates) {
      const { cmd } = candidate;
      if (allows(candidate, "y")) {
        index(top, cmd.y, cmd.x, cmd.x + cmd.w, candidate);
        index(bottom, cmd.y + cmd.h, cmd.x, cmd.x + cmd.w, candidate);
      }
      if (allows(candidate, "x")) {
        index(left, cmd.x, cmd.y, cmd.y + cmd.h, candidate);
        index(right, cmd.x + cmd.w, cmd.y, cmd.y + cmd.h, candidate);
      }
    }
    const connect = (trailing, leading, spanAxis, trailingEdge, leadingEdge) => {
      for (const [key, trailingCandidates] of trailing) {
        const leadingCandidates = leading.get(key);
        if (!leadingCandidates) continue;
        for (const a of trailingCandidates) {
          for (const b of leadingCandidates) {
            if (a === b) continue;
            const overlapsSpan = spanAxis === "x" ? spansJoin(a.cmd.x, a.cmd.x + a.cmd.w, b.cmd.x, b.cmd.x + b.cmd.w) : spansJoin(a.cmd.y, a.cmd.y + a.cmd.h, b.cmd.y, b.cmd.y + b.cmd.h);
            if (!overlapsSpan) continue;
            mark(a.cmd, trailingEdge);
            mark(b.cmd, leadingEdge);
          }
        }
      }
    };
    connect(bottom, top, "x", "bottom", "top");
    connect(right, left, "y", "right", "left");
  }
  function planDrawList(bp, db, opts) {
    return planDrawListWithOptions(bp, db, opts).drawList;
  }
  function planDrawListWithOptions(bp, db, opts) {
    return planDrawListInternal(bp, db, opts);
  }
  function planDrawListInternal(bp, db, opts) {
    const altMode = opts?.altMode ?? true;
    const beltEndings = opts?.beltEndings ?? true;
    const profile = opts?.profileOut ?? (opts?.profile ? {
      migrateMs: 0,
      resolveMs: 0,
      tilesMs: 0,
      entitiesMs: 0,
      overlaysMs: 0,
      sortMs: 0,
      totalMs: 0
    } : void 0);
    const tTotal = profile ? nowMs() : 0;
    let t = profile ? nowMs() : 0;
    bp = migrateTo2x(bp);
    if (profile) profile.migrateMs = nowMs() - t;
    const commands = [];
    let bounds = null;
    t = profile ? nowMs() : 0;
    for (const tile of bp.tiles ?? []) {
      const def = db.tiles[tile.name];
      if (!def) continue;
      const layer = RENDER_LAYERS[def.layer];
      const tx = tile.position.x;
      const ty = tile.position.y;
      if (def.material && def.material.count > 0) {
        const cmd = planMaterialTileSprite(tx, ty, def.material, layer, db.frames);
        if (!cmd) continue;
        commands.push(cmd);
        bounds = includeCmdBounds(bounds, cmd, db.frames);
      } else if (def.frames && def.frames.length > 0) {
        const frameId = def.frames[tileVariantHash(tx, ty) % def.frames.length];
        if (frameId === void 0) continue;
        const frame = db.frames[frameId];
        if (!frame) continue;
        const cmd = {
          kind: "sprite",
          layer,
          sortY: 0,
          sortX: 0,
          entity: 0,
          sub: 0,
          frame: frameId,
          x: tx,
          y: ty,
          w: 1,
          h: 1
        };
        commands.push(cmd);
        bounds = includeCmdBounds(bounds, cmd, db.frames);
      } else {
        const cmd = {
          kind: "rect",
          layer,
          sortY: 0,
          sortX: 0,
          entity: 0,
          sub: 0,
          x: tx,
          y: ty,
          w: 1,
          h: 1,
          color: def.color
        };
        commands.push(cmd);
        bounds = includeCmdBounds(bounds, cmd);
      }
    }
    if (profile) profile.tilesMs = nowMs() - t;
    t = profile ? nowMs() : 0;
    for (const entity of bp.entities ?? []) {
      if (db.entities[entity.name]) continue;
      const cmd = unsupportedEntityCommand(entity, db);
      commands.push(cmd);
      bounds = includeCmdBounds(bounds, cmd, db.frames);
    }
    const tResolve = profile ? nowMs() : 0;
    const resolveContext = createResolveContext(bp, db);
    const resolved = resolveWithContext(resolveContext, void 0, { beltEndings });
    if (profile) profile.resolveMs = nowMs() - tResolve;
    const byNumber = /* @__PURE__ */ new Map();
    const legacyRailBeds = [];
    for (const { entity, def, selections } of resolved) {
      byNumber.set(entity.entity_number, { entity, def });
      const sortYObject = def.kind === "train" ? entity.position.y : entity.position.y + def.collisionBox[1][1];
      const sortXObject = entity.position.x;
      for (const sel of selections) {
        const group = def.graphics[sel.group];
        if (!group) continue;
        if (def.kind === "vehicle" && isRuntimeColorMaskGroup(def, sel.group) && !entity.color && !Array.isArray(def.data?.defaultColor)) {
          continue;
        }
        const variants = group.variants[sel.variantKey] ?? group.variants.default;
        if (!variants) continue;
        const variant = variants[sel.index];
        if (!variant) continue;
        const frame = db.frames[variant.frame];
        if (!frame) continue;
        const dest = spriteDest2(entity.position.x, entity.position.y, frame, variant, sel.shift);
        const layerName = def.kind === "splitter" && group.layer === "object-under" ? "object" : group.layer;
        const isObjectLayer = OBJECT_SORT_LAYERS.has(layerName);
        const cmd = {
          kind: "sprite",
          layer: RENDER_LAYERS[layerName],
          sortY: isObjectLayer ? sortYObject : 0,
          sortX: isObjectLayer ? sortXObject : 0,
          entity: entity.entity_number,
          sub: sel.group,
          frame: variant.frame,
          x: dest.x,
          y: dest.y,
          w: dest.w,
          h: dest.h
        };
        if (variant.tint) cmd.tint = variant.tint;
        const maskTint = runtimeColorMaskTint(entity, def, sel.group);
        if (maskTint) cmd.tint = maskTint;
        if (variant.drawAsShadow) cmd.shadow = true;
        if (variant.flipX) cmd.flipX = true;
        if (variant.flipY) cmd.flipY = true;
        if (variant.rotation != null && variant.rotation !== 0) cmd.rotation = variant.rotation;
        if ((def.protoType === "legacy-straight-rail" || def.protoType === "legacy-curved-rail") && layerName === "rail-stone-path-lower") {
          legacyRailBeds.push({ cmd, axis: legacyRailBedAxis(def.protoType, cmd) });
        }
        if ((def.kind === "underground-belt" || def.kind === "loader") && group.layer === "transport-belt" && sel.variantKey !== "start" && sel.variantKey !== "end") {
          const facing = cardinalDirection(entity.direction ?? 0);
          const openDir = entity.type === "output" ? facing : (facing + 8) % 16;
          cmd.clip = undergroundBeltUnderlayClip(dest, openDir);
        }
        commands.push(cmd);
        bounds = includeCmdBounds(bounds, cmd, db.frames);
      }
      bounds = emitCombinatorDisplay(entity, def, db, commands, bounds);
      const requestPins = planRequestPinCommands(entity, def, db);
      for (const cmd of requestPins) {
        commands.push(cmd);
        bounds = includeCmdBounds(bounds, cmd, db.frames);
      }
      if (altMode) {
        for (const cmd of planAltModeCommands(entity, def, db, {
          insertCommands: requestPins
        })) {
          commands.push(cmd);
          bounds = includeCmdBounds(bounds, cmd, db.frames);
        }
      }
    }
    markLegacyRailBedSeams(legacyRailBeds);
    if (profile) {
      profile.entitiesMs = nowMs() - t - profile.resolveMs;
    }
    t = profile ? nowMs() : 0;
    const { beltIndex, poleDirs } = resolveContext;
    const beltVariations = buildBeltConnectorVariations(bp, byNumber, beltIndex);
    const readerEntities = collectBeltReaderEntities(bp, db, beltIndex);
    bounds = emitCircuitConnectors(bp, db, byNumber, poleDirs, commands, bounds);
    bounds = emitBeltReaders(bp, db, byNumber, beltIndex, readerEntities, commands, bounds);
    bounds = emitBeltCircuitConnectors(bp, db, byNumber, beltVariations, commands, bounds);
    bounds = emitPipePictures(bp, db, byNumber, commands, bounds);
    bounds = emitPipeCovers(bp, db, byNumber, commands, bounds);
    bounds = emitWires(bp, byNumber, poleDirs, beltVariations, commands, bounds);
    bounds = emitTrainChains(bp, byNumber, commands, bounds);
    bounds = emitSnapGrid(bp, commands, bounds);
    const commandsBeforeConnections = commands.length;
    emitCargoBayConnections(bp, db, resolveContext.preferPlatformGraphics, commands);
    for (let i = commandsBeforeConnections; i < commands.length; i++) {
      const cmd = commands[i];
      if (cmd) bounds = includeCmdBounds(bounds, cmd, db.frames);
    }
    if (profile) profile.overlaysMs = nowMs() - t;
    t = profile ? nowMs() : 0;
    commands.sort(compareDrawCmd);
    if (profile) {
      profile.sortMs = nowMs() - t;
      profile.totalMs = nowMs() - tTotal;
    }
    if (commands.length === 0) {
      return {
        drawList: {
          schema: 1,
          bounds: { minX: 0, minY: 0, maxX: 0, maxY: 0 },
          commands: []
        },
        profile
      };
    }
    return {
      drawList: {
        schema: 1,
        bounds: bounds ?? { minX: 0, minY: 0, maxX: 0, maxY: 0 },
        commands
      },
      profile
    };
  }

  // tools/vendor/fpsr/packages/renderer/src/blueprint-icons.ts
  var BLUEPRINT_ICON_TILE_SIZE = 64;
  var VARIANT_LAYOUT = {
    blueprint: { singleSignalPx: 48, multiSignalPx: 28, gapPx: 4 },
    book: { singleSignalPx: 24, multiSignalPx: 18, gapPx: 3 }
  };
  function packedCentersForVariant(variant) {
    const { multiSignalPx, gapPx } = VARIANT_LAYOUT[variant];
    const gridCenter = (BLUEPRINT_ICON_TILE_SIZE - multiSignalPx * 2 - gapPx) / 2 + multiSignalPx / 2;
    const gridFar = BLUEPRINT_ICON_TILE_SIZE - gridCenter;
    const near = gridCenter / BLUEPRINT_ICON_TILE_SIZE;
    const far = gridFar / BLUEPRINT_ICON_TILE_SIZE;
    return {
      1: [{ x: 0.5, y: 0.5 }],
      2: [
        { x: near, y: 0.5 },
        { x: far, y: 0.5 }
      ],
      3: [
        { x: near, y: near },
        { x: far, y: near },
        { x: near, y: far }
      ],
      4: [
        { x: near, y: near },
        { x: far, y: near },
        { x: near, y: far },
        { x: far, y: far }
      ]
    };
  }
  var PACKED_CENTERS = {
    blueprint: packedCentersForVariant("blueprint"),
    book: packedCentersForVariant("book")
  };

  // tools/vendor/fpsr/packages/renderer/src/deconstruction-planner.ts
  var DECONSTRUCTION_ENTITY_FILTER_SLOT_COUNT = 30;
  var DECONSTRUCTION_TILE_FILTER_SLOT_COUNT = 30;
  function isPlainObject(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function parseIndexedFilter(value) {
    if (!isPlainObject(value)) return void 0;
    const index = value.index;
    if (typeof index !== "number" || !Number.isInteger(index) || index < 0) return void 0;
    return { index, rest: value };
  }
  function parseEntityFilter(value) {
    const parsed = parseIndexedFilter(value);
    if (!parsed) return void 0;
    return { ...parsed.rest, index: parsed.index };
  }
  function parseTileFilter(value) {
    const parsed = parseIndexedFilter(value);
    if (!parsed) return void 0;
    return { ...parsed.rest, index: parsed.index };
  }
  function readFilterMode(value) {
    return value === 1 ? "blacklist" : "whitelist";
  }
  function readTileSelectionMode(value) {
    switch (value) {
      case 1:
        return "always";
      case 2:
        return "never";
      case 3:
        return "only";
      default:
        return "normal";
    }
  }
  function settingsOf(planner) {
    const settings = planner.settings;
    return isPlainObject(settings) ? settings : void 0;
  }
  function deconstructionEntityFilters(planner) {
    const slots = Array.from(
      { length: DECONSTRUCTION_ENTITY_FILTER_SLOT_COUNT },
      () => void 0
    );
    const settings = settingsOf(planner);
    const filters = settings?.entity_filters;
    if (!Array.isArray(filters)) return slots;
    for (const entry of filters) {
      const filter = parseEntityFilter(entry);
      if (!filter || filter.index >= DECONSTRUCTION_ENTITY_FILTER_SLOT_COUNT) continue;
      slots[filter.index] = filter;
    }
    return slots;
  }
  function deconstructionTileFilters(planner) {
    const slots = Array.from(
      { length: DECONSTRUCTION_TILE_FILTER_SLOT_COUNT },
      () => void 0
    );
    const settings = settingsOf(planner);
    const filters = settings?.tile_filters;
    if (!Array.isArray(filters)) return slots;
    for (const entry of filters) {
      const filter = parseTileFilter(entry);
      if (!filter || filter.index >= DECONSTRUCTION_TILE_FILTER_SLOT_COUNT) continue;
      slots[filter.index] = filter;
    }
    return slots;
  }
  function deconstructionEntityFilterMode(planner) {
    return readFilterMode(settingsOf(planner)?.entity_filter_mode);
  }
  function deconstructionTileFilterMode(planner) {
    return readFilterMode(settingsOf(planner)?.tile_filter_mode);
  }
  function deconstructionTileSelectionMode(planner) {
    return readTileSelectionMode(settingsOf(planner)?.tile_selection_mode);
  }
  function deconstructionTreesAndRocksOnly(planner) {
    return settingsOf(planner)?.trees_and_rocks_only === true;
  }
  function formatDeconstructionFilterMode(mode) {
    return mode === "blacklist" ? "Blacklist" : "Whitelist";
  }
  function formatDeconstructionTileSelectionMode(mode) {
    switch (mode) {
      case "always":
        return "Always";
      case "never":
        return "Never";
      case "only":
        return "Only";
      default:
        return "Normal";
    }
  }

  // tools/vendor/fpsr/packages/renderer/src/icon-resolve.ts
  function resolveIconFrameId(db, iconKey) {
    const direct = db.icons[iconKey];
    if (direct !== void 0) return direct;
    if (!iconKey.startsWith("item/")) return void 0;
    const tileName = iconKey.slice("item/".length);
    const placingItem = db.tiles[tileName]?.item;
    if (!placingItem) return void 0;
    return db.icons[`item/${placingItem}`];
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/deconstruction-planner.ts
  var DECONSTRUCTION_PLANNER_COLUMNS = 12;
  var TREES_AND_ROCKS_ICON_KEY = "entity/tree-01";
  var OUTER_PAD = 1;
  var ICON_GAP = 0;
  var ICON_SIZE = 1;
  var HEADER_ROWS = 1;
  var SECTION_GAP = 1;
  var TEXT_SIZE = 0.35;
  var TEXT_COLOR = [1, 1, 1, 0.92];
  var HEADER_ENTITY = 0;
  function tileCenter(tileX, tileY) {
    return { x: tileX + 0.5, y: tileY + 0.5 };
  }
  function occupiedRows(slotCount, lastIndex) {
    if (lastIndex < 0) return 0;
    return Math.floor(lastIndex / slotCount) + 1;
  }
  function lastOccupiedIndex(slots) {
    let maxIndex = -1;
    for (let index = 0; index < slots.length; index++) {
      if (slots[index]?.name) maxIndex = index;
    }
    return maxIndex;
  }
  function gridWidth() {
    return OUTER_PAD + DECONSTRUCTION_PLANNER_COLUMNS * ICON_SIZE + (DECONSTRUCTION_PLANNER_COLUMNS - 1) * ICON_GAP + OUTER_PAD;
  }
  function sectionBodyHeight(rows) {
    if (rows === 0) return 0;
    return rows * ICON_SIZE + (rows - 1) * ICON_GAP;
  }
  function textCommand(text, x, y, entity, sub) {
    return {
      kind: "text",
      layer: RENDER_LAYERS.icons,
      sortY: y,
      sortX: x,
      entity,
      sub,
      text,
      x,
      y,
      size: TEXT_SIZE,
      color: TEXT_COLOR,
      align: "left",
      baseline: "middle"
    };
  }
  function entityIconCommand(db, filter, x, y, entity, sub) {
    const signal = {
      name: filter.name,
      type: filter.type ?? "entity",
      ...typeof filter.quality === "string" && filter.quality !== "normal" ? { quality: filter.quality } : {}
    };
    const frame = altSignalFrame(db, signal) ?? db.icons["utility/missing-icon"];
    if (frame === void 0) return void 0;
    return {
      kind: "icon",
      layer: RENDER_LAYERS.icons,
      sortY: y,
      sortX: x,
      entity,
      sub,
      frame,
      x,
      y,
      size: ICON_SIZE
    };
  }
  function tileIconCommand(db, filter, x, y, entity, sub) {
    const frame = resolveIconFrameId(db, `tile/${filter.name}`) ?? db.icons["utility/missing-icon"];
    if (frame === void 0) return void 0;
    return {
      kind: "icon",
      layer: RENDER_LAYERS.icons,
      sortY: y,
      sortX: x,
      entity,
      sub,
      frame,
      x,
      y,
      size: ICON_SIZE
    };
  }
  function treeIconCommand(db, x, y) {
    const frame = db.icons[TREES_AND_ROCKS_ICON_KEY] ?? altSignalFrame(db, { name: "tree-01", type: "entity" }) ?? db.icons["utility/missing-icon"];
    if (frame === void 0) return void 0;
    return {
      kind: "icon",
      layer: RENDER_LAYERS.icons,
      sortY: y,
      sortX: x,
      entity: 1,
      sub: 0,
      frame,
      x,
      y,
      size: ICON_SIZE
    };
  }
  function pushIconGrid(commands, bounds, db, slots, rows, originY, kind) {
    let nextBounds = bounds;
    const colStride = ICON_SIZE + ICON_GAP;
    const rowStride = ICON_SIZE + ICON_GAP;
    const slotLimit = Math.min(slots.length, rows * DECONSTRUCTION_PLANNER_COLUMNS);
    for (let index = 0; index < slotLimit; index++) {
      const filter = slots[index];
      if (!filter?.name) continue;
      const col = index % DECONSTRUCTION_PLANNER_COLUMNS;
      const row = Math.floor(index / DECONSTRUCTION_PLANNER_COLUMNS);
      const pos = tileCenter(OUTER_PAD + col * colStride, originY + row * rowStride);
      const entity = (kind === "entity" ? 1e3 : 2e3) + index + 1;
      const cmd = kind === "entity" ? entityIconCommand(db, filter, pos.x, pos.y, entity, 0) : tileIconCommand(db, filter, pos.x, pos.y, entity, 0);
      if (!cmd) continue;
      commands.push(cmd);
      nextBounds = includeCmdBounds(nextBounds, cmd, db.frames);
    }
    return nextBounds;
  }
  function pushSection(commands, bounds, db, header, headerSub, slots, rows, cursorY, kind) {
    const headerCmd = textCommand(header, OUTER_PAD, cursorY + 0.5, HEADER_ENTITY, headerSub);
    commands.push(headerCmd);
    let nextBounds = includeCmdBounds(bounds, headerCmd);
    const gridY = cursorY + HEADER_ROWS;
    nextBounds = pushIconGrid(commands, nextBounds, db, slots, rows, gridY, kind);
    const nextY = gridY + sectionBodyHeight(rows);
    return { bounds: nextBounds, nextY };
  }
  function planDeconstructionPlannerDrawList(planner, db) {
    const treesOnly = deconstructionTreesAndRocksOnly(planner);
    const width = gridWidth();
    const commands = [];
    if (treesOnly) {
      const height2 = OUTER_PAD + ICON_SIZE + OUTER_PAD;
      let bounds2 = { minX: 0, minY: 0, maxX: width, maxY: height2 };
      const iconPos = tileCenter(OUTER_PAD, OUTER_PAD);
      const treeCmd = treeIconCommand(db, iconPos.x, iconPos.y);
      if (treeCmd) {
        commands.push(treeCmd);
        bounds2 = includeCmdBounds(bounds2, treeCmd, db.frames);
      }
      const label = textCommand(
        "Trees/rocks only",
        OUTER_PAD + ICON_SIZE + ICON_GAP,
        OUTER_PAD + 0.5,
        HEADER_ENTITY,
        0
      );
      commands.push(label);
      bounds2 = includeCmdBounds(bounds2, label);
      bounds2 = expandBounds(bounds2, 0, 0, width, height2);
      commands.sort(compareDrawCmd);
      return { schema: 1, bounds: bounds2, commands };
    }
    const entitySlots = deconstructionEntityFilters(planner);
    const tileSlots = deconstructionTileFilters(planner);
    const entityRows = occupiedRows(DECONSTRUCTION_PLANNER_COLUMNS, lastOccupiedIndex(entitySlots));
    const tileRows = occupiedRows(DECONSTRUCTION_PLANNER_COLUMNS, lastOccupiedIndex(tileSlots));
    const showEntities = entityRows > 0;
    const showTiles = tileRows > 0;
    if (!showEntities && !showTiles) {
      const height2 = OUTER_PAD * 2;
      return {
        schema: 1,
        bounds: { minX: 0, minY: 0, maxX: width, maxY: height2 },
        commands: []
      };
    }
    const entityMode = formatDeconstructionFilterMode(deconstructionEntityFilterMode(planner));
    const tileMode = formatDeconstructionFilterMode(deconstructionTileFilterMode(planner));
    const tileSelection = formatDeconstructionTileSelectionMode(
      deconstructionTileSelectionMode(planner)
    );
    let cursorY = OUTER_PAD;
    let bounds = { minX: 0, minY: 0, maxX: width, maxY: OUTER_PAD };
    if (showEntities) {
      const section = pushSection(
        commands,
        bounds,
        db,
        `Entities / ${entityMode}`,
        0,
        entitySlots,
        entityRows,
        cursorY,
        "entity"
      );
      bounds = section.bounds;
      cursorY = section.nextY;
      if (showTiles) cursorY += SECTION_GAP;
    }
    if (showTiles) {
      const section = pushSection(
        commands,
        bounds,
        db,
        `Tiles / ${tileMode} / ${tileSelection}`,
        1,
        tileSlots,
        tileRows,
        cursorY,
        "tile"
      );
      bounds = section.bounds;
      cursorY = section.nextY;
    }
    const height = cursorY + OUTER_PAD;
    bounds = expandBounds(bounds, 0, 0, width, height);
    commands.sort(compareDrawCmd);
    return { schema: 1, bounds, commands };
  }

  // tools/vendor/fpsr/packages/renderer/src/upgrade-planner.ts
  var UPGRADE_PLANNER_SLOT_COUNT = 24;
  function isPlainObject2(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function parseMapperSide(value) {
    if (!isPlainObject2(value)) return void 0;
    return value;
  }
  function parseMapper(value) {
    if (!isPlainObject2(value)) return void 0;
    const index = value.index;
    if (typeof index !== "number" || !Number.isInteger(index) || index < 0) return void 0;
    return {
      ...value,
      index,
      from: parseMapperSide(value.from),
      to: parseMapperSide(value.to)
    };
  }
  function upgradePlannerMappers(planner) {
    const slots = Array.from(
      { length: UPGRADE_PLANNER_SLOT_COUNT },
      () => void 0
    );
    const settings = planner.settings;
    if (!isPlainObject2(settings)) return slots;
    const mappers = settings.mappers;
    if (!Array.isArray(mappers)) return slots;
    for (const entry of mappers) {
      const mapper = parseMapper(entry);
      if (!mapper || mapper.index >= UPGRADE_PLANNER_SLOT_COUNT) continue;
      slots[mapper.index] = mapper;
    }
    return slots;
  }

  // tools/vendor/fpsr/packages/renderer/src/plan/upgrade-planner.ts
  var UPGRADE_PLANNER_COLUMNS = 4;
  var SLOT_TILES = 3;
  var PAIR_GAP = 1;
  var OUTER_PAD2 = 1;
  var ICON_SIZE2 = 1;
  var RIGHT_ARROW_ICON_KEY = "virtual-signal/right-arrow";
  function mapperSignal(side) {
    if (!side?.name) return void 0;
    return {
      name: side.name,
      type: side.type ?? "entity",
      ...typeof side.quality === "string" && side.quality !== "normal" ? { quality: side.quality } : {}
    };
  }
  function tileCenter2(tileX, tileY) {
    return { x: tileX + 0.5, y: tileY + 0.5 };
  }
  function occupiedRows2(slots) {
    let maxIndex = -1;
    for (let index = 0; index < slots.length; index++) {
      if (slots[index]) maxIndex = index;
    }
    if (maxIndex < 0) return 0;
    return Math.floor(maxIndex / UPGRADE_PLANNER_COLUMNS) + 1;
  }
  function gridSize(rows) {
    const cols = UPGRADE_PLANNER_COLUMNS;
    return {
      width: OUTER_PAD2 + cols * SLOT_TILES + (cols - 1) * PAIR_GAP + OUTER_PAD2,
      height: rows === 0 ? OUTER_PAD2 * 2 : OUTER_PAD2 + rows + (rows - 1) * PAIR_GAP + OUTER_PAD2
    };
  }
  function gridBounds(rows) {
    const { width, height } = gridSize(rows);
    return { minX: 0, minY: 0, maxX: width, maxY: height };
  }
  function mapperIconCommand(db, side, x, y, entity, sub) {
    const signal = mapperSignal(side);
    if (!signal) return void 0;
    const frame = altSignalFrame(db, signal) ?? db.icons["utility/missing-icon"];
    if (frame === void 0) return void 0;
    return {
      kind: "icon",
      layer: RENDER_LAYERS.icons,
      sortY: y,
      sortX: x,
      entity,
      sub,
      frame,
      x,
      y,
      size: ICON_SIZE2
    };
  }
  function arrowCommand(db, x, y, entity) {
    const frame = db.icons[RIGHT_ARROW_ICON_KEY] ?? db.icons["utility/missing-icon"];
    if (frame === void 0) return void 0;
    return {
      kind: "icon",
      layer: RENDER_LAYERS.icons,
      sortY: y,
      sortX: x,
      entity,
      sub: 1,
      frame,
      x,
      y,
      size: ICON_SIZE2
    };
  }
  function planUpgradePlannerDrawList(planner, db) {
    const slots = upgradePlannerMappers(planner);
    const rows = occupiedRows2(slots);
    const commands = [];
    let bounds = gridBounds(rows);
    const colStride = SLOT_TILES + PAIR_GAP;
    const rowStride = 1 + PAIR_GAP;
    const slotLimit = Math.min(UPGRADE_PLANNER_SLOT_COUNT, rows * UPGRADE_PLANNER_COLUMNS);
    for (let index = 0; index < slotLimit; index++) {
      const mapper = slots[index];
      if (!mapper) continue;
      const col = index % UPGRADE_PLANNER_COLUMNS;
      const row = Math.floor(index / UPGRADE_PLANNER_COLUMNS);
      const baseX = OUTER_PAD2 + col * colStride;
      const baseY = OUTER_PAD2 + row * rowStride;
      const entity = index + 1;
      const fromPos = tileCenter2(baseX, baseY);
      const fromCmd = mapperIconCommand(db, mapper.from, fromPos.x, fromPos.y, entity, 0);
      if (fromCmd) {
        commands.push(fromCmd);
        bounds = includeCmdBounds(bounds, fromCmd, db.frames);
      }
      const arrowPos = tileCenter2(baseX + 1, baseY);
      const arrowCmd = arrowCommand(db, arrowPos.x, arrowPos.y, entity);
      if (arrowCmd) {
        commands.push(arrowCmd);
        bounds = includeCmdBounds(bounds, arrowCmd, db.frames);
      }
      const toPos = tileCenter2(baseX + 2, baseY);
      const toCmd = mapperIconCommand(db, mapper.to, toPos.x, toPos.y, entity, 2);
      if (toCmd) {
        commands.push(toCmd);
        bounds = includeCmdBounds(bounds, toCmd, db.frames);
      }
    }
    if (!bounds) {
      bounds = gridBounds(rows);
    } else {
      const grid = gridBounds(rows);
      bounds = expandBounds(
        bounds,
        grid.minX,
        grid.minY,
        grid.maxX - grid.minX,
        grid.maxY - grid.minY
      );
    }
    commands.sort(compareDrawCmd);
    return { schema: 1, bounds, commands };
  }

  // tools/planner-entry.ts
  var plannerRevision = "2f7dc70f2681de530402556f757006e904e692d5";
  function nativePlan(entryJSON, dbJSON) {
    const started = Date.now();
    const entry = JSON.parse(entryJSON);
    const db = JSON.parse(dbJSON);
    const parsed = Date.now();
    let list;
    let warnings = [];
    if (entry.blueprint) {
      list = planDrawListWithOptions(entry.blueprint, db, { altMode: true }).drawList;
    } else if (entry.upgrade_planner) {
      list = planUpgradePlannerDrawList(entry.upgrade_planner, db);
    } else if (entry.deconstruction_planner) {
      list = planDeconstructionPlannerDrawList(entry.deconstruction_planner, db);
    } else {
      throw new Error("Select a blueprint or planner leaf, not a book container.");
    }
    if (list.commands.length > 25e4) throw new Error("Draw command limit exceeded.");
    const diagnostics = analyzePlan(entry.blueprint ?? {}, list, db);
    if (!Object.values(diagnostics.checks).every(Boolean)) throw new Error("Invalid planner draw-list integrity.");
    warnings = [
      ...diagnostics.entities.unsupported.map((value) => `Unsupported entity: ${value.name} (${value.count})`),
      ...diagnostics.tiles.unsupported.map((value) => `Unsupported tile: ${value.name} (${value.count})`)
    ];
    const result = JSON.stringify({
      schema: 1,
      drawList: list,
      warnings,
      commandKinds: diagnostics.drawList.byKind,
      parseMs: parsed - started,
      planningMs: Date.now() - parsed
    });
    if (result.length > 64 * 1024 * 1024) throw new Error("Draw-list transfer limit exceeded.");
    return result;
  }
  function selfTest() {
    const db = { frames: [], icons: {} };
    const planner = { settings: {} };
    const upgrade = planUpgradePlannerDrawList(planner, db);
    const deconstruction = planDeconstructionPlannerDrawList(planner, db);
    return {
      schema: 1,
      plannerRevision,
      upgradeCommands: upgrade.commands.length,
      deconstructionCommands: deconstruction.commands.length,
      finiteBounds: [upgrade, deconstruction].every((list) => Object.values(list.bounds).every(Number.isFinite)),
      nodeAvailable: typeof globalThis.process !== "undefined" || typeof globalThis.require !== "undefined",
      networkAPIAvailable: typeof globalThis.fetch !== "undefined" || typeof globalThis.XMLHttpRequest !== "undefined"
    };
  }
  return __toCommonJS(planner_entry_exports);
})();
