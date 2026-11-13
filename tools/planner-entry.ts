import {
  analyzePlan,
  planDrawListWithOptions,
  planDeconstructionPlannerDrawList,
  planUpgradePlannerDrawList,
} from "./vendor/fpsr/packages/renderer/src/planner.js";

export {
  planDrawList,
  planDrawListWithOptions,
  planDeconstructionPlannerDrawList,
  planUpgradePlannerDrawList,
  resolve,
} from "./vendor/fpsr/packages/renderer/src/planner.js";

export const plannerRevision = "2f7dc70f2681de530402556f757006e904e692d5";

/** One JSON transfer per job; no host callbacks or filesystem/network capabilities. */
export function nativePlan(entryJSON: string, dbJSON: string): string {
  const started = Date.now();
  const entry = JSON.parse(entryJSON);
  const db = JSON.parse(dbJSON);
  const parsed = Date.now();
  let list;
  let warnings: string[] = [];
  if (entry.blueprint) {
    list = planDrawListWithOptions(entry.blueprint, db, { altMode: true }).drawList;
  } else if (entry.upgrade_planner) {
    list = planUpgradePlannerDrawList(entry.upgrade_planner, db);
  } else if (entry.deconstruction_planner) {
    list = planDeconstructionPlannerDrawList(entry.deconstruction_planner, db);
  } else {
    throw new Error("Select a blueprint or planner leaf, not a book container.");
  }
  if (list.commands.length > 250_000) throw new Error("Draw command limit exceeded.");
  const diagnostics = analyzePlan(entry.blueprint ?? {}, list, db);
  if (!Object.values(diagnostics.checks).every(Boolean)) throw new Error("Invalid planner draw-list integrity.");
  warnings = [
    ...diagnostics.entities.unsupported.map(value => `Unsupported entity: ${value.name} (${value.count})`),
    ...diagnostics.tiles.unsupported.map(value => `Unsupported tile: ${value.name} (${value.count})`),
  ];
  const result = JSON.stringify({
    schema: 1, drawList: list, warnings,
    commandKinds: diagnostics.drawList.byKind,
    parseMs: parsed - started, planningMs: Date.now() - parsed,
  });
  if (result.length > 64 * 1024 * 1024) throw new Error("Draw-list transfer limit exceeded.");
  return result;
}

export function selfTest() {
  const db = { frames: [], icons: {} } as never;
  const planner = { settings: {} };
  const upgrade = planUpgradePlannerDrawList(planner, db);
  const deconstruction = planDeconstructionPlannerDrawList(planner, db);
  return {
    schema: 1,
    plannerRevision,
    upgradeCommands: upgrade.commands.length,
    deconstructionCommands: deconstruction.commands.length,
    finiteBounds: [upgrade, deconstruction].every(list =>
      Object.values(list.bounds).every(Number.isFinite)),
    nodeAvailable: typeof (globalThis as Record<string, unknown>).process !== "undefined" ||
      typeof (globalThis as Record<string, unknown>).require !== "undefined",
    networkAPIAvailable: typeof (globalThis as Record<string, unknown>).fetch !== "undefined" ||
      typeof (globalThis as Record<string, unknown>).XMLHttpRequest !== "undefined",
  };
}
