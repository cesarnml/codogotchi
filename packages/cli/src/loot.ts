import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { LootEventResponse } from "@codogotchi/contracts";

export type LootTier = LootEventResponse["tier"];

export const TIERS: readonly LootTier[] = [
	"common",
	"uncommon",
	"rare",
	"epic",
	"legendary",
];

export function lootLogPath(home: string): string {
	return join(home, "loot.log");
}

export type LootDeps = {
	home: string;
};

export type LootOptions = {
	limit?: number;
	tier?: LootTier;
};

export type LootResult = {
	output: string;
	missingCache: boolean;
};

function isValidLootEvent(parsed: unknown): parsed is LootEventResponse {
	if (typeof parsed !== "object" || parsed === null) return false;
	const r = parsed as Record<string, unknown>;
	return (
		typeof r.tier === "string" &&
		(TIERS as readonly string[]).includes(r.tier) &&
		typeof r.name === "string" &&
		typeof r.source === "string" &&
		typeof r.ts === "number" &&
		Number.isFinite(r.ts)
	);
}

export async function readAllLoot(home: string): Promise<LootEventResponse[]> {
	let raw: string;
	try {
		raw = await readFile(lootLogPath(home), "utf8");
	} catch (err) {
		if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
		throw err;
	}
	const events: LootEventResponse[] = [];
	for (const line of raw.split("\n")) {
		if (line.length === 0) continue;
		try {
			const parsed: unknown = JSON.parse(line);
			if (isValidLootEvent(parsed)) events.push(parsed);
		} catch {
			// skip malformed lines
		}
	}
	return events;
}

export function formatLoot(events: LootEventResponse[]): string {
	if (events.length === 0) {
		return "No loot yet. Run `codogotchi sync` after some activity to drop your first events.\n";
	}
	const lines: string[] = [];
	lines.push(
		`Loot history (${events.length} event${events.length === 1 ? "" : "s"}):`,
	);
	for (const e of events) {
		const ts = new Date(e.ts).toISOString();
		const base = `  [${e.tier}] ${e.name} (${e.source}) — ${ts}`;
		lines.push(base);
		if (e.score_explanation) {
			lines.push(`      ${e.score_explanation}`);
		}
	}
	return `${lines.join("\n")}\n`;
}

export async function lootLogExists(home: string): Promise<boolean> {
	try {
		await readFile(lootLogPath(home), "utf8");
		return true;
	} catch (err) {
		if ((err as NodeJS.ErrnoException).code === "ENOENT") return false;
		throw err;
	}
}

export async function runLoot(
	deps: LootDeps,
	opts: LootOptions = {},
): Promise<LootResult> {
	const exists = await lootLogExists(deps.home);
	const all = await readAllLoot(deps.home);
	let filtered = opts.tier ? all.filter((e) => e.tier === opts.tier) : all;
	if (opts.limit !== undefined && opts.limit >= 0) {
		filtered = filtered.slice(-opts.limit);
	}
	return {
		missingCache: !exists,
		output: formatLoot(filtered),
	};
}
