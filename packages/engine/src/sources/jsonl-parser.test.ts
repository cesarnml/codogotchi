import { describe, expect, it } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { readJsonlSignals } from "./jsonl-parser";

const FIXTURE_ROOT = resolve(
	__dirname,
	"..",
	"..",
	"test",
	"fixtures",
	"jsonl",
);
const CLAUDE_ROOT = join(FIXTURE_ROOT, "claude");
const CODEX_ROOT = join(FIXTURE_ROOT, "codex");

describe("readJsonlSignals — claude", () => {
	it("aggregates token counts per project and excludes pre-cutoff lines", async () => {
		const result = await readJsonlSignals({
			source: "claude",
			rootDir: CLAUDE_ROOT,
			since: new Date("2026-05-15T00:00:00.000Z"),
		});
		expect(result.source).toBe("claude");
		// proj-a: (100+50) + (200+40+10+5) + (50+10) = 150 + 255 + 60 = 465
		// proj-b: 300+150 = 450  (the 2026-05-14 line is excluded by since)
		expect(result.perProject["/repo/proj-a"]?.tokens).toBe(465);
		expect(result.perProject["/repo/proj-a"]?.events).toBe(3);
		expect(result.perProject["/repo/proj-b"]?.tokens).toBe(450);
		expect(result.perProject["/repo/proj-b"]?.events).toBe(1);
		expect(result.totalTokens).toBe(915);
		expect(result.events).toBe(4);
		expect(result.parseErrors).toBe(1);
		expect(result.lastEventAt?.toISOString()).toBe("2026-05-16T08:00:00.000Z");
	});

	it("returns zeros for an empty directory", async () => {
		const dir = await mkdtemp(join(tmpdir(), "jsonl-empty-"));
		try {
			const result = await readJsonlSignals({
				source: "claude",
				rootDir: dir,
				since: new Date(0),
			});
			expect(result.totalTokens).toBe(0);
			expect(result.events).toBe(0);
			expect(result.parseErrors).toBe(0);
			expect(result.lastEventAt).toBeNull();
			expect(result.perProject).toEqual({});
		} finally {
			await rm(dir, { recursive: true, force: true });
		}
	});

	it("returns zeros for a missing root directory without throwing", async () => {
		const result = await readJsonlSignals({
			source: "claude",
			rootDir: join(tmpdir(), "does-not-exist-jsonl-parser-test-xyz"),
			since: new Date(0),
		});
		expect(result.totalTokens).toBe(0);
		expect(result.events).toBe(0);
		expect(result.lastEventAt).toBeNull();
	});
});

describe("readJsonlSignals — codex", () => {
	it("aggregates token_count events keyed on session_meta cwd", async () => {
		const result = await readJsonlSignals({
			source: "codex",
			rootDir: CODEX_ROOT,
			since: new Date("2026-05-15T00:00:00.000Z"),
		});
		expect(result.source).toBe("codex");
		// /repo/codex-x: 1550 + 600 = 2150 (pre-cutoff line and bad payload skipped)
		expect(result.perProject["/repo/codex-x"]?.tokens).toBe(2150);
		expect(result.perProject["/repo/codex-x"]?.events).toBe(2);
		expect(result.totalTokens).toBe(2150);
		expect(result.events).toBe(2);
		expect(result.parseErrors).toBe(1);
		expect(result.lastEventAt?.toISOString()).toBe("2026-05-15T09:02:00.000Z");
	});

	it("buckets an in-window event under its session_meta cwd even when meta predates since", async () => {
		// Regression: the parser must not drop session_meta lines based on the
		// raw line timestamp, because that drops the per-file project state and
		// later in-window events fall back to <unknown>.
		const root = join(FIXTURE_ROOT, "codex-old-meta");
		const result = await readJsonlSignals({
			source: "codex",
			rootDir: root,
			since: new Date("2026-05-01T00:00:00.000Z"),
		});
		expect(result.perProject["/repo/codex-old-meta"]?.tokens).toBe(150);
		expect(result.perProject["<unknown>"]).toBeUndefined();
		expect(result.events).toBe(1);
	});

	it("since cutoff filters out the entire file when nothing qualifies", async () => {
		const result = await readJsonlSignals({
			source: "codex",
			rootDir: CODEX_ROOT,
			since: new Date("2099-01-01T00:00:00.000Z"),
		});
		expect(result.totalTokens).toBe(0);
		expect(result.events).toBe(0);
		expect(result.lastEventAt).toBeNull();
	});
});
