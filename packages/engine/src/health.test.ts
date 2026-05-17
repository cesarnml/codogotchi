import { describe, expect, it } from "bun:test";
import {
	DEFAULT_HEALTH_CONFIG,
	type HealthConfig,
	hpBucket,
	type ProfileHealth,
	tickHealth,
} from "./health";

const TZ = "America/New_York";

function profile(overrides: Partial<ProfileHealth> = {}): ProfileHealth {
	return {
		hp: 100,
		last_signal_at: null,
		died_at: null,
		death_count: 0,
		...overrides,
	};
}

function config(overrides: Partial<HealthConfig> = {}): HealthConfig {
	return { ...DEFAULT_HEALTH_CONFIG, timezone: TZ, ...overrides };
}

const noSignals = {
	claudeTokens: 0,
	codexTokens: 0,
	githubPRs: 0,
	wakatimeHours: 0,
};

const someActivity = {
	claudeTokens: 1000,
	codexTokens: 0,
	githubPRs: 0,
	wakatimeHours: 0,
};

describe("hpBucket", () => {
	it("matches contract overlay boundaries", () => {
		expect(hpBucket(100)).toBe("thriving");
		expect(hpBucket(76)).toBe("thriving");
		expect(hpBucket(75)).toBe("getting_sick");
		expect(hpBucket(26)).toBe("getting_sick");
		expect(hpBucket(25)).toBe("near_death");
		expect(hpBucket(1)).toBe("near_death");
		expect(hpBucket(0)).toBe("ghost");
		expect(hpBucket(-10)).toBe("ghost");
	});
});

describe("weekend rule", () => {
	const sat = new Date("2026-05-16T15:00:00-04:00"); // Saturday in NY
	const sun = new Date("2026-05-17T15:00:00-04:00"); // Sunday in NY
	const mon = new Date("2026-05-18T15:00:00-04:00"); // Monday in NY
	const stale = profile({
		hp: 80,
		last_signal_at: "2026-05-01T00:00:00Z", // 15+ days idle
	});

	it("skips decay on Saturday when weekend_decay=false (default)", () => {
		const next = tickHealth(sat, stale, noSignals, config());
		expect(next.hp).toBe(80);
	});

	it("skips decay on Sunday when weekend_decay=false (default)", () => {
		const next = tickHealth(sun, stale, noSignals, config());
		expect(next.hp).toBe(80);
	});

	it("applies decay on Monday despite long idle stretch", () => {
		const next = tickHealth(mon, stale, noSignals, config());
		expect(next.hp).toBeLessThan(80);
	});

	it("respects timezone: Saturday in Pacific/Auckland triggers weekend skip even when UTC says Friday", () => {
		// 2026-05-15 18:00Z is Friday in UTC but Saturday 06:00 in Auckland
		const t = new Date("2026-05-15T18:00:00Z");
		const next = tickHealth(
			t,
			stale,
			noSignals,
			config({ timezone: "Pacific/Auckland" }),
		);
		expect(next.hp).toBe(80);
	});

	it("applies decay on weekend when weekend_decay=true is set explicitly", () => {
		const next = tickHealth(
			sat,
			stale,
			noSignals,
			config({ weekend_decay: true }),
		);
		expect(next.hp).toBeLessThan(80);
	});
});

describe("grace period", () => {
	const mon = new Date("2026-05-18T15:00:00-04:00"); // Monday

	it("skips decay when days-since-last-signal is strictly less than grace_days", () => {
		// last signal 1 day ago, grace_days=2 → still in grace
		const recent = profile({
			hp: 80,
			last_signal_at: new Date(mon.getTime() - 24 * 3600 * 1000).toISOString(),
		});
		const next = tickHealth(mon, recent, noSignals, config({ grace_days: 2 }));
		expect(next.hp).toBe(80);
	});

	it("applies decay when days-since-last-signal equals grace_days (boundary is exclusive on grace side)", () => {
		const old = profile({
			hp: 80,
			last_signal_at: new Date(
				mon.getTime() - 2 * 24 * 3600 * 1000,
			).toISOString(),
		});
		const next = tickHealth(mon, old, noSignals, config({ grace_days: 2 }));
		expect(next.hp).toBeLessThan(80);
	});
});

describe("vacation rule", () => {
	const mon = new Date("2026-05-18T15:00:00-04:00");
	const stale = profile({ hp: 80, last_signal_at: "2026-05-01T00:00:00Z" });

	it("suspends decay while vacation_until is in the future", () => {
		const next = tickHealth(
			mon,
			stale,
			noSignals,
			config({ vacation_until: "2026-05-20T00:00:00Z" }),
		);
		expect(next.hp).toBe(80);
	});

	it("resumes decay once vacation_until is in the past", () => {
		const next = tickHealth(
			mon,
			stale,
			noSignals,
			config({ vacation_until: "2026-05-10T00:00:00Z" }),
		);
		expect(next.hp).toBeLessThan(80);
	});

	it("ignores vacation_until=null", () => {
		const next = tickHealth(
			mon,
			stale,
			noSignals,
			config({ vacation_until: null }),
		);
		expect(next.hp).toBeLessThan(80);
	});
});

describe("decay accumulation + death + revival", () => {
	const mon = new Date("2026-05-18T15:00:00-04:00");

	it("multi-day idle stretch on weekdays accumulates decay", () => {
		const stale = profile({
			hp: 100,
			last_signal_at: "2026-04-01T00:00:00Z", // very old
		});
		const next = tickHealth(
			mon,
			stale,
			noSignals,
			config({ decay_per_day: 5 }),
		);
		expect(next.hp).toBeLessThan(100);
		expect(next.hp).toBeGreaterThanOrEqual(0);
	});

	it("sets died_at and cause when HP reaches 0", () => {
		const dying = profile({
			hp: 3,
			last_signal_at: "2026-04-01T00:00:00Z",
		});
		const next = tickHealth(
			mon,
			dying,
			noSignals,
			config({ decay_per_day: 5 }),
		);
		expect(next.hp).toBe(0);
		expect(next.died_at).not.toBeNull();
		expect(next.cause).toBe("decay");
		expect(next.death_count).toBe(1);
	});

	it("does not double-count death once already dead", () => {
		const dead = profile({
			hp: 0,
			died_at: "2026-05-10T00:00:00Z",
			cause: "decay",
			death_count: 1,
			last_signal_at: "2026-04-01T00:00:00Z",
		});
		const next = tickHealth(mon, dead, noSignals, config());
		expect(next.death_count).toBe(1);
		expect(next.died_at).toBe("2026-05-10T00:00:00Z");
	});

	it("revives on activity above revive_threshold and sets HP to revive_hp", () => {
		const dead = profile({
			hp: 0,
			died_at: "2026-05-10T00:00:00Z",
			cause: "decay",
			death_count: 1,
			last_signal_at: "2026-04-01T00:00:00Z",
		});
		const next = tickHealth(
			mon,
			dead,
			{ ...someActivity, claudeTokens: 100_000 },
			config({ revive_threshold: 1000, revive_hp: 50 }),
		);
		expect(next.died_at).toBeNull();
		expect(next.cause).toBeUndefined();
		expect(next.hp).toBe(50);
	});

	it("activity below revive_threshold does not revive", () => {
		const dead = profile({
			hp: 0,
			died_at: "2026-05-10T00:00:00Z",
			cause: "decay",
			death_count: 1,
			last_signal_at: "2026-04-01T00:00:00Z",
		});
		const next = tickHealth(
			mon,
			dead,
			{ ...someActivity, claudeTokens: 10 },
			config({ revive_threshold: 1000, revive_hp: 50 }),
		);
		expect(next.died_at).not.toBeNull();
		expect(next.hp).toBe(0);
	});
});

describe("activity records last_signal_at", () => {
	const mon = new Date("2026-05-18T15:00:00-04:00");

	it("updates last_signal_at when any source has nonzero activity", () => {
		const p = profile({ hp: 80, last_signal_at: "2026-05-01T00:00:00Z" });
		const next = tickHealth(mon, p, someActivity, config());
		expect(next.last_signal_at).toBe(mon.toISOString());
	});

	it("activity within grace period keeps HP and refreshes signal", () => {
		const p = profile({ hp: 80, last_signal_at: "2026-05-17T15:00:00-04:00" });
		const next = tickHealth(mon, p, someActivity, config());
		expect(next.hp).toBe(80);
		expect(next.last_signal_at).toBe(mon.toISOString());
	});
});

describe("integration: 10 days of synthetic time", () => {
	it("Mon active → Tue idle → Wed idle (grace expires) → ... weekend skip → resumes", () => {
		// Start Mon active, hp 100; idle Tue–Sun; resume next Mon.
		// grace_days=2, weekend_decay=false, decay_per_day=10
		const start = profile({
			hp: 100,
			last_signal_at: "2026-05-18T15:00:00-04:00",
		});
		const cfg = config({ grace_days: 2, decay_per_day: 10 });
		const days = [
			"2026-05-19T15:00:00-04:00", // Tue (idle, within grace)
			"2026-05-20T15:00:00-04:00", // Wed (grace expired, decay)
			"2026-05-21T15:00:00-04:00", // Thu (decay)
			"2026-05-22T15:00:00-04:00", // Fri (decay)
			"2026-05-23T15:00:00-04:00", // Sat (weekend, skip)
			"2026-05-24T15:00:00-04:00", // Sun (weekend, skip)
			"2026-05-25T15:00:00-04:00", // Mon (decay)
		];
		let p = start;
		for (const d of days) {
			p = tickHealth(new Date(d), p, noSignals, cfg);
		}
		// Decay days: Wed, Thu, Fri, Mon → 4 decay days × 10 = 40
		expect(p.hp).toBe(60);
		expect(p.died_at).toBeNull();
	});
});
