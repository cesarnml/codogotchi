import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type CodogotchiConfig, configPath, writeConfig } from "./config";
import {
	ConfigCommandError,
	configGet,
	configList,
	configSet,
} from "./config-command";

function fixture(): CodogotchiConfig {
	return {
		profile_id: "11111111-2222-3333-4444-555555555555",
		handle: "ada",
		github_token: "ghp_secret",
		github_username: "ada-dev",
		wakatime_key: "waka_secret",
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

describe("config command", () => {
	let home: string;

	beforeEach(async () => {
		home = mkdtempSync(join(tmpdir(), "codogotchi-cfg-"));
		await writeConfig(home, fixture());
	});

	afterEach(() => {
		rmSync(home, { recursive: true, force: true });
	});

	describe("get", () => {
		it("returns scalar values for known paths", async () => {
			expect(await configGet({ home, path: "handle" })).toBe("ada\n");
			expect(await configGet({ home, path: "health.grace_days" })).toBe("2\n");
			expect(await configGet({ home, path: "health.weekend_decay" })).toBe(
				"false\n",
			);
		});

		it("refuses unknown keys", async () => {
			await expect(configGet({ home, path: "nope" })).rejects.toBeInstanceOf(
				ConfigCommandError,
			);
			await expect(
				configGet({ home, path: "health.unknown" }),
			).rejects.toBeInstanceOf(ConfigCommandError);
		});
	});

	describe("set", () => {
		it("writes a boolean health field with type validation", async () => {
			await configSet({ home, path: "health.weekend_decay", value: "true" });
			const onDisk = JSON.parse(readFileSync(configPath(home), "utf8"));
			expect(onDisk.health.weekend_decay).toBe(true);
		});

		it("refuses a non-boolean string for a boolean field", async () => {
			await expect(
				configSet({ home, path: "health.weekend_decay", value: "yes" }),
			).rejects.toBeInstanceOf(ConfigCommandError);
		});

		it("writes a numeric health field; refuses negatives and non-numbers", async () => {
			await configSet({ home, path: "health.decay_per_day", value: "10" });
			const onDisk = JSON.parse(readFileSync(configPath(home), "utf8"));
			expect(onDisk.health.decay_per_day).toBe(10);
			await expect(
				configSet({ home, path: "health.decay_per_day", value: "-5" }),
			).rejects.toBeInstanceOf(ConfigCommandError);
			await expect(
				configSet({ home, path: "health.decay_per_day", value: "nope" }),
			).rejects.toBeInstanceOf(ConfigCommandError);
		});

		it("writes an ISO date or null for vacation_until", async () => {
			await configSet({
				home,
				path: "health.vacation_until",
				value: "2026-06-01T00:00:00Z",
			});
			let onDisk = JSON.parse(readFileSync(configPath(home), "utf8"));
			expect(onDisk.health.vacation_until).toBe("2026-06-01T00:00:00.000Z");
			await configSet({ home, path: "health.vacation_until", value: "null" });
			onDisk = JSON.parse(readFileSync(configPath(home), "utf8"));
			expect(onDisk.health.vacation_until).toBeNull();
			await expect(
				configSet({ home, path: "health.vacation_until", value: "tomorrow" }),
			).rejects.toBeInstanceOf(ConfigCommandError);
		});

		it("refuses unknown keys and read-only keys", async () => {
			await expect(
				configSet({ home, path: "foo.bar", value: "baz" }),
			).rejects.toBeInstanceOf(ConfigCommandError);
			await expect(
				configSet({ home, path: "profile_id", value: "x" }),
			).rejects.toBeInstanceOf(ConfigCommandError);
		});

		it("validates convex_http_url is an https URL", async () => {
			await configSet({
				home,
				path: "convex_http_url",
				value: "https://new.convex.site/",
			});
			const onDisk = JSON.parse(readFileSync(configPath(home), "utf8"));
			expect(onDisk.convex_http_url).toBe("https://new.convex.site");
			await expect(
				configSet({
					home,
					path: "convex_http_url",
					value: "http://insecure.example",
				}),
			).rejects.toBeInstanceOf(ConfigCommandError);
		});

		it("allows clearing nullable secrets via 'null' literal", async () => {
			await configSet({ home, path: "github_token", value: "null" });
			const onDisk = JSON.parse(readFileSync(configPath(home), "utf8"));
			expect(onDisk.github_token).toBeNull();
		});
	});

	describe("list", () => {
		it("redacts credentials when set; preserves null when unset", async () => {
			let out = await configList({ home });
			expect(out).not.toContain("ghp_secret");
			expect(out).not.toContain("waka_secret");
			expect(out).toContain('"github_token": "<set>"');
			expect(out).toContain('"wakatime_key": "<set>"');
			expect(out).toContain('"handle": "ada"');

			await configSet({ home, path: "github_token", value: "null" });
			out = await configList({ home });
			expect(out).toContain('"github_token": null');
		});
	});

	describe("missing config", () => {
		it("errors with exit code 2 hint when config missing", async () => {
			const empty = mkdtempSync(join(tmpdir(), "codogotchi-cfg-empty-"));
			try {
				const promise = configGet({ home: empty, path: "handle" });
				await expect(promise).rejects.toBeInstanceOf(ConfigCommandError);
				try {
					await promise;
				} catch (err) {
					expect((err as ConfigCommandError).exitCode).toBe(2);
				}
			} finally {
				rmSync(empty, { recursive: true, force: true });
			}
		});
	});
});
