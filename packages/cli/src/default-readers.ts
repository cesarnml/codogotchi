import { homedir } from "node:os";
import { join } from "node:path";
import {
  readGithubSignals,
  readJsonlSignals,
  readWakatimeSignals,
} from "@codogotchi/engine";
import { type CodogotchiConfig, getCodogotchiHome } from "./config";
import { appendScorePRLog } from "./score-pr-log";
import type { SourceReaders } from "./sync";

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

/** Forward-only: first read for a source starts at `now`, not a historical window. */
function forwardSince(since: Date | null, now: Date): Date {
  return since ?? now;
}

// Default readers wrap the engine source clients with the config-driven
// credentials and per-source defaults. A source returns null when it is not
// configured (e.g. no token, no key) so the heartbeat sync still goes through.
export function defaultReaders(config: CodogotchiConfig): SourceReaders {
  return {
    async claude(since, now) {
      const sinceDate = forwardSince(since, now);
      try {
        const set = await readJsonlSignals({
          source: "claude",
          rootDir: claudeRoot(),
          since: sinceDate,
        });
        if (set.totalTokens <= 0) return null;
        return { tokens: set.totalTokens };
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
        throw err;
      }
    },
    async codex(since, now) {
      const sinceDate = forwardSince(since, now);
      try {
        const set = await readJsonlSignals({
          source: "codex",
          rootDir: codexRoot(),
          since: sinceDate,
        });
        if (set.totalTokens <= 0) return null;
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
      const scoredAt = now.toISOString();
      const scorePRHome = getCodogotchiHome();
      for (const pr of set.prs) {
        // Best-effort: never block sync on a log write failure.
        try {
          await appendScorePRLog(scorePRHome, {
            at: scoredAt,
            pr_number: pr.number,
            pr_url: pr.htmlUrl ?? null,
            title: pr.title,
            additions: pr.additions,
            deletions: pr.deletions,
            review_comment_count: pr.reviewCommentCount,
            score: pr.score,
            explanation: pr.scoreExplanation,
          });
        } catch {
          // Swallow: sync correctness must not depend on log I/O.
        }
      }
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
      const sinceDate = forwardSince(since, now);
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
      if (set.totalHours <= 0) return null;
      return { hours: set.totalHours };
    },
  };
}
