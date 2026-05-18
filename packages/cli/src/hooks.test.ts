import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { installHooks } from "./hooks";

describe("installHooks", () => {
	let userRoot: string;
	let prevUserRoot: string | undefined;
	let prevHome: string | undefined;

	beforeEach(() => {
		userRoot = mkdtempSync(join(tmpdir(), "codogotchi-hooks-"));
		prevUserRoot = process.env.CODOGOTCHI_USER_ROOT;
		prevHome = process.env.CODOGOTCHI_HOME;
		process.env.CODOGOTCHI_USER_ROOT = userRoot;
	});

	afterEach(() => {
		rmSync(userRoot, { recursive: true, force: true });
		if (prevUserRoot === undefined) delete process.env.CODOGOTCHI_USER_ROOT;
		else process.env.CODOGOTCHI_USER_ROOT = prevUserRoot;
		if (prevHome === undefined) delete process.env.CODOGOTCHI_HOME;
		else process.env.CODOGOTCHI_HOME = prevHome;
	});

	it("writes Claude Code and Codex hook entries pointing at codogotchi-hook", async () => {
		await installHooks({
			home: "/home/user/.codogotchi",
			convex_http_url: "https://example.convex.site",
		});

		const claudeRaw = readFileSync(
			join(userRoot, ".claude", "settings.json"),
			"utf8",
		);
		const claude = JSON.parse(claudeRaw) as {
			hooks: {
				codogotchi: { command: string; env: Record<string, string> };
			};
		};
		expect(claude.hooks.codogotchi.command).toBe("codogotchi-hook");
		expect(claude.hooks.codogotchi.env.CODOGOTCHI_HOME).toBe(
			"/home/user/.codogotchi",
		);
		expect(claude.hooks.codogotchi.env.CODOGOTCHI_CONVEX_URL).toBe(
			"https://example.convex.site",
		);

		const codexRaw = readFileSync(
			join(userRoot, ".codex", "hooks", "codogotchi.toml"),
			"utf8",
		);
		expect(codexRaw).toContain('command = "codogotchi-hook"');
		expect(codexRaw).toContain('CODOGOTCHI_HOME = "/home/user/.codogotchi"');
		expect(codexRaw).toContain(
			'CODOGOTCHI_CONVEX_URL = "https://example.convex.site"',
		);
	});

	it("preserves unrelated entries in an existing Claude settings file", async () => {
		await mkdir(join(userRoot, ".claude"), { recursive: true });
		writeFileSync(
			join(userRoot, ".claude", "settings.json"),
			JSON.stringify(
				{
					theme: "dark",
					hooks: { other: { command: "other-cmd" } },
				},
				null,
				2,
			),
			"utf8",
		);

		await installHooks({
			home: "/home/user/.codogotchi",
			convex_http_url: "https://example.convex.site",
		});

		const claude = JSON.parse(
			readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
		) as {
			theme: string;
			hooks: Record<string, { command: string }>;
		};
		expect(claude.theme).toBe("dark");
		expect(claude.hooks.other?.command).toBe("other-cmd");
		expect(claude.hooks.codogotchi?.command).toBe("codogotchi-hook");
	});

	it("is idempotent — re-running yields identical files", async () => {
		const ctx = {
			home: "/home/user/.codogotchi",
			convex_http_url: "https://example.convex.site",
		};
		await installHooks(ctx);
		const claudeFirst = readFileSync(
			join(userRoot, ".claude", "settings.json"),
			"utf8",
		);
		const codexFirst = readFileSync(
			join(userRoot, ".codex", "hooks", "codogotchi.toml"),
			"utf8",
		);

		await installHooks(ctx);
		const claudeSecond = readFileSync(
			join(userRoot, ".claude", "settings.json"),
			"utf8",
		);
		const codexSecond = readFileSync(
			join(userRoot, ".codex", "hooks", "codogotchi.toml"),
			"utf8",
		);

		expect(claudeSecond).toBe(claudeFirst);
		expect(codexSecond).toBe(codexFirst);
	});
});
