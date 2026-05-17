export type LootTier = "common" | "uncommon" | "rare" | "epic" | "legendary";

export const LOOT_TIER_WEIGHTS: Record<LootTier, number> = {
	common: 60,
	uncommon: 25,
	rare: 10,
	epic: 4,
	legendary: 1,
};

const LOOT_TIER_ORDER: readonly LootTier[] = [
	"common",
	"uncommon",
	"rare",
	"epic",
	"legendary",
] as const;

export const BASE_DROP_PROBABILITY = 0.05;
export const PR_QUALITY_DROP_BONUS_MAX = 0.45;

export type LootSource = "claude_code" | "codex" | "github" | "wakatime";

export type RngFn = () => number;

export type LootContext = {
	source: LootSource;
	dropProbability?: number;
};

export type LootEvent = {
	tier: LootTier;
	source: LootSource;
};

export type PRMerge = {
	number: number;
	title: string;
	additions: number;
	deletions: number;
	reviewCommentCount: number;
	body?: string | null;
};

export type ScoredPR = PRMerge & {
	score: number;
	explanation: string;
};

function nonNegativeFiniteOrZero(n: number): number {
	return Number.isFinite(n) ? Math.max(0, n) : 0;
}

function clamp(n: number, lo: number, hi: number): number {
	if (n < lo) return lo;
	if (n > hi) return hi;
	return n;
}

function pickTier(roll: number): LootTier {
	const totalWeight = LOOT_TIER_ORDER.reduce(
		(sum, tier) => sum + LOOT_TIER_WEIGHTS[tier],
		0,
	);
	let cumulative = 0;
	for (const tier of LOOT_TIER_ORDER) {
		cumulative += LOOT_TIER_WEIGHTS[tier] / totalWeight;
		if (roll < cumulative) return tier;
	}
	// Floating-point straggler when roll ≈ 1; fall through to the rarest tier
	// rather than throwing, matching what callers expect of a tier roll.
	return LOOT_TIER_ORDER[LOOT_TIER_ORDER.length - 1] as LootTier;
}

export function rollLootDrop(
	rng: RngFn,
	context: LootContext,
): LootEvent | null {
	const probability = clamp(
		context.dropProbability ?? BASE_DROP_PROBABILITY,
		0,
		1,
	);
	if (rng() >= probability) return null;
	const tier = pickTier(rng());
	return { tier, source: context.source };
}

// Revert detection: GitHub's auto-generated revert PRs use the title prefix
// `Revert "<original title>"`. Matching the prefix is intentionally narrow —
// we only want to penalize confirmed reverts, not titles that happen to
// mention the word "revert".
const REVERT_TITLE_PATTERN = /^Revert\s+"/i;

function isRevert(pr: PRMerge): boolean {
	return REVERT_TITLE_PATTERN.test(pr.title);
}

export function scorePR(pr: PRMerge): ScoredPR {
	const reviewComments = nonNegativeFiniteOrZero(pr.reviewCommentCount);
	const additions = nonNegativeFiniteOrZero(pr.additions);
	const deletions = nonNegativeFiniteOrZero(pr.deletions);
	const churn = additions + deletions;
	const reverted = isRevert(pr);

	const reviewPenalty = Math.min(0.8, reviewComments * 0.02);
	let sizePenalty = 0;
	if (churn > 1000) sizePenalty = 0.3;
	else if (churn > 500) sizePenalty = 0.15;

	let score = 1 - reviewPenalty - sizePenalty;
	if (reverted) score *= 0.1;
	score = clamp(score, 0, 1);

	const parts = [
		`${reviewComments} review comments`,
		`+${additions}/-${deletions} LOC`,
	];
	if (reverted) parts.push("revert detected");
	const explanation = parts.join(", ");

	return { ...pr, score, explanation };
}

export function rollPRLootDropWithQuality(
	rng: RngFn,
	pr: ScoredPR,
): LootEvent | null {
	const probability = clamp(
		BASE_DROP_PROBABILITY + pr.score * PR_QUALITY_DROP_BONUS_MAX,
		0,
		1,
	);
	return rollLootDrop(rng, { source: "github", dropProbability: probability });
}
