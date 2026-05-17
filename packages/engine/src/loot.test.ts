import { describe, expect, it } from "bun:test";
import {
	BASE_DROP_PROBABILITY,
	LOOT_TIER_WEIGHTS,
	type LootTier,
	type PRMerge,
	rollLootDrop,
	rollPRLootDropWithQuality,
	scorePR,
} from "./loot";

function sequenceRng(values: number[]): () => number {
	let i = 0;
	return () => {
		const v = values[i++];
		if (v === undefined) {
			throw new Error("sequenceRng exhausted");
		}
		return v;
	};
}

function mulberry32(seed: number): () => number {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

function pr(overrides: Partial<PRMerge> = {}): PRMerge {
	return {
		number: 1,
		title: "feat: add thing",
		additions: 50,
		deletions: 10,
		reviewCommentCount: 0,
		...overrides,
	};
}

describe("rollLootDrop", () => {
	it("returns null when the drop-probability roll fails", () => {
		const rng = sequenceRng([0.99]);
		expect(rollLootDrop(rng, { source: "claude_code" })).toBeNull();
	});

	it("drops an event when the drop-probability roll succeeds", () => {
		const rng = sequenceRng([0.0, 0.0]);
		const event = rollLootDrop(rng, { source: "claude_code" });
		expect(event).not.toBeNull();
		expect(event?.source).toBe("claude_code");
		expect(event?.tier).toBe("common");
	});

	it("honors a per-context dropProbability override", () => {
		// override probability 1.0 means any rng < 1.0 drops.
		const rng = sequenceRng([0.9, 0.0]);
		const event = rollLootDrop(rng, {
			source: "wakatime",
			dropProbability: 1.0,
		});
		expect(event).not.toBeNull();
		expect(event?.source).toBe("wakatime");
	});

	it("returns rarer tier when the tier roll lands in the rare band", () => {
		// Common = 60, uncommon = 25, rare = 10 — rare band starts at 0.85.
		const rng = sequenceRng([0.0, 0.9]);
		const event = rollLootDrop(rng, { source: "github" });
		expect(event?.tier).toBe("rare");
	});

	it("returns legendary when the tier roll lands in the top band", () => {
		// Legendary weight is 1 of 100 — top 1% slice (>= 0.99).
		const rng = sequenceRng([0.0, 0.999]);
		const event = rollLootDrop(rng, { source: "github" });
		expect(event?.tier).toBe("legendary");
	});
});

describe("scorePR", () => {
	it("clean small PR scores high and explains why", () => {
		const scored = scorePR(pr());
		expect(scored.score).toBeGreaterThan(0.7);
		expect(scored.explanation).toContain("0 review comments");
		expect(scored.explanation).toContain("+50/-10");
	});

	it("heavy review traffic pushes score down and surfaces the count", () => {
		const heavy = scorePR(pr({ reviewCommentCount: 20 }));
		const clean = scorePR(pr({ reviewCommentCount: 0 }));
		expect(heavy.score).toBeLessThan(clean.score);
		expect(heavy.explanation).toContain("20 review comments");
	});

	it("reverts collapse the score and call out the revert", () => {
		const reverted = scorePR(pr({ title: 'Revert "feat: add thing"' }));
		expect(reverted.score).toBeLessThanOrEqual(0.2);
		expect(reverted.explanation.toLowerCase()).toContain("revert");
	});

	it("very large diffs incur a size penalty", () => {
		const tiny = scorePR(pr({ additions: 10, deletions: 5 }));
		const huge = scorePR(pr({ additions: 1200, deletions: 800 }));
		expect(huge.score).toBeLessThan(tiny.score);
		expect(huge.explanation).toContain("+1200/-800");
	});

	it("score is clamped to [0, 1]", () => {
		const awful = scorePR(
			pr({
				title: 'Revert "trash"',
				reviewCommentCount: 100,
				additions: 5000,
				deletions: 5000,
			}),
		);
		expect(awful.score).toBeGreaterThanOrEqual(0);
		expect(awful.score).toBeLessThanOrEqual(1);
	});
});

describe("rollPRLootDropWithQuality", () => {
	it("a top-quality PR drops more often than a junk PR for the same rng draw", () => {
		const clean = scorePR(pr());
		const trash = scorePR(pr({ title: 'Revert "x"', reviewCommentCount: 50 }));
		// rng draws 0.3 — within clean's effective probability but above trash's.
		expect(
			rollPRLootDropWithQuality(sequenceRng([0.3, 0.0]), clean),
		).not.toBeNull();
		expect(
			rollPRLootDropWithQuality(sequenceRng([0.3, 0.0]), trash),
		).toBeNull();
	});

	it("rng draw above the effective probability still yields no drop", () => {
		const clean = scorePR(pr());
		expect(rollPRLootDropWithQuality(sequenceRng([0.999]), clean)).toBeNull();
	});

	it("dropped event is sourced as github", () => {
		const clean = scorePR(pr());
		const event = rollPRLootDropWithQuality(sequenceRng([0.0, 0.0]), clean);
		expect(event?.source).toBe("github");
	});
});

describe("tier distribution under seeded sweep", () => {
	it("approximates LOOT_TIER_WEIGHTS over a large sweep", () => {
		const rng = mulberry32(0xc0d06017);
		const counts: Record<LootTier, number> = {
			common: 0,
			uncommon: 0,
			rare: 0,
			epic: 0,
			legendary: 0,
		};
		const N = 20_000;
		// Force every roll to drop by using dropProbability=1 and pairing rolls:
		// each rollLootDrop consumes two rng draws (drop check + tier pick).
		for (let i = 0; i < N; i++) {
			const event = rollLootDrop(rng, {
				source: "claude_code",
				dropProbability: 1,
			});
			if (event !== null) {
				counts[event.tier]++;
			}
		}
		const totalWeight = Object.values(LOOT_TIER_WEIGHTS).reduce(
			(a, b) => a + b,
			0,
		);
		for (const tier of Object.keys(LOOT_TIER_WEIGHTS) as LootTier[]) {
			const expectedShare = LOOT_TIER_WEIGHTS[tier] / totalWeight;
			const actualShare = counts[tier] / N;
			// Generous tolerance — distribution shape matters, not exact value.
			expect(Math.abs(actualShare - expectedShare)).toBeLessThan(0.025);
		}
	});

	it("BASE_DROP_PROBABILITY is exposed for callers", () => {
		expect(BASE_DROP_PROBABILITY).toBeGreaterThan(0);
		expect(BASE_DROP_PROBABILITY).toBeLessThan(1);
	});
});
