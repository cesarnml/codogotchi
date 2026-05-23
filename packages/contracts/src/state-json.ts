import { z } from "zod";
import { activityStateSchema, hpOverlaySchema } from "./animation-state";

export const STATE_JSON_SCHEMA_VERSION = 2;

// Forward-compat policy from docs/contracts/animation-state-vocabulary.md:
// renderers accept any `schema_version` ≤ EXPECTED_VERSION (this constant),
// and refuse anything greater.
const schemaVersionField = z
  .number()
  .int()
  .min(1)
  .max(STATE_JSON_SCHEMA_VERSION);

export const sourceEventOriginSchema = z.enum([
  "claude_code",
  "codex",
  "soa",
  "sync",
  "manual",
]);
export type SourceEventOrigin = z.infer<typeof sourceEventOriginSchema>;

export const sourceEventKindSchema = z.enum([
  "tool_use",
  "session_start",
  "session_end",
  "gate",
  "sync_response",
  "cli",
]);
export type SourceEventKind = z.infer<typeof sourceEventKindSchema>;

export const sourceEventSchema = z.object({
  origin: sourceEventOriginSchema,
  kind: sourceEventKindSchema,
  name: z.string().min(1),
});
export type SourceEvent = z.infer<typeof sourceEventSchema>;

export const stateJsonV1Schema = z.object({
  schema_version: schemaVersionField,
  activity_state: activityStateSchema,
  hp_overlay: hpOverlaySchema,
  hp: z.number().int().min(-100).max(100),
  updated_at: z.string().datetime({ offset: true }),
  source_event: sourceEventSchema,
});
export type StateJsonV1 = z.infer<typeof stateJsonV1Schema>;

export function parseStateJson(raw: unknown): StateJsonV1 {
  return stateJsonV1Schema.parse(raw);
}
