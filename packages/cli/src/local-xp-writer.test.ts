import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  computeAndPersistV5Fields,
  type LocalXpCache,
  readLocalXpCache,
  writeLocalXpCache,
} from "./local-xp-writer";

// The revive animation plays while `now < revive_until`. The writer arms a 5s
// window on a half-heart gain, but state.json is rewritten on *every* hook event
// — so the window must survive the frequent non-gain writes that follow during
// active coding, or the renderer's 1Hz poll never catches it (the bug that made
// revive only ever show at full health). These tests pin that live-mode behavior.
describe("computeAndPersistV5Fields — revive_until window", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "cdg-revive-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  async function seed(overrides: Partial<LocalXpCache>): Promise<void> {
    const base: LocalXpCache = {
      cumulative_claude_tokens: 0,
      cumulative_codex_tokens: 0,
      last_read_at_claude: null,
      last_read_at_codex: null,
      last_activity_at: null,
      last_active_credit_at: null,
      active_minutes: 0,
      half_hearts: 6,
      revive_until: null,
    };
    await writeLocalXpCache(home, { ...base, ...overrides });
  }

  it("arms revive_until for 5s on a half-heart gain and persists it to the cache", async () => {
    const now = new Date("2026-06-08T12:00:00.000Z");
    // Dead pet one active-minute shy of a heal, with the credit gate already open
    // (last credit > 60s ago) so this event crosses the 60-minute heal threshold.
    await seed({
      half_hearts: 0,
      active_minutes: 59,
      last_active_credit_at: new Date(now.getTime() - 61_000).toISOString(),
      last_activity_at: new Date(now.getTime() - 61_000).toISOString(),
    });

    // cursor is a non-token origin → no JSONL read; isolates the heal/revive path.
    const v5 = await computeAndPersistV5Fields(home, "cursor", now);

    expect(v5.half_hearts).toBe(1);
    expect(v5.revive_until).toBe(new Date(now.getTime() + 5_000).toISOString());
    // Persisted so subsequent non-gain writes can preserve the same window.
    expect((await readLocalXpCache(home)).revive_until).toBe(v5.revive_until);
  });

  it("preserves an unexpired revive_until on a non-gain write", async () => {
    const now = new Date("2026-06-08T12:00:00.000Z");
    const armed = new Date(now.getTime() + 5_000).toISOString();
    // Full pet (no gain possible), window armed 5s out, recent activity.
    await seed({
      half_hearts: 6,
      active_minutes: 0,
      last_activity_at: new Date(now.getTime() - 1_000).toISOString(),
      last_active_credit_at: new Date(now.getTime() - 1_000).toISOString(),
      revive_until: armed,
    });

    // A non-gain write 2s into the window must keep it, not null it.
    const v5 = await computeAndPersistV5Fields(
      home,
      "cursor",
      new Date(now.getTime() + 2_000),
    );

    expect(v5.half_hearts).toBe(6);
    expect(v5.revive_until).toBe(armed);
  });

  it("clears revive_until once the window has lapsed", async () => {
    const now = new Date("2026-06-08T12:00:00.000Z");
    // Window expiry already in the past.
    await seed({
      half_hearts: 6,
      active_minutes: 0,
      last_activity_at: new Date(now.getTime() - 1_000).toISOString(),
      last_active_credit_at: new Date(now.getTime() - 1_000).toISOString(),
      revive_until: new Date(now.getTime() - 1_000).toISOString(),
    });

    const v5 = await computeAndPersistV5Fields(home, "cursor", now);

    expect(v5.revive_until).toBeNull();
    expect((await readLocalXpCache(home)).revive_until).toBeNull();
  });
});
