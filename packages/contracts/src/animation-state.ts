import { z } from "zod";

export const ACTIVITY_STATES = [
  "idle",
  "implementing",
  "running-tests",
  "reviewing",
  "pushing",
  "hyped",
  "focused",
  "nervous",
  "waiting",
  "celebrating",
  "ascended",
  "calling_for_backup",
  "panicking",
  "requesting_input",
  "errored",
] as const;

export const activityStateSchema = z.enum(ACTIVITY_STATES);
export type ActivityState = z.infer<typeof activityStateSchema>;

export const HP_OVERLAY_STATES = [
  "thriving",
  "getting_sick",
  "near_death",
  "ghost",
] as const;

export const hpOverlaySchema = z.enum(HP_OVERLAY_STATES);
export type HpOverlay = z.infer<typeof hpOverlaySchema>;

export const RELIABLE_ACTIVITY_STATES = [
  "idle",
  "hyped",
  "focused",
  "nervous",
  "waiting",
  "celebrating",
  "ascended",
  "calling_for_backup",
  "panicking",
  "requesting_input",
  "errored",
] as const satisfies readonly ActivityState[];

export const HEURISTIC_ACTIVITY_STATES = [
  "implementing",
  "running-tests",
  "reviewing",
  "pushing",
] as const satisfies readonly ActivityState[];

export function hpToOverlay(hp: number): HpOverlay {
  if (hp <= 0) return "ghost";
  if (hp <= 25) return "near_death";
  if (hp <= 75) return "getting_sick";
  return "thriving";
}
