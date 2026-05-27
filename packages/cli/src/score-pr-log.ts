import { appendFile, mkdir, rename, stat } from "node:fs/promises";
import { join } from "node:path";

/**
 * `scorePR` decisions are written as one JSON line per PR scoring to
 * `~/.codogotchi/scorePR.log`. The file mirrors `sync.log`'s rotation
 * behavior — when it crosses 10 MiB it is rotated to `scorePR.log.1` and a
 * fresh file is opened. Append-only by design so a partial write never
 * corrupts older entries.
 */
export const DEFAULT_SCORE_PR_LOG_LIMIT_BYTES = 10 * 1024 * 1024;

export function scorePRLogPath(home: string): string {
  return join(home, "scorePR.log");
}

export function scorePRLogRotationPath(home: string): string {
  return join(home, "scorePR.log.1");
}

export type ScorePRLogEntry = {
  at: string;
  pr_number: number;
  pr_url: string | null;
  title: string;
  additions: number;
  deletions: number;
  review_comment_count: number;
  score: number;
  explanation: string;
};

export function formatScorePRLogEntry(entry: ScorePRLogEntry): string {
  return `${JSON.stringify(entry)}\n`;
}

export async function appendScorePRLog(
  home: string,
  entry: ScorePRLogEntry,
  limitBytes: number = DEFAULT_SCORE_PR_LOG_LIMIT_BYTES,
): Promise<void> {
  await mkdir(home, { recursive: true });
  const target = scorePRLogPath(home);
  try {
    const info = await stat(target);
    if (info.size >= limitBytes) {
      await rename(target, scorePRLogRotationPath(home));
    }
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
  }
  await appendFile(target, formatScorePRLogEntry(entry), "utf8");
}
