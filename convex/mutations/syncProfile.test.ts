import { afterEach, describe, expect, spyOn, test } from "bun:test";
import type { SyncProfileRequest } from "@codogotchi/contracts";
import { convexTest } from "convex-test";
import { convexTestModules } from "../../test/convex-modules";
import { api } from "../_generated/api";
import schema from "../schema";

const NOW = "2026-05-18T12:00:00.000Z";

const baseConfig: SyncProfileRequest["config"] = {
	weekend_decay: false,
	grace_days: 2,
	vacation_until: null,
	timezone: "UTC",
	decay_per_day: 5,
	revive_threshold: 100,
	revive_hp: 50,
};

function req(over: Partial<SyncProfileRequest> = {}): SyncProfileRequest {
	return {
		profile_id: "profile-a",
		handle: "alice",
		signals: { claude: null, codex: null, github: null, wakatime: null },
		config: baseConfig,
		now: NOW,
		...over,
	};
}

describe("syncProfile mutation", () => {
	afterEach(() => {
		// Math.random is the only non-determinism in the loot path. Restore
		// after each test so probability stubs do not bleed across cases.
		spyOn(Math, "random").mockRestore?.();
	});

	test("creates a new profile on first sync when none exists", async () => {
		const t = convexTest(schema, convexTestModules);
		const out = await t.mutation(api.mutations.syncProfile.syncProfile, req());
		expect(out.profile.profile_id).toBe("profile-a");
		expect(out.profile.handle).toBe("alice");
		expect(out.profile.total_xp).toBe(0);
		expect(out.profile.stage).toBe(1);
		expect(out.profile.hp).toBeGreaterThan(0);
	});

	test("null source preserves prior per-source totals across syncs", async () => {
		// Force loot rng never-drops so the second sync stays deterministic.
		spyOn(Math, "random").mockReturnValue(0.99);
		const t = convexTest(schema, convexTestModules);

		await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({
				signals: {
					claude: { tokens: 1234 },
					codex: null,
					github: null,
					wakatime: null,
				},
			}),
		);

		const after = await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({ now: NOW }),
		);
		expect(after.profile.xp_by_source.claude_code).toBe(1234);
		expect(after.profile.last_signal_at_by_source.claude_code).not.toBeNull();
	});

	test("two profiles do not bleed (distinct UUIDs route correctly)", async () => {
		spyOn(Math, "random").mockReturnValue(0.99);
		const t = convexTest(schema, convexTestModules);

		await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({
				profile_id: "uuid-a",
				handle: "alice",
				signals: {
					claude: { tokens: 5000 },
					codex: null,
					github: null,
					wakatime: null,
				},
			}),
		);
		await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({
				profile_id: "uuid-b",
				handle: "bob",
				signals: {
					claude: null,
					codex: { tokens: 7777 },
					github: null,
					wakatime: null,
				},
			}),
		);

		const a = await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({ profile_id: "uuid-a" }),
		);
		const b = await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({ profile_id: "uuid-b" }),
		);

		expect(a.profile.xp_by_source.claude_code).toBe(5000);
		expect(a.profile.xp_by_source.codex).toBe(0);
		expect(b.profile.xp_by_source.codex).toBe(7777);
		expect(b.profile.xp_by_source.claude_code).toBe(0);
	});

	test("rolls and inserts loot events when probability fires", async () => {
		// Force rng to always-drop so a single sync produces deterministic loot.
		spyOn(Math, "random").mockReturnValue(0.0001);
		const t = convexTest(schema, convexTestModules);

		const out = await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({
				signals: {
					claude: { tokens: 100 },
					codex: null,
					github: null,
					wakatime: null,
				},
			}),
		);

		expect(out.new_loot_events.length).toBeGreaterThan(0);
		expect(out.new_loot_events[0]?.source).toBe("claude_code");
		expect(out.new_loot_events[0]?.profile_id).toBe("profile-a");

		const stored = await t.run(async (ctx) =>
			ctx.db
				.query("loot_events")
				.withIndex("by_profile_id", (q) => q.eq("profile_id", "profile-a"))
				.collect(),
		);
		expect(stored.length).toBe(out.new_loot_events.length);
	});

	test("HP changes when idle period exceeds grace through synthetic time", async () => {
		spyOn(Math, "random").mockReturnValue(0.99);
		const t = convexTest(schema, convexTestModules);

		const seed = await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({
				signals: {
					claude: { tokens: 1 },
					codex: null,
					github: null,
					wakatime: null,
				},
				now: "2026-05-01T12:00:00.000Z",
			}),
		);
		const startingHp = seed.profile.hp;

		// 10 days later, weekend_decay false but May 11 2026 is a Monday, so decay fires.
		const later = await t.mutation(
			api.mutations.syncProfile.syncProfile,
			req({
				signals: { claude: null, codex: null, github: null, wakatime: null },
				now: "2026-05-11T12:00:00.000Z",
			}),
		);
		expect(later.profile.hp).toBeLessThan(startingHp);
	});
});
