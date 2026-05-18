import { describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readSoaEventsSince, resolveSoaRoot, type SoaTailState } from "./soa";

function makeTempRoot(): string {
	const root = mkdtempSync(join(tmpdir(), "codogotchi-soa-"));
	return root;
}

function writeEventsFile(root: string, lines: string[]): void {
	writeFileSync(join(root, ".soa", "events.ndjson"), `${lines.join("\n")}\n`);
}

async function ensureSoaDir(root: string): Promise<void> {
	await mkdir(join(root, ".soa"), { recursive: true });
}

describe("readSoaEventsSince", () => {
	it("returns empty events when .soa/events.ndjson is absent", async () => {
		const root = makeTempRoot();
		try {
			const result = await readSoaEventsSince(root, null);
			expect(result.events).toEqual([]);
			expect(result.tail).toBeNull();
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	it("parses valid NDJSON lines and updates tail state", async () => {
		const root = makeTempRoot();
		try {
			await ensureSoaDir(root);
			writeEventsFile(root, [
				JSON.stringify({
					name: "ticket_started",
					ts: "2026-05-18T16:00:00.000Z",
					plan_key: "phase-01",
					ticket_id: "P1.19",
				}),
				JSON.stringify({
					name: "verification_failed",
					ts: "2026-05-18T16:00:01.000Z",
				}),
			]);
			const result = await readSoaEventsSince(root, null);
			expect(result.events).toHaveLength(2);
			expect(result.events[0]?.name).toBe("ticket_started");
			expect(result.events[1]?.name).toBe("verification_failed");
			expect(result.tail).not.toBeNull();
			expect(result.tail?.offset).toBeGreaterThan(0);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	it("skips malformed lines without throwing", async () => {
		const root = makeTempRoot();
		try {
			await ensureSoaDir(root);
			writeEventsFile(root, [
				"this is not json",
				JSON.stringify({ name: "ticket_started", ts: "2026-05-18T16:00:00Z" }),
				"{not closed",
			]);
			const result = await readSoaEventsSince(root, null);
			expect(result.events).toHaveLength(1);
			expect(result.events[0]?.name).toBe("ticket_started");
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	it("only returns events after the previous tail offset", async () => {
		const root = makeTempRoot();
		try {
			await ensureSoaDir(root);
			writeEventsFile(root, [
				JSON.stringify({ name: "ticket_started", ts: "2026-05-18T16:00:00Z" }),
			]);
			const first = await readSoaEventsSince(root, null);
			expect(first.events).toHaveLength(1);
			expect(first.tail).not.toBeNull();

			// Append a new event.
			writeFileSync(
				join(root, ".soa", "events.ndjson"),
				`${JSON.stringify({ name: "ticket_completed", ts: "2026-05-18T16:00:01Z" })}\n`,
				{ flag: "a" },
			);
			const second = await readSoaEventsSince(root, first.tail);
			expect(second.events).toHaveLength(1);
			expect(second.events[0]?.name).toBe("ticket_completed");
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	it("resets to offset 0 when inode changes (rotation)", async () => {
		const root = makeTempRoot();
		try {
			await ensureSoaDir(root);
			writeEventsFile(root, [
				JSON.stringify({ name: "ticket_started", ts: "2026-05-18T16:00:00Z" }),
			]);
			const first = await readSoaEventsSince(root, null);
			expect(first.tail).not.toBeNull();

			// Simulate rotation: delete + recreate with different content.
			rmSync(join(root, ".soa", "events.ndjson"));
			writeEventsFile(root, [
				JSON.stringify({
					name: "stage_advanced",
					ts: "2026-05-18T16:01:00Z",
				}),
			]);

			// Pass stale tail with mismatched inode; reader must re-read from 0.
			const stale: SoaTailState = {
				inode: (first.tail?.inode ?? 0) + 999999,
				offset: 9999,
			};
			const second = await readSoaEventsSince(root, stale);
			expect(second.events).toHaveLength(1);
			expect(second.events[0]?.name).toBe("stage_advanced");
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});
});

describe("resolveSoaRoot", () => {
	it("prefers CLAUDE_PROJECT_DIR over CODEX_PROJECT_DIR and cwd", () => {
		expect(
			resolveSoaRoot({
				CLAUDE_PROJECT_DIR: "/claude",
				CODEX_PROJECT_DIR: "/codex",
				CWD: "/cwd",
			}),
		).toBe("/claude");
	});

	it("falls back to CODEX_PROJECT_DIR when CLAUDE_PROJECT_DIR is absent", () => {
		expect(
			resolveSoaRoot({
				CODEX_PROJECT_DIR: "/codex",
				CWD: "/cwd",
			}),
		).toBe("/codex");
	});

	it("falls back to cwd when both are absent", () => {
		expect(
			resolveSoaRoot({
				CWD: "/cwd",
			}),
		).toBe("/cwd");
	});
});
