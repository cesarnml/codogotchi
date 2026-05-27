import { z } from "zod";

// CLI sends cumulative per-source counts. Server is canonical for XP — it
// recomputes from these counts via @codogotchi/engine. The schema deliberately
// excludes any precomputed XP fields so the wire format cannot lie.

export const signalClaudeSchema = z.object({
  tokens: z.number().int().nonnegative(),
});
export type SignalClaude = z.infer<typeof signalClaudeSchema>;

export const signalCodexSchema = z.object({
  tokens: z.number().int().nonnegative(),
});
export type SignalCodex = z.infer<typeof signalCodexSchema>;

export const prMergeSchema = z.object({
  number: z.number().int().nonnegative(),
  title: z.string(),
  additions: z.number().int().nonnegative(),
  deletions: z.number().int().nonnegative(),
  reviewCommentCount: z.number().int().nonnegative(),
  body: z.string().nullable().optional(),
});
export type PRMergePayload = z.infer<typeof prMergeSchema>;

export const signalGithubSchema = z.object({
  prs: z.array(prMergeSchema),
});
export type SignalGithub = z.infer<typeof signalGithubSchema>;

export const signalWakatimeSchema = z.object({
  hours: z.number().nonnegative(),
});
export type SignalWakatime = z.infer<typeof signalWakatimeSchema>;

export const signalsPayloadSchema = z.object({
  claude: signalClaudeSchema.nullable(),
  codex: signalCodexSchema.nullable(),
  github: signalGithubSchema.nullable(),
  wakatime: signalWakatimeSchema.nullable(),
});
export type SignalsPayload = z.infer<typeof signalsPayloadSchema>;

export const healthConfigSchema = z.object({
  weekend_decay: z.boolean(),
  grace_days: z.number().nonnegative(),
  vacation_until: z.string().nullable(),
  timezone: z.string().min(1),
  decay_per_day: z.number().nonnegative(),
  revive_threshold: z.number().nonnegative(),
  revive_hp: z.number(),
});
export type HealthConfigPayload = z.infer<typeof healthConfigSchema>;

export const syncProfileRequestSchema = z.object({
  profile_id: z.string().min(1),
  handle: z.string().min(1),
  signals: signalsPayloadSchema,
  config: healthConfigSchema,
  now: z.string().datetime({ offset: true }),
});
export type SyncProfileRequest = z.infer<typeof syncProfileRequestSchema>;

export const lootEventResponseSchema = z.object({
  profile_id: z.string(),
  tier: z.enum(["common", "uncommon", "rare", "epic", "legendary"]),
  name: z.string(),
  source: z.enum(["claude_code", "codex", "github", "wakatime"]),
  score_explanation: z.string().nullable(),
  ts: z.number(),
});
export type LootEventResponse = z.infer<typeof lootEventResponseSchema>;

export const profileResponseSchema = z.object({
  profile_id: z.string(),
  handle: z.string(),
  xp_by_source: z.object({
    claude_code: z.number(),
    codex: z.number(),
    github: z.number(),
    wakatime: z.number(),
  }),
  total_xp: z.number(),
  stage: z.number().int(),
  hp: z.number(),
  mood: z.enum(["thriving", "getting_sick", "near_death", "ghost"]),
  died_at: z.string().nullable(),
  cause: z.enum(["decay"]).nullable(),
  death_count: z.number().int().nonnegative(),
  last_signal_at_by_source: z.object({
    claude_code: z.string().nullable(),
    codex: z.string().nullable(),
    github: z.string().nullable(),
    wakatime: z.string().nullable(),
  }),
  updated_at: z.number(),
});
export type ProfileResponse = z.infer<typeof profileResponseSchema>;

export const syncProfileResponseSchema = z.object({
  profile: profileResponseSchema,
  new_loot_events: z.array(lootEventResponseSchema),
});
export type SyncProfileResponse = z.infer<typeof syncProfileResponseSchema>;
