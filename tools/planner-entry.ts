import {
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
