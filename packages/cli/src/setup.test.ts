import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SyncProfileRequest } from "@codogotchi/contracts";
import { configPath, readConfig } from "./config";
import { ConfigExistsError, runSetup, type SetupDeps } from "./setup";

function scriptedPrompter(answers: string[]) {
	const queue = [...answers];
	const notices: string[] = [];
	return {
		notices,
		prompter: {
			async ask(_question: string): Promise<string> {
				const next = queue.shift();
				if (next === undefined) {
					throw new Error("prompter ran out of scripted answers");
				}
				return next;
			},
			notice(msg: string): void {
				notices.push(msg);
			},
		},
	};
}

function recordingFetch() {
	const calls: {
		url: string;
		init?: RequestInit;
		body?: SyncProfileRequest;
	}[] = [];
	const fetcher: typeof fetch = async (
		input: Parameters<typeof fetch>[0],
		init?: Parameters<typeof fetch>[1],
	) => {
		const url = typeof input === "string" ? input : input.toString();
		let body: SyncProfileRequest | undefined;
		if (init?.body && typeof init.body === "string") {
			body = JSON.parse(init.body) as SyncProfileRequest;
		}
		calls.push({ url, init, body });
		return new Response(
			JSON.stringify({
				profile: {
					profile_id: body?.profile_id ?? "unknown",
					handle: body?.handle ?? "unknown",
					xp_by_source: {
						claude_code: 0,
						codex: 0,
						github: 0,
						wakatime: 0,
					},
					total_xp: 0,
					stage: 0,
					hp: 100,
					mood: "thriving",
					died_at: null,
					cause: null,
					death_count: 0,
					last_signal_at_by_source: {
						claude_code: null,
						codex: null,
						github: null,
						wakatime: null,
					},
					updated_at: Date.now(),
				},
				new_loot_events: [],
			}),
			{ status: 200, headers: { "content-type": "application/json" } },
		);
	};
	return { fetcher, calls };
}

type HookCall = { home: string; convex_http_url: string };

function recordingHooks() {
	const calls: HookCall[] = [];
	const installHooks = async (ctx: HookCall): Promise<void> => {
		calls.push(ctx);
	};
	return { installHooks, calls };
}

function makeDeps(
	answers: string[],
	home: string,
	uuid = "11111111-2222-3333-4444-555555555555",
): {
	deps: SetupDeps;
	prompterRec: ReturnType<typeof scriptedPrompter>;
	fetchRec: ReturnType<typeof recordingFetch>;
	hooksRec: ReturnType<typeof recordingHooks>;
} {
	const prompterRec = scriptedPrompter(answers);
	const fetchRec = recordingFetch();
	const hooksRec = recordingHooks();
	return {
		prompterRec,
		fetchRec,
		hooksRec,
		deps: {
			prompter: prompterRec.prompter,
			fetch: fetchRec.fetcher,
			home,
			randomUUID: () => uuid,
			installHooks: hooksRec.installHooks,
		},
	};
}

describe("runSetup", () => {
	let home: string;

	beforeEach(() => {
		home = mkdtempSync(join(tmpdir(), "codogotchi-setup-"));
	});

	afterEach(() => {
		rmSync(home, { recursive: true, force: true });
	});

	it("happy path writes config, registers profile, installs hooks", async () => {
		const { deps, fetchRec, hooksRec } = makeDeps(
			["user-1", "ghp_secret", "waka_secret", "https://example.convex.site"],
			home,
		);

		const result = await runSetup(deps);

		expect(result.config.handle).toBe("user-1");
		expect(result.config.profile_id).toBe(
			"11111111-2222-3333-4444-555555555555",
		);
		expect(result.config.github_token).toBe("ghp_secret");
		expect(result.config.wakatime_key).toBe("waka_secret");
		expect(result.config.convex_http_url).toBe("https://example.convex.site");
		expect(result.config.health.timezone).toBeString();
		expect(result.config.health.decay_per_day).toBeGreaterThan(0);

		// config persisted to disk under CODOGOTCHI_HOME
		expect(existsSync(configPath(home))).toBe(true);
		const onDisk = await readConfig(home);
		expect(onDisk?.handle).toBe("user-1");
		expect(onDisk?.profile_id).toBe(result.config.profile_id);

		// profile registered via Convex /sync with zero signals
		expect(fetchRec.calls).toHaveLength(1);
		const call = fetchRec.calls[0];
		expect(call?.url).toBe("https://example.convex.site/sync");
		expect(call?.init?.method).toBe("POST");
		expect(call?.body?.handle).toBe("user-1");
		expect(call?.body?.profile_id).toBe(result.config.profile_id);
		expect(call?.body?.signals.claude).toBeNull();
		expect(call?.body?.signals.codex).toBeNull();
		expect(call?.body?.signals.github).toBeNull();
		expect(call?.body?.signals.wakatime).toBeNull();

		// hooks installed once
		expect(hooksRec.calls).toHaveLength(1);
		expect(hooksRec.calls[0]?.home).toBe(home);
		expect(hooksRec.calls[0]?.convex_http_url).toBe(
			"https://example.convex.site",
		);
	});

	it("skipped optional credentials store as null and warn", async () => {
		const { deps, prompterRec, fetchRec } = makeDeps(
			["user-2", "", "", "https://example.convex.site"],
			home,
		);

		const result = await runSetup(deps);

		expect(result.config.github_token).toBeNull();
		expect(result.config.wakatime_key).toBeNull();

		// warning surfaced to the user
		const allNotices = prompterRec.notices.join("\n");
		expect(allNotices).toContain("GitHub");
		expect(allNotices).toContain("Wakatime");

		// still registers profile
		expect(fetchRec.calls).toHaveLength(1);
	});

	it("invalid handle re-prompts until valid", async () => {
		const { deps, prompterRec } = makeDeps(
			[
				"bad name!",
				"also bad ",
				"good-handle-2",
				"",
				"",
				"https://example.convex.site",
			],
			home,
		);

		const result = await runSetup(deps);

		expect(result.config.handle).toBe("good-handle-2");
		expect(prompterRec.notices.some((n) => /handle/i.test(n))).toBe(true);
	});

	it("refuses to overwrite pre-existing config without force", async () => {
		// First run creates the config.
		const { deps: firstDeps } = makeDeps(
			["user-3", "", "", "https://example.convex.site"],
			home,
		);
		await runSetup(firstDeps);

		// Second run without force must throw.
		const { deps: secondDeps } = makeDeps(
			["user-other", "", "", "https://example.convex.site"],
			home,
		);
		await expect(runSetup(secondDeps)).rejects.toBeInstanceOf(
			ConfigExistsError,
		);

		// Underlying config unchanged.
		const onDisk = await readConfig(home);
		expect(onDisk?.handle).toBe("user-3");
	});

	it("force overwrites pre-existing config and re-installs hooks idempotently", async () => {
		const { deps: firstDeps, hooksRec: firstHooks } = makeDeps(
			["user-a", "", "", "https://example.convex.site"],
			home,
			"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
		);
		await runSetup(firstDeps);
		expect(firstHooks.calls).toHaveLength(1);

		const { deps: secondDeps, hooksRec: secondHooks } = makeDeps(
			["user-b", "", "", "https://example.convex.site"],
			home,
			"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
		);
		const result = await runSetup(secondDeps, { force: true });
		expect(result.config.handle).toBe("user-b");
		expect(result.config.profile_id).toBe(
			"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
		);
		expect(secondHooks.calls).toHaveLength(1);

		// File reflects the second run.
		const raw = readFileSync(configPath(home), "utf8");
		const parsed = JSON.parse(raw);
		expect(parsed.handle).toBe("user-b");
	});

	it("does not write config when Convex /sync fails", async () => {
		const { prompter } = scriptedPrompter([
			"user-x",
			"",
			"",
			"https://example.convex.site",
		]);
		const failingFetch: typeof fetch = async () =>
			new Response("nope", { status: 500, statusText: "Internal Error" });
		const hooks: { calls: { home: string; convex_http_url: string }[] } = {
			calls: [],
		};
		const deps: SetupDeps = {
			prompter,
			fetch: failingFetch,
			home,
			randomUUID: () => "ffffffff-ffff-ffff-ffff-ffffffffffff",
			installHooks: async (ctx) => {
				hooks.calls.push(ctx);
			},
		};

		await expect(runSetup(deps)).rejects.toThrow(/Convex \/sync/);
		expect(existsSync(configPath(home))).toBe(false);
		expect(hooks.calls).toHaveLength(0);
	});

	it("does not write config when installHooks fails", async () => {
		const { prompter } = scriptedPrompter([
			"user-y",
			"",
			"",
			"https://example.convex.site",
		]);
		const okFetch: typeof fetch = async () =>
			new Response("{}", { status: 200 });
		const deps: SetupDeps = {
			prompter,
			fetch: okFetch,
			home,
			randomUUID: () => "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
			installHooks: async () => {
				throw new Error("boom");
			},
		};

		await expect(runSetup(deps)).rejects.toThrow(/boom/);
		expect(existsSync(configPath(home))).toBe(false);
	});
});
