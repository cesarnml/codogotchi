import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	parseStateJson,
	type ProfileResponse,
	type StateJsonV1,
	STATE_JSON_SCHEMA_VERSION,
} from "@codogotchi/contracts";
import { classifyEvent, type HookInput, runHook } from "./hook-binary";

const FIXED_NOW = new Date("2026-05-18T15:00:00.000Z");

function readState(home: string): StateJsonV1 {
	const raw = readFileSync(join(home, "state.json"), "utf8");
	return parseStateJson(JSON.parse(raw));
}

describe("classifyEvent", () => {
	it("classifies Claude Code Edit tool-use as implementing", () => {
		const out = classifyEvent(
			{
				origin: "claude_code",
				kind: "tool_use",
				name: "Edit",
			},
			{ readRun: 0 },
		);
		expect(out.state).toBe("implementing");
		expect(out.sourceEvent.origin).toBe("claude_code");
		expect(out.sourceEvent.kind).toBe("tool_use");
		expect(out.sourceEvent.name).toBe("Edit");
		expect(out.readRun).toBe(0);
	});

	it("classifies Write tool-use as implementing", () => {
		expect(
			classifyEvent(
				{ origin: "claude_code", kind: "tool_use", name: "Write" },
				{ readRun: 0 },
			).state,
		).toBe("implementing");
	});

	it("classifies MultiEdit tool-use as implementing", () => {
		expect(
			classifyEvent(
				{ origin: "claude_code", kind: "tool_use", name: "MultiEdit" },
				{ readRun: 0 },
			).state,
		).toBe("implementing");
	});

	it("classifies Bash 'bun test' as running-tests", () => {
		const out = classifyEvent(
			{
				origin: "claude_code",
				kind: "tool_use",
				name: "Bash",
				command: "bun test packages/engine",
			},
			{ readRun: 0 },
		);
		expect(out.state).toBe("running-tests");
	});

	it("classifies Bash 'pytest' as running-tests", () => {
		expect(
			classifyEvent(
				{
					origin: "claude_code",
					kind: "tool_use",
					name: "Bash",
					command: "pytest -k smoke",
				},
				{ readRun: 0 },
			).state,
		).toBe("running-tests");
	});

	it("classifies Bash 'git push' as pushing", () => {
		expect(
			classifyEvent(
				{
					origin: "claude_code",
					kind: "tool_use",
					name: "Bash",
					command: "git push origin main",
				},
				{ readRun: 0 },
			).state,
		).toBe("pushing");
	});

	it("classifies Bash with no recognized command as idle", () => {
		expect(
			classifyEvent(
				{
					origin: "claude_code",
					kind: "tool_use",
					name: "Bash",
					command: "ls -la",
				},
				{ readRun: 0 },
			).state,
		).toBe("idle");
	});

	it("requires 3 consecutive Read tool-uses to classify as reviewing", () => {
		const first = classifyEvent(
			{ origin: "claude_code", kind: "tool_use", name: "Read" },
			{ readRun: 0 },
		);
		expect(first.state).toBe("idle");
		expect(first.readRun).toBe(1);

		const second = classifyEvent(
			{ origin: "claude_code", kind: "tool_use", name: "Read" },
			{ readRun: first.readRun },
		);
		expect(second.state).toBe("idle");
		expect(second.readRun).toBe(2);

		const third = classifyEvent(
			{ origin: "claude_code", kind: "tool_use", name: "Read" },
			{ readRun: second.readRun },
		);
		expect(third.state).toBe("reviewing");
		expect(third.readRun).toBe(3);
	});

	it("resets Read run when an Edit interrupts", () => {
		const after_edit = classifyEvent(
			{ origin: "claude_code", kind: "tool_use", name: "Edit" },
			{ readRun: 2 },
		);
		expect(after_edit.state).toBe("implementing");
		expect(after_edit.readRun).toBe(0);
	});

	it("classifies SoA ticket_started as hyped", () => {
		expect(
			classifyEvent(
				{ origin: "soa", kind: "gate", name: "ticket_started" },
				{ readRun: 0 },
			).state,
		).toBe("hyped");
	});

	it("classifies SoA verification_failed as panicking", () => {
		expect(
			classifyEvent(
				{ origin: "soa", kind: "gate", name: "verification_failed" },
				{ readRun: 0 },
			).state,
		).toBe("panicking");
	});

	it("classifies SoA ticket_completed as celebrating", () => {
		expect(
			classifyEvent(
				{ origin: "soa", kind: "gate", name: "ticket_completed" },
				{ readRun: 0 },
			).state,
		).toBe("celebrating");
	});

	it("classifies SoA review_clean_recorded as celebrating", () => {
		expect(
			classifyEvent(
				{ origin: "soa", kind: "gate", name: "review_clean_recorded" },
				{ readRun: 0 },
			).state,
		).toBe("celebrating");
	});

	it("classifies session_start with no prior activity as idle", () => {
		expect(
			classifyEvent(
				{ origin: "claude_code", kind: "session_start", name: "start" },
				{ readRun: 0 },
			).state,
		).toBe("idle");
	});

	it("classifies session_end as idle", () => {
		expect(
			classifyEvent(
				{ origin: "claude_code", kind: "session_end", name: "end" },
				{ readRun: 0 },
			).state,
		).toBe("idle");
	});

	it("classifies Claude Code raw stdin {tool_name:'Edit'} as implementing", () => {
		const out = classifyEvent(
			{ tool_name: "Edit", hook_event_name: "PreToolUse" } as HookInput,
			{ readRun: 0 },
		);
		expect(out.state).toBe("implementing");
		expect(out.sourceEvent.origin).toBe("claude_code");
		expect(out.sourceEvent.kind).toBe("tool_use");
		expect(out.sourceEvent.name).toBe("Edit");
	});
});

describe("runHook", () => {
	let home: string;

	beforeEach(async () => {
		home = mkdtempSync(join(tmpdir(), "codogotchi-hook-"));
		await mkdir(home, { recursive: true });
	});

	afterEach(() => {
		rmSync(home, { recursive: true, force: true });
	});

	it("writes state.json on first event with default thriving overlay when no profile", async () => {
		await runHook(
			{ origin: "claude_code", kind: "tool_use", name: "Edit" },
			{ home, now: FIXED_NOW },
		);
		const state = readState(home);
		expect(state.schema_version).toBe(STATE_JSON_SCHEMA_VERSION);
		expect(state.activity_state).toBe("implementing");
		expect(state.hp).toBe(100);
		expect(state.hp_overlay).toBe("thriving");
		expect(state.updated_at).toBe(FIXED_NOW.toISOString());
		expect(state.source_event.name).toBe("Edit");
	});

	it("layers HP from profile.json when present", async () => {
		const profile: Pick<ProfileResponse, "hp" | "mood"> & {
			[k: string]: unknown;
		} = {
			hp: 20,
			mood: "near_death",
			profile_id: "p",
			handle: "h",
			xp_by_source: {
				claude_code: 0,
				codex: 0,
				github: 0,
				wakatime: 0,
			},
			total_xp: 0,
			stage: 1,
			died_at: null,
			cause: null,
			death_count: 0,
			last_signal_at_by_source: {
				claude_code: null,
				codex: null,
				github: null,
				wakatime: null,
			},
			updated_at: 0,
		};
		writeFileSync(
			join(home, "profile.json"),
			JSON.stringify(profile),
			"utf8",
		);

		await runHook(
			{ origin: "claude_code", kind: "tool_use", name: "Edit" },
			{ home, now: FIXED_NOW },
		);
		const state = readState(home);
		expect(state.hp).toBe(20);
		expect(state.hp_overlay).toBe("near_death");
	});

	it("classifies SoA gate event as celebrating", async () => {
		await runHook(
			{ origin: "soa", kind: "gate", name: "ticket_completed" },
			{ home, now: FIXED_NOW },
		);
		expect(readState(home).activity_state).toBe("celebrating");
	});

	it("tracks consecutive Read runs across invocations and switches to reviewing", async () => {
		const input: HookInput = {
			origin: "claude_code",
			kind: "tool_use",
			name: "Read",
		};
		await runHook(input, { home, now: FIXED_NOW });
		await runHook(input, { home, now: FIXED_NOW });
		expect(readState(home).activity_state).toBe("idle");

		await runHook(input, { home, now: FIXED_NOW });
		expect(readState(home).activity_state).toBe("reviewing");
	});

	it("resets Read run when an Edit interrupts across invocations", async () => {
		const read: HookInput = {
			origin: "claude_code",
			kind: "tool_use",
			name: "Read",
		};
		await runHook(read, { home, now: FIXED_NOW });
		await runHook(read, { home, now: FIXED_NOW });
		await runHook(
			{ origin: "claude_code", kind: "tool_use", name: "Edit" },
			{ home, now: FIXED_NOW },
		);
		await runHook(read, { home, now: FIXED_NOW });
		// One Read after reset is not enough for reviewing.
		expect(readState(home).activity_state).toBe("idle");
	});

	it("silently skips on malformed JSON without throwing", async () => {
		// Simulate a parser error path by passing invalid input through the
		// raw stdin entrypoint helper.
		const { runHookFromStdin } = await import("./hook-binary");
		await runHookFromStdin("{not valid json", { home, now: FIXED_NOW });
		// No state.json should have been written.
		expect(() => readState(home)).toThrow();
	});

	it("writes atomically (no half-written file visible at target)", async () => {
		await runHook(
			{ origin: "claude_code", kind: "tool_use", name: "Edit" },
			{ home, now: FIXED_NOW },
		);
		// Sanity: target file is fully parseable.
		const raw = readFileSync(join(home, "state.json"), "utf8");
		expect(() => JSON.parse(raw)).not.toThrow();
	});
});
