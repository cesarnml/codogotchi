import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	appendScorePRLog,
	type ScorePRLogEntry,
	scorePRLogPath,
	scorePRLogRotationPath,
} from "./score-pr-log";

function makeEntry(overrides: Partial<ScorePRLogEntry> = {}): ScorePRLogEntry {
	return {
		at: "2026-05-18T16:00:00.000Z",
		pr_number: 42,
		pr_url: "https://github.com/cesarnml/codogotchi/pull/42",
		title: "feat: do a thing",
		additions: 10,
		deletions: 2,
		review_comment_count: 0,
		score: 7,
		explanation: "small additive change",
		...overrides,
	};
}

describe("appendScorePRLog", () => {
	let home: string;

	beforeEach(() => {
		home = mkdtempSync(join(tmpdir(), "codogotchi-score-pr-"));
	});

	afterEach(() => {
		rmSync(home, { recursive: true, force: true });
	});

	it("appends one JSON line per call", async () => {
		await appendScorePRLog(home, makeEntry({ pr_number: 1 }));
		await appendScorePRLog(home, makeEntry({ pr_number: 2 }));
		const raw = readFileSync(scorePRLogPath(home), "utf8");
		const lines = raw.split("\n").filter((l) => l.length > 0);
		expect(lines).toHaveLength(2);
		const first = JSON.parse(lines[0] ?? "{}") as ScorePRLogEntry;
		const second = JSON.parse(lines[1] ?? "{}") as ScorePRLogEntry;
		expect(first.pr_number).toBe(1);
		expect(second.pr_number).toBe(2);
	});

	it("rotates to scorePR.log.1 when size crosses the limit", async () => {
		const limit = 256;
		// Each entry is ~150–200 bytes; two entries will exceed 256.
		await appendScorePRLog(home, makeEntry({ pr_number: 1 }), limit);
		await appendScorePRLog(home, makeEntry({ pr_number: 2 }), limit);
		// At this point either the second write rotated first, or the third
		// will. Force one more to ensure rotation.
		await appendScorePRLog(home, makeEntry({ pr_number: 3 }), limit);
		expect(existsSync(scorePRLogRotationPath(home))).toBe(true);
	});

	it("creates the home directory if it does not exist yet", async () => {
		const nestedHome = join(home, "nested", "deeper");
		await appendScorePRLog(nestedHome, makeEntry());
		expect(existsSync(scorePRLogPath(nestedHome))).toBe(true);
	});
});
