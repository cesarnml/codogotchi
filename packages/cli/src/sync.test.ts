import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type {
	ProfileResponse,
	SignalsPayload,
	SyncProfileRequest,
	SyncProfileResponse,
} from "@codogotchi/contracts";
import type { CodogotchiConfig } from "./config";
import { writeConfig } from "./config";
import { profileCachePath, readProfileCache } from "./profile-cache";
import { runSync, type SourceReaders } from "./sync";
import { syncLogPath, syncLogRotationPath } from "./sync-log";

const FIXED_NOW = new Date("2026-05-18T09:30:00.000Z");

function defaultConfig(home: string): CodogotchiConfig {
	return {
		profile_id: "11111111-2222-3333-4444-555555555555",
		handle: "user-1",
		github_token: "ghp_x",
		wakatime_key: "waka_x",
		convex_http_url: "https://example.convex.site",
		health: {
			weekend_decay: false,
			grace_days: 2,
			vacation_until: null,
			timezone: "UTC",
			decay_per_day: 5,
			revive_threshold: 100,
			revive_hp: 50,
		},
	};
}

function profileResponseFixture(
	overrides?: Partial<ProfileResponse>,
): ProfileResponse {
	return {
		profile_id: "11111111-2222-3333-4444-555555555555",
		handle: "user-1",
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
		updated_at: 0,
		...overrides,
	};
}

type FetchCall = {
	url: string;
	body: SyncProfileRequest | undefined;
};

function recordingFetch(
	respond: () =>
		| { ok: true; body: SyncProfileResponse }
		| { ok: false; status: number },
) {
	const calls: FetchCall[] = [];
	const fetcher: typeof fetch = async (input, init) => {
		const url = typeof input === "string" ? input : input.toString();
		let body: SyncProfileRequest | undefined;
		if (init?.body && typeof init.body === "string") {
			body = JSON.parse(init.body) as SyncProfileRequest;
		}
		calls.push({ url, body });
		const r = respond();
		if (r.ok) {
			return new Response(JSON.stringify(r.body), {
				status: 200,
				headers: { "content-type": "application/json" },
			});
		}
		return new Response("", { status: r.status });
	};
	return { fetcher, calls };
}

function makeReaders(opts: {
	claude?: { tokens: number } | "fail";
	codex?: { tokens: number } | "fail";
	github?: { prs: SignalsPayload["github"] extends infer T ? unknown : never };
	githubFail?: boolean;
	wakatime?: { hours: number } | "fail";
}): SourceReaders {
	return {
		async claude() {
			if (opts.claude === "fail") throw new Error("claude failed");
			return opts.claude ?? null;
		},
		async codex() {
			if (opts.codex === "fail") throw new Error("codex failed");
			return opts.codex ?? null;
		},
		async github() {
			if (opts.githubFail) throw new Error("github failed");
			return { prs: [] };
		},
		async wakatime() {
			if (opts.wakatime === "fail") throw new Error("wakatime failed");
			return opts.wakatime ?? null;
		},
	};
}

describe("runSync", () => {
	let home: string;

	beforeEach(async () => {
		home = mkdtempSync(join(tmpdir(), "codogotchi-sync-"));
		await writeConfig(home, defaultConfig(home));
	});

	afterEach(() => {
		rmSync(home, { recursive: true, force: true });
	});

	it("all sources succeed: posts payload, writes profile cache, exit 0", async () => {
		const { fetcher, calls } = recordingFetch(() => ({
			ok: true,
			body: {
				profile: profileResponseFixture({ total_xp: 100, updated_at: 1 }),
				new_loot_events: [],
			},
		}));

		const result = await runSync({
			home,
			config: defaultConfig(home),
			readers: makeReaders({
				claude: { tokens: 50_000 },
				codex: { tokens: 10_000 },
				wakatime: { hours: 2 },
			}),
			fetch: fetcher,
			now: () => FIXED_NOW,
		});

		expect(result.exitCode).toBe(0);
		expect(result.postSucceeded).toBe(true);
		expect(result.errors).toHaveLength(0);
		expect(calls).toHaveLength(1);
		expect(calls[0]?.url).toBe("https://example.convex.site/sync");
		expect(calls[0]?.body?.signals.claude?.tokens).toBe(50_000);
		expect(calls[0]?.body?.signals.codex?.tokens).toBe(10_000);
		expect(calls[0]?.body?.signals.wakatime?.hours).toBe(2);
		expect(calls[0]?.body?.signals.github).not.toBeNull();
		expect(calls[0]?.body?.now).toBe(FIXED_NOW.toISOString());

		expect(existsSync(profileCachePath(home))).toBe(true);
		const cached = await readProfileCache(home);
		expect(cached?.total_xp).toBe(100);
	});

	it("one source failure does not poison others — exit 0 with error recorded", async () => {
		const { fetcher } = recordingFetch(() => ({
			ok: true,
			body: {
				profile: profileResponseFixture(),
				new_loot_events: [],
			},
		}));

		const result = await runSync({
			home,
			config: defaultConfig(home),
			readers: makeReaders({
				claude: { tokens: 1 },
				codex: { tokens: 1 },
				githubFail: true,
				wakatime: { hours: 1 },
			}),
			fetch: fetcher,
			now: () => FIXED_NOW,
		});

		expect(result.exitCode).toBe(0);
		expect(result.errors.map((e) => e.source)).toEqual(["github"]);
		expect(result.signals.github).toBeNull();
		expect(result.signals.claude?.tokens).toBe(1);
	});

	it("all sources fail but POST succeeds: exit 0", async () => {
		const { fetcher, calls } = recordingFetch(() => ({
			ok: true,
			body: {
				profile: profileResponseFixture(),
				new_loot_events: [],
			},
		}));

		const result = await runSync({
			home,
			config: defaultConfig(home),
			readers: {
				async claude() {
					throw new Error("c");
				},
				async codex() {
					throw new Error("x");
				},
				async github() {
					throw new Error("g");
				},
				async wakatime() {
					throw new Error("w");
				},
			},
			fetch: fetcher,
			now: () => FIXED_NOW,
		});

		expect(result.exitCode).toBe(0);
		expect(result.errors).toHaveLength(4);
		expect(result.signals.claude).toBeNull();
		expect(result.signals.codex).toBeNull();
		expect(result.signals.github).toBeNull();
		expect(result.signals.wakatime).toBeNull();
		expect(calls).toHaveLength(1);
		expect(calls[0]?.body?.errors).toHaveLength(4);
	});

	it("all sources fail AND POST fails: exit 1", async () => {
		const { fetcher } = recordingFetch(() => ({
			ok: false,
			status: 503,
		}));

		const result = await runSync({
			home,
			config: defaultConfig(home),
			readers: {
				async claude() {
					throw new Error("c");
				},
				async codex() {
					throw new Error("x");
				},
				async github() {
					throw new Error("g");
				},
				async wakatime() {
					throw new Error("w");
				},
			},
			fetch: fetcher,
			now: () => FIXED_NOW,
		});

		expect(result.exitCode).toBe(1);
		expect(result.postSucceeded).toBe(false);
	});

	it("since per source is derived from profile.json cache", async () => {
		const cached = profileResponseFixture({
			last_signal_at_by_source: {
				claude_code: "2026-05-15T00:00:00.000Z",
				codex: "2026-05-15T01:00:00.000Z",
				github: "2026-05-15T02:00:00.000Z",
				wakatime: "2026-05-15T03:00:00.000Z",
			},
		});
		await writeFile(profileCachePath(home), JSON.stringify(cached), "utf8");

		const seen: Record<string, string | null> = {};
		const readers: SourceReaders = {
			async claude(since) {
				seen.claude = since?.toISOString() ?? null;
				return null;
			},
			async codex(since) {
				seen.codex = since?.toISOString() ?? null;
				return null;
			},
			async github(since) {
				seen.github = since?.toISOString() ?? null;
				return null;
			},
			async wakatime(since) {
				seen.wakatime = since?.toISOString() ?? null;
				return null;
			},
		};
		const { fetcher } = recordingFetch(() => ({
			ok: true,
			body: { profile: cached, new_loot_events: [] },
		}));

		await runSync({
			home,
			config: defaultConfig(home),
			readers,
			fetch: fetcher,
			now: () => FIXED_NOW,
		});

		expect(seen.claude).toBe("2026-05-15T00:00:00.000Z");
		expect(seen.codex).toBe("2026-05-15T01:00:00.000Z");
		expect(seen.github).toBe("2026-05-15T02:00:00.000Z");
		expect(seen.wakatime).toBe("2026-05-15T03:00:00.000Z");
	});

	it("sync.log rotates when current log exceeds the limit", async () => {
		// Pre-fill sync.log past the limit.
		await mkdir(home, { recursive: true });
		const big = "x".repeat(1024);
		await writeFile(syncLogPath(home), big, "utf8");

		const { fetcher } = recordingFetch(() => ({
			ok: true,
			body: { profile: profileResponseFixture(), new_loot_events: [] },
		}));

		await runSync({
			home,
			config: defaultConfig(home),
			readers: makeReaders({
				claude: { tokens: 1 },
				codex: { tokens: 1 },
				wakatime: { hours: 1 },
			}),
			fetch: fetcher,
			now: () => FIXED_NOW,
			logSizeLimit: 512,
		});

		expect(existsSync(syncLogRotationPath(home))).toBe(true);
		const rotated = readFileSync(syncLogRotationPath(home), "utf8");
		expect(rotated.length).toBeGreaterThanOrEqual(1024);
		const current = readFileSync(syncLogPath(home), "utf8");
		expect(current).toContain("xp_delta=");
	});
});
