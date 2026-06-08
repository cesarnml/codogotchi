import { z } from "zod";
import { activityStateSchema, hpOverlaySchema } from "./animation-state";

export const STATE_JSON_SCHEMA_VERSION = 6;

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
  "cursor",
  "vscode",
  "antigravity",
  "soa",
  "sync",
  "manual",
]);
export type SourceEventOrigin = z.infer<typeof sourceEventOriginSchema>;

export const sourceEventKindSchema = z.enum([
  "tool_use",
  "prompt_submit",
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
  terminal_bundle_id: z.string().optional(),
  repo_root: z.string().min(1).optional(),
});
export type SourceEvent = z.infer<typeof sourceEventSchema>;

export const stateJsonV1Schema = z
  .object({
    schema_version: schemaVersionField,
    activity_state: activityStateSchema,
    hp_overlay: hpOverlaySchema,
    hp: z.number().int().min(-100).max(100),
    updated_at: z.string().datetime({ offset: true }),
    source_event: sourceEventSchema,
    // v5 RPG progression fields — required when schema_version >= 5, optional for ≤4
    level: z.number().int().min(1).max(100).optional(),
    level_fraction: z.number().min(0).max(1).optional(),
    half_hearts: z.number().int().min(0).max(6).optional(),
    // Active-minute carry toward the next half-heart (0…59). Drives the
    // revival progress meter shown while the pet is dead. Optional/additive —
    // older writers and ≤v4 payloads omit it; renderers treat absence as 0.
    active_minutes: z.number().int().min(0).optional(),
    last_activity_at: z
      .string()
      .datetime({ offset: true })
      .nullable()
      .optional(),
    attention: z
      .object({
        reason_kind: z.enum([
          "input_requested",
          "error_blocked",
          "review_ready",
        ]),
        summary: z.string(),
        created_at: z.string().datetime({ offset: true }),
        expires_at: z.string().datetime({ offset: true }),
      })
      .optional(),
    tool_command: z.string().optional(),
    // v6 revive animation hint — present and non-null for 5 s after a health gain.
    // Renderer shows the `revive` row while Date.now() < Date.parse(revive_until).
    // Absent (or null) when no health gain occurred on this write.
    revive_until: z.string().datetime({ offset: true }).nullable().optional(),
  })
  .superRefine((data, ctx) => {
    if (data.schema_version >= 5) {
      const required: Array<keyof typeof data> = [
        "level",
        "level_fraction",
        "half_hearts",
        "last_activity_at",
      ];
      for (const field of required) {
        if (data[field] === undefined) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: [field],
            message: `${field} is required for schema_version >= 5`,
          });
        }
      }
    }
  });
export type StateJsonV1 = z.infer<typeof stateJsonV1Schema>;

export function parseStateJson(raw: unknown): StateJsonV1 {
  return stateJsonV1Schema.parse(raw);
}
