import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type CodogotchiConfig, configPath, writeConfig } from "./config";
import { ConfigCommandError } from "./config-command";
import {
	VACATION_DEFAULT_DAYS,
	vacationOff,
	vacationOn,
	vacationStatus,
} from "./vacation";

const NOW = new Date("2026-05-18T00:00:00.000Z");

function fixture(overrides: Partial<CodogotchiConfig> = {}): CodogotchiConfig {
	return {
		profile_id: "p",
		handle: "ada",
		github_token: null,
		github_username: null,
		wakatime_key: null,
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
		...overrides,
	};
}

function diskHealth(home: string): CodogotchiConfig["health"] {
	return JSON.parse(readFileSync(configPath(home), "utf8")).health;
}

describe("vacation command", () => {
	let home: string;

	beforeEach(async () => {
		home = mkdtempSync(join(tmpdir(), "codogotchi-vac-"));
		await writeConfig(home, fixture());
	});

	afterEach(() => {
		rmSync(home, { recursive: true, force: true });
	});

	it("on without --until defaults to 30 days from now", async () => {
		const out = await vacationOn({ home, now: () => NOW });
		expect(out).toContain("vacation on until");
		const stored = diskHealth(home).vacation_until;
		expect(stored).toBeTypeOf("string");
		const t = Date.parse(stored as string);
		const expected =
			NOW.getTime() + VACATION_DEFAULT_DAYS * 24 * 60 * 60 * 1000;
		// Allow a 1s tolerance for now()-vs-stored serialization.
		expect(Math.abs(t - expected)).toBeLessThan(1000);
	});

	it("on with --until writes the exact ISO date (midnight UTC)", async () => {
		await vacationOn({ home, now: () => NOW }, { until: "2026-06-15" });
		expect(diskHealth(home).vacation_until).toBe("2026-06-15T00:00:00.000Z");
	});

	it("off clears vacation_until to null", async () => {
		await writeConfig(
			home,
			fixture({
				health: {
					...fixture().health,
					vacation_until: "2026-06-15T00:00:00.000Z",
				},
			}),
		);
		const out = await vacationOff({ home, now: () => NOW });
		expect(out).toContain("vacation off");
		expect(diskHealth(home).vacation_until).toBeNull();
	});

	it("status renders off when vacation_until is null", async () => {
		const out = await vacationStatus({ home, now: () => NOW });
		expect(out).toContain("vacation off");
	});

	it("status renders on with days remaining when vacation_until is set", async () => {
		await writeConfig(
			home,
			fixture({
				health: {
					...fixture().health,
					vacation_until: "2026-06-15T00:00:00.000Z",
				},
			}),
		);
		const out = await vacationStatus({ home, now: () => NOW });
		expect(out).toContain("vacation on until 2026-06-15T00:00:00.000Z");
		expect(out).toContain("28 days remaining");
	});

	it("rejects invalid date format", async () => {
		await expect(
			vacationOn({ home, now: () => NOW }, { until: "2026-13-45" }),
		).rejects.toBeInstanceOf(ConfigCommandError);
		await expect(
			vacationOn({ home, now: () => NOW }, { until: "tomorrow" }),
		).rejects.toBeInstanceOf(ConfigCommandError);
	});
});
