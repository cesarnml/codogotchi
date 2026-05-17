import { HP_OVERLAY_STATES, type HpOverlay } from "@codogotchi/contracts";
import type { LootSource, LootTier } from "@codogotchi/engine";
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// Mood = HP overlay bucket (thriving / getting_sick / near_death / ghost).
// Keep this list locked to HP_OVERLAY_STATES via the `satisfies` assertion below.
const moodLiterals = HP_OVERLAY_STATES.map((s) => v.literal(s));
HP_OVERLAY_STATES satisfies readonly HpOverlay[];

// Loot tier and source literals are mirrored from @codogotchi/engine. The
// `satisfies` assertions below fail to compile if the engine enum changes
// without updating this schema — a deliberate type-time drift gate.
const lootTiers = [
	"common",
	"uncommon",
	"rare",
	"epic",
	"legendary",
] as const satisfies readonly LootTier[];
const lootSources = [
	"claude_code",
	"codex",
	"github",
	"wakatime",
] as const satisfies readonly LootSource[];

const xpBySource = v.object({
	claude_code: v.number(),
	codex: v.number(),
	github: v.number(),
	wakatime: v.number(),
});

// Signal timestamps are ISO-8601 strings — engine writes `now.toISOString()`
// (see `packages/engine/src/health.ts`). Storing them as strings preserves
// timezone semantics and avoids a server-side parse on every write.
const lastSignalAtBySource = v.object({
	claude_code: v.union(v.string(), v.null()),
	codex: v.union(v.string(), v.null()),
	github: v.union(v.string(), v.null()),
	wakatime: v.union(v.string(), v.null()),
});

// Full snapshot of `HealthConfig` from `packages/engine/src/health.ts`. Stored
// per-profile so server-side health ticks are deterministic from the row alone
// — the user's runtime knobs and the tuning constants ride together.
const configSnapshot = v.object({
	weekend_decay: v.boolean(),
	grace_days: v.number(),
	vacation_until: v.union(v.string(), v.null()),
	timezone: v.string(),
	decay_per_day: v.number(),
	revive_threshold: v.number(),
	revive_hp: v.number(),
});

export default defineSchema({
	users: defineTable({
		handle: v.string(),
		profile_id: v.string(),
		created_at: v.number(),
	}).index("by_handle", ["handle"]),

	profiles: defineTable({
		profile_id: v.string(),
		handle: v.string(),
		xp_by_source: xpBySource,
		total_xp: v.number(),
		stage: v.number(),
		hp: v.number(),
		mood: v.union(...moodLiterals),
		died_at: v.union(v.string(), v.null()),
		// `cause` mirrors engine `ProfileHealth.cause` (`"decay" | undefined`).
		// Persisted as `"decay" | null` so the column is queryable and matches
		// the only failure mode the engine currently emits.
		cause: v.union(v.literal("decay"), v.null()),
		death_count: v.number(),
		last_signal_at_by_source: lastSignalAtBySource,
		config_snapshot: configSnapshot,
		updated_at: v.number(),
	})
		.index("by_profile_id", ["profile_id"])
		.index("by_handle", ["handle"]),

	loot_events: defineTable({
		profile_id: v.string(),
		tier: v.union(...lootTiers.map((t) => v.literal(t))),
		name: v.string(),
		source: v.union(...lootSources.map((s) => v.literal(s))),
		score_explanation: v.union(v.string(), v.null()),
		ts: v.number(),
	})
		.index("by_profile_id", ["profile_id"])
		.index("by_profile_id_ts", ["profile_id", "ts"])
		.index("by_ts", ["ts"]),
});
