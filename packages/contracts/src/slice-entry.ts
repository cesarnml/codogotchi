import { z } from "zod";
import { activityStateSchema, hpOverlaySchema } from "./animation-state";
import type { StateJsonV1 } from "./state-json";
import {
  STATE_JSON_SCHEMA_VERSION,
  sourceEventOriginSchema,
  sourceEventSchema,
} from "./state-json";

const attentionSchema = z.object({
  reason_kind: z.enum(["input_requested", "error_blocked", "review_ready"]),
  summary: z.string(),
  created_at: z.string().datetime({ offset: true }),
  expires_at: z.string().datetime({ offset: true }),
});

export const sliceEntrySchema = z.object({
  origin: sourceEventOriginSchema,
  session_id: z
    .string()
    .min(1)
    .regex(/^[^/\\]+$/, "session_id must not contain path separators"),
  activity_state: activityStateSchema,
  hp_overlay: hpOverlaySchema,
  hp: z.number().int().min(-100).max(100),
  updated_at: z.string().datetime({ offset: true }),
  source_event: sourceEventSchema,
  // v5 RPG fields
  level: z.number().int().min(1).max(100).optional(),
  level_fraction: z.number().min(0).max(1).optional(),
  half_hearts: z.number().int().min(0).max(6).optional(),
  active_minutes: z.number().int().min(0).optional(),
  last_activity_at: z.string().datetime({ offset: true }).nullable().optional(),
  attention: attentionSchema.optional(),
  tool_command: z.string().optional(),
  revive_until: z.string().datetime({ offset: true }).nullable().optional(),
});

export type SliceEntry = z.infer<typeof sliceEntrySchema>;

// Generic reducer interface: collapses a slice collection to an arbitrary render target.
export type SliceReducer<T> = (slices: SliceEntry[]) => T;

const IDLE_DEFAULT: StateJsonV1 = {
  schema_version: STATE_JSON_SCHEMA_VERSION,
  activity_state: "idle",
  hp_overlay: "thriving",
  hp: 100,
  updated_at: new Date(0).toISOString(),
  source_event: { origin: "manual", kind: "cli", name: "idle-default" },
};

function sliceToStateJson(slice: SliceEntry): StateJsonV1 {
  return {
    schema_version: STATE_JSON_SCHEMA_VERSION,
    activity_state: slice.activity_state,
    hp_overlay: slice.hp_overlay,
    hp: slice.hp,
    updated_at: slice.updated_at,
    source_event: slice.source_event,
    level: slice.level,
    level_fraction: slice.level_fraction,
    half_hearts: slice.half_hearts,
    active_minutes: slice.active_minutes,
    last_activity_at: slice.last_activity_at,
    attention: slice.attention,
    tool_command: slice.tool_command,
    revive_until: slice.revive_until,
  };
}

// Tie-resolution: equal updated_at → first-in-array wins (strict >, not >=).
// updated_at comparison uses epoch millis so offset-aware strings (e.g. +07:00)
// are compared by wall-clock UTC rather than lexicographic character order.
function latestSlice(slices: SliceEntry[]): SliceEntry | undefined {
  return slices.reduce<SliceEntry | undefined>((winner, candidate) => {
    if (!winner) return candidate;
    return new Date(candidate.updated_at).getTime() >
      new Date(winner.updated_at).getTime()
      ? candidate
      : winner;
  }, undefined);
}

// Collapses the full slice set to a single StateJsonV1 using most-recent updated_at as
// the tiebreak — consistent with today's last-writer-wins single-file behavior.
// Empty set returns a synthetic idle default.
export const globalAggregate: SliceReducer<StateJsonV1> = (slices) => {
  const winner = latestSlice(slices);
  return winner ? sliceToStateJson(winner) : { ...IDLE_DEFAULT };
};

// Groups slices by origin and collapses each group to a single StateJsonV1 via the
// same most-recent tiebreak. Pure function — wired to no consumer in this phase.
export const perPlatform: SliceReducer<Record<string, StateJsonV1>> = (
  slices,
) => {
  const groups = new Map<string, SliceEntry[]>();
  for (const slice of slices) {
    const group = groups.get(slice.origin) ?? [];
    group.push(slice);
    groups.set(slice.origin, group);
  }
  const result: Record<string, StateJsonV1> = {};
  for (const [origin, group] of groups) {
    const winner = latestSlice(group);
    if (winner) result[origin] = sliceToStateJson(winner);
  }
  return result;
};
