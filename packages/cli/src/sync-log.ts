import { appendFile, mkdir, rename, stat } from "node:fs/promises";
import { join } from "node:path";

export const DEFAULT_SYNC_LOG_LIMIT_BYTES = 10 * 1024 * 1024;

export function syncLogPath(home: string): string {
  return join(home, "sync.log");
}

export function syncLogRotationPath(home: string): string {
  return join(home, "sync.log.1");
}

export type SyncLogEntry = {
  at: string;
  per_source: Record<string, "ok" | "error">;
  xp_delta: number;
  new_loot: number;
};

export function formatSyncLogEntry(entry: SyncLogEntry): string {
  const sources = Object.entries(entry.per_source)
    .map(([name, status]) => `${name}=${status}`)
    .join(" ");
  return `${entry.at} ${sources} xp_delta=${entry.xp_delta} new_loot=${entry.new_loot}\n`;
}

export async function appendSyncLog(
  home: string,
  entry: SyncLogEntry,
  limitBytes: number = DEFAULT_SYNC_LOG_LIMIT_BYTES,
): Promise<void> {
  await mkdir(home, { recursive: true });
  const target = syncLogPath(home);
  try {
    const info = await stat(target);
    if (info.size >= limitBytes) {
      await rename(target, syncLogRotationPath(home));
    }
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
  }
  await appendFile(target, formatSyncLogEntry(entry), "utf8");
}
