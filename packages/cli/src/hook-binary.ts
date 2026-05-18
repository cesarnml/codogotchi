import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
	type ActivityState,
	type HpOverlay,
	hpToOverlay,
	type ProfileResponse,
	type SourceEvent,
	type SourceEventKind,
	type SourceEventOrigin,
	STATE_JSON_SCHEMA_VERSION,
	type StateJsonV1,
	sourceEventSchema,
	stateJsonV1Schema,
} from "@codogotchi/contracts";

export type HookInput = {
	origin?: SourceEventOrigin;
	kind?: SourceEventKind;
	name?: string;
	command?: string;
	// Claude Code raw stdin shape.
	tool_name?: string;
	tool_input?: { command?: string } & Record<string, unknown>;
	hook_event_name?: string;
};

export type ClassifyState = { readRun: number };

export type ClassifyResult = {
	state: ActivityState;
	sourceEvent: SourceEvent;
	readRun: number;
};

const SOA_GATE_TO_STATE: Record<string, ActivityState> = {
	verification_failed: "panicking",
	subagent_invoked: "calling_for_backup",
	stage_advanced: "ascended",
	ticket_completed: "celebrating",
	review_clean_recorded: "celebrating",
	pr_review_window_opened: "waiting",
	risky_diff_detected: "nervous",
	flow_state_entered: "focused",
	ticket_started: "hyped",
};

const TEST_RUNNER_PREFIXES = [
	"bun test",
	"bun run test",
	"npm test",
	"npm run test",
	"pnpm test",
	"pnpm run test",
	"yarn test",
	"yarn run test",
	"pytest",
	"cargo test",
	"go test",
	"vitest",
	"jest",
];

const READ_RUN_THRESHOLD = 3;

type NormalizedEvent = {
	origin: SourceEventOrigin;
	kind: SourceEventKind;
	name: string;
	command: string | undefined;
};

function normalize(input: HookInput): NormalizedEvent | null {
	// Prefer explicit shape; fall back to Claude Code raw stdin shape.
	const rawOrigin = input.origin ?? "claude_code";
	const rawName = input.name ?? input.tool_name ?? "unknown";
	const rawKind =
		input.kind ?? (input.tool_name ? "tool_use" : "session_start");
	const candidate: SourceEvent = {
		origin: rawOrigin as SourceEventOrigin,
		kind: rawKind as SourceEventKind,
		name: rawName,
	};
	const parsed = sourceEventSchema.safeParse(candidate);
	if (!parsed.success) return null;
	const rawCommand = input.command ?? input.tool_input?.command;
	const command = typeof rawCommand === "string" ? rawCommand : undefined;
	return { ...parsed.data, command };
}

function matchesTestRunner(command: string): boolean {
	const trimmed = command.trimStart();
	return TEST_RUNNER_PREFIXES.some((prefix) => {
		if (!trimmed.startsWith(prefix)) return false;
		const next = trimmed.slice(prefix.length, prefix.length + 1);
		return next === "" || next === " " || next === "\t";
	});
}

export function classifyEvent(
	input: HookInput,
	prior: ClassifyState,
): ClassifyResult {
	const normalized = normalize(input) ?? {
		origin: "claude_code" as const,
		kind: "session_start" as const,
		name: "unknown",
		command: undefined,
	};
	const { origin, kind, name, command } = normalized;
	const sourceEvent: SourceEvent = { origin, kind, name };

	// SoA gate events win over heuristics.
	if (origin === "soa" && kind === "gate") {
		const mapped = SOA_GATE_TO_STATE[name];
		if (mapped !== undefined) {
			return { state: mapped, sourceEvent, readRun: 0 };
		}
	}

	if (kind === "tool_use") {
		if (name === "Edit" || name === "Write" || name === "MultiEdit") {
			return { state: "implementing", sourceEvent, readRun: 0 };
		}
		if (name === "Bash" && command !== undefined) {
			if (command.trimStart().startsWith("git push")) {
				return { state: "pushing", sourceEvent, readRun: 0 };
			}
			if (matchesTestRunner(command)) {
				return { state: "running-tests", sourceEvent, readRun: 0 };
			}
			return { state: "idle", sourceEvent, readRun: 0 };
		}
		if (name === "Read") {
			const nextRun = prior.readRun + 1;
			const state: ActivityState =
				nextRun >= READ_RUN_THRESHOLD ? "reviewing" : "idle";
			return { state, sourceEvent, readRun: nextRun };
		}
	}

	return { state: "idle", sourceEvent, readRun: 0 };
}

type Counters = { read_run: number };

function countersPath(home: string): string {
	return join(home, ".hook-counters.json");
}

async function readCounters(home: string): Promise<Counters> {
	try {
		const raw = await readFile(countersPath(home), "utf8");
		const parsed = JSON.parse(raw) as Partial<Counters>;
		const readRun =
			typeof parsed.read_run === "number" && Number.isFinite(parsed.read_run)
				? Math.max(0, Math.trunc(parsed.read_run))
				: 0;
		return { read_run: readRun };
	} catch (err) {
		if ((err as NodeJS.ErrnoException).code === "ENOENT") {
			return { read_run: 0 };
		}
		return { read_run: 0 };
	}
}

function tempName(target: string): string {
	return `${target}.tmp-${process.pid}-${Date.now()}-${randomUUID()}`;
}

async function writeCounters(home: string, counters: Counters): Promise<void> {
	const target = countersPath(home);
	const tmp = tempName(target);
	await writeFile(tmp, JSON.stringify(counters), "utf8");
	await rename(tmp, target);
}

export type HpSnapshot = { hp: number; hpOverlay: HpOverlay };

function isValidHp(value: unknown): value is number {
	return (
		typeof value === "number" &&
		Number.isInteger(value) &&
		value >= -100 &&
		value <= 100
	);
}

export async function readProfileOverlay(
	home: string,
): Promise<HpSnapshot | null> {
	try {
		const raw = await readFile(join(home, "profile.json"), "utf8");
		const parsed = JSON.parse(raw) as Partial<ProfileResponse>;
		if (!isValidHp(parsed.hp)) return null;
		return { hp: parsed.hp, hpOverlay: hpToOverlay(parsed.hp) };
	} catch (err) {
		if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
		return null;
	}
}

export function statePath(home: string): string {
	return join(home, "state.json");
}

export async function writeStateAtomic(
	home: string,
	state: StateJsonV1,
): Promise<void> {
	// Validate before writing — never let a malformed payload land at the
	// target path even if upstream callers pass an invalid shape.
	const verified = stateJsonV1Schema.parse(state);
	await mkdir(home, { recursive: true });
	const target = statePath(home);
	const tmp = tempName(target);
	await writeFile(tmp, `${JSON.stringify(verified, null, 2)}\n`, "utf8");
	await rename(tmp, target);
}

export type RunHookOptions = {
	home: string;
	now: Date;
};

export async function runHook(
	input: HookInput,
	opts: RunHookOptions,
): Promise<void> {
	await mkdir(opts.home, { recursive: true });
	const counters = await readCounters(opts.home);
	const classified = classifyEvent(input, { readRun: counters.read_run });

	const overlay = await readProfileOverlay(opts.home);
	const hp = overlay?.hp ?? 100;
	const hp_overlay = overlay?.hpOverlay ?? "thriving";

	const state: StateJsonV1 = {
		schema_version: STATE_JSON_SCHEMA_VERSION,
		activity_state: classified.state,
		hp_overlay,
		hp,
		updated_at: opts.now.toISOString(),
		source_event: classified.sourceEvent,
	};

	await writeStateAtomic(opts.home, state);
	await writeCounters(opts.home, { read_run: classified.readRun });
}

export async function runHookFromStdin(
	raw: string,
	opts: RunHookOptions,
): Promise<void> {
	let parsed: HookInput;
	try {
		const value = JSON.parse(raw);
		if (value === null || typeof value !== "object" || Array.isArray(value)) {
			// Silently skip — see ticket rationale: a crashed hook can spam logs.
			return;
		}
		parsed = value as HookInput;
	} catch {
		return;
	}
	try {
		await runHook(parsed, opts);
	} catch {
		// Silent skip on any write/IO failure to avoid polluting Claude Code logs.
	}
}
