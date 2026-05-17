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
	claude: v.number(),
	codex: v.number(),
	github: v.number(),
	wakatime: v.number(),
});

const lastSignalAtBySource = v.object({
	claude: v.union(v.number(), v.null()),
	codex: v.union(v.number(), v.null()),
	github: v.union(v.number(), v.null()),
	wakatime: v.union(v.number(), v.null()),
});

const configSnapshot = v.object({
	weekend_decay: v.boolean(),
	grace_days: v.number(),
	vacation_until: v.union(v.string(), v.null()),
	timezone: v.string(),
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
		died_at: v.union(v.number(), v.null()),
		cause: v.union(v.string(), v.null()),
		death_count: v.number(),
		last_signal_at_by_source: lastSignalAtBySource,
		config_snapshot: configSnapshot,
		updated_at: v.number(),
	}).index("by_profile_id", ["profile_id"]),

	loot_events: defineTable({
		profile_id: v.string(),
		tier: v.union(...lootTiers.map((t) => v.literal(t))),
		name: v.string(),
		source: v.union(...lootSources.map((s) => v.literal(s))),
		score_explanation: v.union(v.string(), v.null()),
		ts: v.number(),
	})
		.index("by_profile_id", ["profile_id"])
		.index("by_ts", ["ts"]),
});
