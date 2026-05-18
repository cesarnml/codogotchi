import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type {
	LootEventResponse,
	ProfileResponse,
	StateJsonV1,
} from "@codogotchi/contracts";
import { profileCachePath, readProfileCache } from "./profile-cache";

export const STALE_SYNC_THRESHOLD_MS = 24 * 60 * 60 * 1000;

export type StatusDeps = {
	home: string;
	now: () => Date;
};

export type StatusResult = {
	output: string;
	missingProfile: boolean;
};

function formatNumber(n: number): string {
	return Math.round(n).toLocaleString("en-US");
}

function stateJsonPath(home: string): string {
	return join(home, "state.json");
}

function lootLogPath(home: string): string {
	return join(home, "loot.log");
}

async function readStateJson(home: string): Promise<StateJsonV1 | null> {
	try {
		const raw = await readFile(stateJsonPath(home), "utf8");
		return JSON.parse(raw) as StateJsonV1;
	} catch (err) {
		if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
		return null;
	}
}

async function readRecentLoot(
	home: string,
	limit = 5,
): Promise<LootEventResponse[]> {
	try {
		const raw = await readFile(lootLogPath(home), "utf8");
		const lines = raw.split("\n").filter((l) => l.length > 0);
		const recent = lines.slice(-limit);
		const events: LootEventResponse[] = [];
		for (const line of recent) {
			try {
				events.push(JSON.parse(line) as LootEventResponse);
			} catch {
				// skip malformed lines
			}
		}
		return events.reverse();
	} catch (err) {
		if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
		return [];
	}
}

function formatProfile(
	profile: ProfileResponse,
	state: StateJsonV1 | null,
	loot: LootEventResponse[],
	now: Date,
): string {
	const lines: string[] = [];
	lines.push(`@${profile.handle} — stage ${profile.stage}`);
	lines.push(
		`XP: ${formatNumber(profile.total_xp)} (claude=${formatNumber(
			profile.xp_by_source.claude_code,
		)} codex=${formatNumber(profile.xp_by_source.codex)} github=${formatNumber(
			profile.xp_by_source.github,
		)} wakatime=${formatNumber(profile.xp_by_source.wakatime)})`,
	);
	lines.push(`HP: ${formatNumber(profile.hp)} (${profile.mood})`);
	if (profile.died_at !== null) {
		lines.push(
			`Died at ${profile.died_at}${
				profile.cause ? ` (${profile.cause})` : ""
			} — death count ${profile.death_count}`,
		);
	}
	if (state !== null) {
		lines.push(
			`Current: activity=${state.activity_state} overlay=${state.hp_overlay} (updated ${state.updated_at})`,
		);
	}
	const updatedAtMs = profile.updated_at;
	if (updatedAtMs > 0) {
		const updatedDate = new Date(updatedAtMs);
		const ageMs = now.getTime() - updatedDate.getTime();
		const stale = ageMs > STALE_SYNC_THRESHOLD_MS;
		lines.push(
			`Last sync: ${updatedDate.toISOString()}${stale ? " (stale, >24h)" : ""}`,
		);
	} else {
		lines.push("Last sync: never");
	}
	if (loot.length > 0) {
		lines.push("Recent loot:");
		for (const event of loot) {
			lines.push(
				`  [${event.tier}] ${event.name} (${event.source}) — ${new Date(
					event.ts,
				).toISOString()}`,
			);
		}
	}
	return `${lines.join("\n")}\n`;
}

export async function runStatus(deps: StatusDeps): Promise<StatusResult> {
	throw new Error("not implemented");
}

export {
	formatNumber,
	formatProfile,
	lootLogPath,
	profileCachePath,
	readProfileCache,
	readRecentLoot,
	readStateJson,
	stateJsonPath,
};
