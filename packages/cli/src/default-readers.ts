import { homedir } from "node:os";
import { join } from "node:path";
import {
	readGithubSignals,
	readJsonlSignals,
	readWakatimeSignals,
} from "@codogotchi/engine";
import type { CodogotchiConfig } from "./config";
import type { SourceReaders } from "./sync";

const NINETY_DAYS_MS = 90 * 24 * 60 * 60 * 1000;

function claudeRoot(): string {
	return (
		process.env.CODOGOTCHI_CLAUDE_ROOT ?? join(homedir(), ".claude", "projects")
	);
}

function codexRoot(): string {
	return (
		process.env.CODOGOTCHI_CODEX_ROOT ?? join(homedir(), ".codex", "sessions")
	);
}

// Default readers wrap the engine source clients with the config-driven
// credentials and per-source defaults. A source returns null when it is not
// configured (e.g. no token, no key) so the heartbeat sync still goes through.
export function defaultReaders(config: CodogotchiConfig): SourceReaders {
	return {
		async claude(since, now) {
			const sinceDate = since ?? new Date(now.getTime() - NINETY_DAYS_MS);
			try {
				const set = await readJsonlSignals({
					source: "claude",
					rootDir: claudeRoot(),
					since: sinceDate,
				});
				return { tokens: set.totalTokens };
			} catch (err) {
				if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
				throw err;
			}
		},
		async codex(since, now) {
			const sinceDate = since ?? new Date(now.getTime() - NINETY_DAYS_MS);
			try {
				const set = await readJsonlSignals({
					source: "codex",
					rootDir: codexRoot(),
					since: sinceDate,
				});
				return { tokens: set.totalTokens };
			} catch (err) {
				if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
				throw err;
			}
		},
		async github(since, now) {
			if (!config.github_token || !config.github_username) return null;
			const set = await readGithubSignals({
				token: config.github_token,
				username: config.github_username,
				since,
				now,
			});
			// The engine returns `rateLimitHit: true` (and empty PRs) when the
			// GitHub API soft-failed. Surface that as a source error so it shows
			// up in the sync `errors[]` rather than masquerading as zero activity.
			if (set.rateLimitHit) throw new Error("GitHub rate limit hit");
			return {
				prs: set.prs.map((pr) => ({
					number: pr.number,
					title: pr.title,
					additions: pr.additions,
					deletions: pr.deletions,
					reviewCommentCount: pr.reviewCommentCount,
				})),
			};
		},
		async wakatime(since, now) {
			if (!config.wakatime_key) return null;
			const sinceDate = since ?? new Date(now.getTime() - NINETY_DAYS_MS);
			const set = await readWakatimeSignals({
				apiKey: config.wakatime_key,
				since: sinceDate,
				now,
			});
			// The engine surfaces HTTP/parse failures via `error` rather than
			// throwing. Convert that to a real throw so per-source isolation in
			// runSync records it in `errors[]` instead of treating a possibly
			// partial `totalHours` as a clean signal.
			if (set.error !== null) throw new Error(`Wakatime: ${set.error}`);
			return { hours: set.totalHours };
		},
	};
}
