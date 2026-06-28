import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  type LootEventResponse,
  type ProfileResponse,
  STATE_JSON_SCHEMA_VERSION,
  type StateJsonV1,
} from "@codogotchi/contracts";
import { lootLogPath } from "./loot";
import { profileCachePath, runStatus, sliceDirPath } from "./status";

const NOW = new Date("2026-05-18T10:00:00.000Z");
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

function profileFixture(overrides?: Partial<ProfileResponse>): ProfileResponse {
  return {
    profile_id: "11111111-2222-3333-4444-555555555555",
    handle: "ada",
    xp_by_source: {
      claude_code: 12345,
      codex: 678,
      github: 9000,
      wakatime: 4321,
    },
    total_xp: 26344,
    stage: 3,
    hp: 87,
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
    updated_at: NOW.getTime() - 60_000, // 1 min ago
    ...overrides,
  };
}

function stateFixture(overrides?: Partial<StateJsonV1>): StateJsonV1 {
  return {
    schema_version: STATE_JSON_SCHEMA_VERSION,
    activity_state: "implementing",
    hp_overlay: "thriving",
    hp: 87,
    updated_at: NOW.toISOString(),
    source_event: {
      origin: "claude_code",
      kind: "tool_use",
      name: "Write",
    },
    ...overrides,
  };
}

describe("runStatus", () => {
  let home: string;

  beforeEach(async () => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-status-"));
    await mkdir(home, { recursive: true });
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("missing profile.json prints a helpful setup hint", async () => {
    const result = await runStatus({ home, now: () => NOW });
    expect(result.missingProfile).toBe(true);
    expect(result.output).toContain("codogotchi setup");
  });

  it("corrupt profile.json is treated as missing", async () => {
    await writeFile(profileCachePath(home), "{bad json", "utf8");
    const result = await runStatus({ home, now: () => NOW });
    expect(result.missingProfile).toBe(true);
    expect(result.output).toContain("codogotchi setup");
  });

  it("renders full populated cache with state and loot", async () => {
    const profile = profileFixture();
    await writeFile(profileCachePath(home), JSON.stringify(profile), "utf8");
    // Write a slice file so runStatus can read it via globalAggregate.
    const sliceDir = sliceDirPath(home);
    await mkdir(sliceDir, { recursive: true });
    await writeFile(
      join(sliceDir, "claude_code:ses-test.json"),
      JSON.stringify({
        origin: "claude_code",
        session_id: "ses-test",
        ...stateFixture(),
      }),
      "utf8",
    );
    const lootEvents: LootEventResponse[] = [
      {
        profile_id: profile.profile_id,
        tier: "common",
        name: "lucky-bash",
        source: "claude_code",
        score_explanation: null,
        ts: NOW.getTime() - 60_000,
      },
      {
        profile_id: profile.profile_id,
        tier: "rare",
        name: "Pull Master",
        source: "github",
        score_explanation: null,
        ts: NOW.getTime() - 30_000,
      },
    ];
    await writeFile(
      lootLogPath(home),
      lootEvents.map((e) => JSON.stringify(e)).join("\n"),
      "utf8",
    );

    const result = await runStatus({ home, now: () => NOW });
    expect(result.missingProfile).toBe(false);
    expect(result.output).toContain("@ada");
    expect(result.output).toContain("stage 3");
    expect(result.output).toContain("12,345");
    expect(result.output).toContain("thriving");
    expect(result.output).toContain("implementing");
    expect(result.output).toContain("Pull Master");
    expect(result.output).toContain("lucky-bash");
    expect(result.output).not.toContain("stale");
  });

  it("missing state.json is omitted from the output (no stack trace)", async () => {
    await writeFile(
      profileCachePath(home),
      JSON.stringify(profileFixture()),
      "utf8",
    );
    const result = await runStatus({ home, now: () => NOW });
    expect(result.missingProfile).toBe(false);
    expect(result.output).not.toContain("activity=");
    expect(result.output).toContain("@ada");
  });

  it("flags stale last-sync when older than 24h", async () => {
    const profile = profileFixture({
      updated_at: NOW.getTime() - ONE_DAY_MS - 1,
    });
    await writeFile(profileCachePath(home), JSON.stringify(profile), "utf8");
    const result = await runStatus({ home, now: () => NOW });
    expect(result.output).toContain("stale");
  });

  it("does not flag stale last-sync at the exact 24h boundary", async () => {
    const profile = profileFixture({
      updated_at: NOW.getTime() - ONE_DAY_MS,
    });
    await writeFile(profileCachePath(home), JSON.stringify(profile), "utf8");
    const result = await runStatus({ home, now: () => NOW });
    expect(result.output).toContain("Last sync:");
    expect(result.output).not.toContain("stale");
  });

  it("skips malformed loot.log lines and invalid timestamps", async () => {
    await writeFile(
      profileCachePath(home),
      JSON.stringify(profileFixture()),
      "utf8",
    );
    const bogus = [
      "not-json",
      JSON.stringify({ tier: "common", name: "no-ts", source: "claude_code" }),
      JSON.stringify({
        profile_id: "p",
        tier: "rare",
        name: "ok",
        source: "github",
        score_explanation: null,
        ts: NOW.getTime() - 1000,
      }),
      JSON.stringify({
        tier: "epic",
        name: "bad-ts",
        source: "codex",
        ts: "x",
      }),
    ].join("\n");
    await writeFile(lootLogPath(home), bogus, "utf8");
    const result = await runStatus({ home, now: () => NOW });
    expect(result.output).toContain("ok");
    expect(result.output).not.toContain("no-ts");
    expect(result.output).not.toContain("bad-ts");
  });

  it("renders died_at and death count when set", async () => {
    const profile = profileFixture({
      died_at: "2026-05-17T00:00:00.000Z",
      cause: "decay",
      death_count: 1,
      mood: "ghost",
      hp: 0,
    });
    await writeFile(profileCachePath(home), JSON.stringify(profile), "utf8");
    const result = await runStatus({ home, now: () => NOW });
    expect(result.output).toContain("Died at 2026-05-17T00:00:00.000Z");
    expect(result.output).toContain("decay");
    expect(result.output).toContain("death count 1");
  });
});

// ---------------------------------------------------------------------------
// P12.02 Red tests — status reads from state.d/ via globalAggregate
// Imports sliceDirPath which does not exist yet; MUST fail until implemented.
// ---------------------------------------------------------------------------
describe("runStatus reads from state.d/ slice directory (P12.02 red)", () => {
  let home: string;

  beforeEach(async () => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-status-slice-"));
    await mkdir(home, { recursive: true });
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("sliceDirPath returns the expected state.d directory path", () => {
    const dir = sliceDirPath(home);
    expect(dir).toContain("state.d");
    expect(dir.startsWith(home)).toBe(true);
  });

  it("runStatus reads N slices and renders the globalAggregate activity state", async () => {
    const profile = profileFixture();
    await writeFile(profileCachePath(home), JSON.stringify(profile), "utf8");

    // Write two slice files directly into state.d/
    const dir = sliceDirPath(home);
    await mkdir(dir, { recursive: true });

    const olderSlice = {
      schema_version: STATE_JSON_SCHEMA_VERSION,
      origin: "codex",
      session_id: "ses-codex-old",
      activity_state: "idle",
      hp_overlay: "thriving",
      hp: 80,
      updated_at: new Date(NOW.getTime() - 60_000).toISOString(),
      source_event: { origin: "codex", kind: "tool_use", name: "Read" },
    };
    const newerSlice = {
      schema_version: STATE_JSON_SCHEMA_VERSION,
      origin: "claude_code",
      session_id: "ses-claude-new",
      activity_state: "implementing",
      hp_overlay: "thriving",
      hp: 90,
      updated_at: NOW.toISOString(),
      source_event: { origin: "claude_code", kind: "tool_use", name: "Write" },
    };

    await writeFile(
      join(dir, "codex:ses-codex-old.json"),
      JSON.stringify(olderSlice),
      "utf8",
    );
    await writeFile(
      join(dir, "claude_code:ses-claude-new.json"),
      JSON.stringify(newerSlice),
      "utf8",
    );

    const result = await runStatus({ home, now: () => NOW });
    expect(result.missingProfile).toBe(false);
    // globalAggregate picks the most-recent slice (claude_code, implementing)
    expect(result.output).toContain("implementing");
    // Must NOT fall through to stateJsonPath
    expect(existsSync(join(home, "state.json"))).toBe(false);
  });
});
