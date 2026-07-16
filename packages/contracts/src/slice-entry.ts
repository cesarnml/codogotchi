import { z } from "zod";
import { activityStateSchema } from "./animation-state";
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

// v8: RPG fields removed from slice; they now live in rpg-state.json.
// v9: hp/hp_overlay removed — no renderer read them off the slice (the real
// hp source of truth is profile.json / Convex); they were pure denormalization.
// v10: optional sticky ISO-8601 clocks for prompt/session/error/turn freeze.
// .strict() rejects any unknown keys so stale writers that include removed
// fields are caught at parse time rather than silently accepted.
export const sliceEntrySchema = z
  .object({
    schema_version: z.literal(STATE_JSON_SCHEMA_VERSION),
    origin: sourceEventOriginSchema,
    session_id: z
      .string()
      .min(1)
      .regex(/^[^/\\]+$/, "session_id must not contain path separators"),
    activity_state: activityStateSchema,
    updated_at: z.string().datetime({ offset: true }),
    source_event: sourceEventSchema,
    attention: attentionSchema.optional(),
    tool_command: z.string().optional(),
    prompt_started_at: z.string().datetime({ offset: true }).optional(),
    session_started_at: z.string().datetime({ offset: true }).optional(),
    errored_since: z.string().datetime({ offset: true }).optional(),
    turn_ended_at: z.string().datetime({ offset: true }).optional(),
  })
  .strict();

export type SliceEntry = z.infer<typeof sliceEntrySchema>;

// Generic reducer interface: collapses a slice collection to an arbitrary render target.
export type SliceReducer<T> = (slices: SliceEntry[]) => T;

const IDLE_DEFAULT: StateJsonV1 = {
  schema_version: STATE_JSON_SCHEMA_VERSION,
  activity_state: "idle",
  updated_at: new Date(0).toISOString(),
  source_event: { origin: "manual", kind: "cli", name: "idle-default" },
};

function sliceToStateJson(slice: SliceEntry): StateJsonV1 {
  return {
    schema_version: STATE_JSON_SCHEMA_VERSION,
    activity_state: slice.activity_state,
    updated_at: slice.updated_at,
    source_event: slice.source_event,
    attention: slice.attention,
    tool_command: slice.tool_command,
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
