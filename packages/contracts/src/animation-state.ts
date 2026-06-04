import { z } from "zod";

export const ACTIVITY_STATES = [
  // Floor / hook states
  "idle",
  "standby",
  "errored",
  "waiting_for_input",
  // Heuristic-tier hook states
  "implementing",
  "editing",
  "searching",
  "web_search",
  "verifying",
  "git_ops",
  "testing",
  "thinking",
  "reading",
  "cramming",
  // SoA gate states
  "ticket_started",
  "red_tdd",
  "green_tdd",
  "adversarial_review",
  "open_pr",
  "poll_review",
  "record_review",
  "advance",
  "ticket_completed",
  "review_clean",
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

// Reliable: hook or SoA-gate driven; no heuristic inference required.
export const RELIABLE_ACTIVITY_STATES = [
  "idle",
  "standby",
  "errored",
  "waiting_for_input",
  "ticket_started",
  "red_tdd",
  "green_tdd",
  "adversarial_review",
  "open_pr",
  "poll_review",
  "record_review",
  "advance",
  "ticket_completed",
  "review_clean",
] as const satisfies readonly ActivityState[];

// Heuristic: inferred from tool-use patterns; may occasionally misclassify.
export const HEURISTIC_ACTIVITY_STATES = [
  "implementing",
  "editing",
  "searching",
  "web_search",
  "verifying",
  "git_ops",
  "testing",
  "thinking",
  "reading",
  "cramming",
] as const satisfies readonly ActivityState[];

export function hpToOverlay(hp: number): HpOverlay {
  if (hp <= 0) return "ghost";
  if (hp <= 25) return "near_death";
  if (hp <= 75) return "getting_sick";
  return "thriving";
}
