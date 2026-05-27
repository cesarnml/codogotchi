import { open, stat } from "node:fs/promises";
import { join } from "node:path";
import { type SoaEventLine, soaEventLineSchema } from "@codogotchi/contracts";

const SOA_EVENTS_REL = join(".soa", "events.ndjson");

export type SoaTailState = {
  /** inode if available; null on filesystems where it is not reliable */
  inode: number | null;
  /** byte offset into the events file */
  offset: number;
};

export type ReadSoaEventsResult = {
  events: SoaEventLine[];
  tail: SoaTailState | null;
};

export type SoaPathEnv = {
  CLAUDE_PROJECT_DIR?: string;
  CODEX_PROJECT_DIR?: string;
  CWD?: string;
};

/**
 * Resolve the project root for the SoA event feed. Priority:
 *   1. $CLAUDE_PROJECT_DIR
 *   2. $CODEX_PROJECT_DIR
 *   3. cwd (passed in as `CWD` for testability)
 *
 * `events.ndjson` is then read from `${root}/.soa/events.ndjson`.
 */
export function resolveSoaRoot(env: SoaPathEnv): string | null {
  if (env.CLAUDE_PROJECT_DIR && env.CLAUDE_PROJECT_DIR.length > 0) {
    return env.CLAUDE_PROJECT_DIR;
  }
  if (env.CODEX_PROJECT_DIR && env.CODEX_PROJECT_DIR.length > 0) {
    return env.CODEX_PROJECT_DIR;
  }
  if (env.CWD && env.CWD.length > 0) return env.CWD;
  return null;
}

export function soaEventsPath(rootDir: string): string {
  return join(rootDir, SOA_EVENTS_REL);
}

/**
 * Tail-read `.soa/events.ndjson` since the previous tail state. Defensive by
 * design: a missing file returns no events and no tail; malformed lines are
 * skipped silently; an inode mismatch (file rotation/truncation) resets the
 * offset to zero so the new contents are read in full.
 *
 * Pure I/O — no logging, no throwing on absent files. The consumer (hook
 * binary) decides what to do with the events and the new tail state.
 */
export async function readSoaEventsSince(
  rootDir: string,
  prev: SoaTailState | null,
): Promise<ReadSoaEventsResult> {
  const target = soaEventsPath(rootDir);
  let stats: Awaited<ReturnType<typeof stat>>;
  try {
    stats = await stat(target);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { events: [], tail: null };
    }
    return { events: [], tail: null };
  }

  const inode = typeof stats.ino === "number" ? stats.ino : null;
  const size = stats.size;
  let startOffset = 0;
  if (prev !== null) {
    const inodeMatches =
      prev.inode === null || inode === null || prev.inode === inode;
    if (inodeMatches && prev.offset <= size) {
      startOffset = prev.offset;
    }
  }

  if (startOffset === size) {
    return { events: [], tail: { inode, offset: size } };
  }

  const bytesToRead = size - startOffset;
  let raw = "";
  try {
    const handle = await open(target, "r");
    try {
      const buffer = Buffer.alloc(bytesToRead);
      await handle.read(buffer, 0, bytesToRead, startOffset);
      raw = buffer.toString("utf8");
    } finally {
      await handle.close();
    }
  } catch {
    return { events: [], tail: prev };
  }

  const events: SoaEventLine[] = [];
  const lines = raw.split("\n");
  // Track the last newline-terminated byte we successfully consumed so a
  // trailing partial line does not advance the tail past its own start.
  let consumedBytes = 0;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i] ?? "";
    const isLast = i === lines.length - 1;
    if (isLast) {
      // The trailing element after split("\n") is the leftover after the
      // last newline. If it is non-empty, we treat it as a partial line
      // and do not advance past its start. If empty, the file ended with
      // a newline and consumedBytes is already correct.
      break;
    }
    consumedBytes += Buffer.byteLength(line, "utf8") + 1; // +1 for "\n"
    if (line.length === 0) continue;
    let parsedJson: unknown;
    try {
      parsedJson = JSON.parse(line);
    } catch {
      continue;
    }
    const parsed = soaEventLineSchema.safeParse(parsedJson);
    if (!parsed.success) continue;
    events.push(parsed.data);
  }

  return {
    events,
    tail: { inode, offset: startOffset + consumedBytes },
  };
}

export type WatchSoaEventsOptions = {
  intervalMs?: number;
  signal?: AbortSignal;
};

/**
 * Long-running poll wrapper around `readSoaEventsSince`. The hook binary does
 * not use this — it is for any future renderer that wants to subscribe to the
 * stream. Stops cleanly when the optional AbortSignal fires.
 */
export async function watchSoaEvents(
  rootDir: string,
  onEvent: (event: SoaEventLine) => void,
  opts: WatchSoaEventsOptions = {},
): Promise<void> {
  const interval = opts.intervalMs ?? 250;
  let tail: SoaTailState | null = null;
  while (opts.signal?.aborted !== true) {
    const result = await readSoaEventsSince(rootDir, tail);
    tail = result.tail;
    for (const event of result.events) onEvent(event);
    await new Promise<void>((resolve) => setTimeout(resolve, interval));
  }
}
