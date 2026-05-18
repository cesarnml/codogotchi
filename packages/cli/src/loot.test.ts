import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { LootEventResponse } from "@codogotchi/contracts";
import { type LootTier, lootLogPath, runLoot } from "./loot";

const NOW = new Date("2026-05-18T10:00:00.000Z").getTime();

function event(
	overrides: Partial<LootEventResponse> & { name: string; ts: number },
): LootEventResponse {
	return {
		profile_id: "p",
		tier: "common",
		name: overrides.name,
		source: "claude_code",
		score_explanation: null,
		ts: overrides.ts,
		...overrides,
	} as LootEventResponse;
}

async function writeLoot(home: string, events: LootEventResponse[]) {
	await writeFile(
		lootLogPath(home),
		events.map((e) => JSON.stringify(e)).join("\n"),
		"utf8",
	);
}

describe("runLoot", () => {
	let home: string;

	beforeEach(() => {
		home = mkdtempSync(join(tmpdir(), "codogotchi-loot-"));
	});

	afterEach(() => {
		rmSync(home, { recursive: true, force: true });
	});

	it("missing loot.log prints a helpful empty-state hint", async () => {
		const result = await runLoot({ home });
		expect(result.missingCache).toBe(true);
		expect(result.output).toContain("No loot yet");
	});

	it("renders populated history with score_explanation when present", async () => {
		await writeLoot(home, [
			event({
				name: "first-blood",
				ts: NOW - 60_000,
				tier: "common",
				source: "claude_code",
			}),
			event({
				name: "merge-master",
				ts: NOW - 30_000,
				tier: "rare",
				source: "github",
				score_explanation: "Large PR with thorough review",
			}),
		]);
		const result = await runLoot({ home });
		expect(result.missingCache).toBe(false);
		expect(result.output).toContain("Loot history (2 events)");
		expect(result.output).toContain("[common] first-blood");
		expect(result.output).toContain("[rare] merge-master");
		expect(result.output).toContain("Large PR with thorough review");
	});

	it("--limit N keeps only the last N events (newest preserved)", async () => {
		const events: LootEventResponse[] = [];
		for (let i = 0; i < 5; i++) {
			events.push(
				event({
					name: `loot-${i}`,
					ts: NOW - (5 - i) * 60_000,
					tier: "common",
				}),
			);
		}
		await writeLoot(home, events);
		const result = await runLoot({ home }, { limit: 2 });
		expect(result.output).toContain("Loot history (2 events)");
		expect(result.output).toContain("loot-4");
		expect(result.output).toContain("loot-3");
		expect(result.output).not.toContain("loot-0");
	});

	it("--tier filters to a single tier", async () => {
		await writeLoot(home, [
			event({ name: "c1", ts: NOW - 3000, tier: "common" }),
			event({ name: "r1", ts: NOW - 2000, tier: "rare" }),
			event({ name: "r2", ts: NOW - 1000, tier: "rare" }),
		]);
		const result = await runLoot({ home }, { tier: "rare" as LootTier });
		expect(result.output).toContain("r1");
		expect(result.output).toContain("r2");
		expect(result.output).not.toContain("c1");
	});

	it("--limit and --tier compose: filter then limit", async () => {
		await writeLoot(home, [
			event({ name: "c1", ts: NOW - 5000, tier: "common" }),
			event({ name: "r1", ts: NOW - 4000, tier: "rare" }),
			event({ name: "r2", ts: NOW - 3000, tier: "rare" }),
			event({ name: "r3", ts: NOW - 2000, tier: "rare" }),
		]);
		const result = await runLoot(
			{ home },
			{ tier: "rare" as LootTier, limit: 2 },
		);
		expect(result.output).toContain("r2");
		expect(result.output).toContain("r3");
		expect(result.output).not.toContain("r1");
		expect(result.output).not.toContain("c1");
	});

	it("empty loot.log file shows empty-state message (not missingCache)", async () => {
		await writeFile(lootLogPath(home), "", "utf8");
		const result = await runLoot({ home });
		expect(result.missingCache).toBe(false);
		expect(result.output).toContain("No loot yet");
	});
});
