import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SyncProfileRequest } from "@codogotchi/contracts";
import { configPath, readConfig, writeConfig } from "./config";
// runRpg does not exist yet → RED: this import will fail until Green
import { ConfigExistsError, runRpg, runSetup } from "./setup";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function scriptedPrompter(answers: string[]) {
  const queue = [...answers];
  const notices: string[] = [];
  return {
    notices,
    prompter: {
      async ask(_question: string): Promise<string> {
        const next = queue.shift();
        if (next === undefined) throw new Error("prompter ran out of answers");
        return next;
      },
      notice(msg: string): void {
        notices.push(msg);
      },
    },
  };
}

function recordingFetch() {
  const calls: {
    url: string;
    init?: RequestInit;
    body?: SyncProfileRequest;
  }[] = [];
  const fetcher: typeof fetch = async (
    input: Parameters<typeof fetch>[0],
    init?: Parameters<typeof fetch>[1],
  ) => {
    const url = typeof input === "string" ? input : input.toString();
    let body: SyncProfileRequest | undefined;
    if (init?.body && typeof init.body === "string") {
      body = JSON.parse(init.body) as SyncProfileRequest;
    }
    calls.push({ url, init, body });
    return new Response(
      JSON.stringify({
        profile: {
          profile_id: body?.profile_id ?? "unknown",
          handle: body?.handle ?? "unknown",
          xp_by_source: {
            claude_code: 0,
            codex: 0,
            github: 0,
            wakatime: 0,
          },
          total_xp: 0,
          stage: 0,
          hp: 100,
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
          updated_at: Date.now(),
        },
        new_loot_events: [],
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  return { fetcher, calls };
}

// Lite setup deps — no prompter, no fetch
function makeLiteDeps(
  home: string,
  uuid = "11111111-2222-3333-4444-555555555555",
) {
  const hookCalls: { home: string }[] = [];
  return {
    hookCalls,
    deps: {
      home,
      randomUUID: () => uuid,
      installHooks: async (ctx: { home: string }) => {
        hookCalls.push(ctx);
      },
    },
  };
}

// RPG enrollment deps — prompts + fetch, no installHooks
function makeRpgDeps(
  answers: string[],
  home: string,
  uuid = "11111111-2222-3333-4444-555555555555",
) {
  const prompterRec = scriptedPrompter(answers);
  const fetchRec = recordingFetch();
  return {
    prompterRec,
    fetchRec,
    deps: {
      prompter: prompterRec.prompter,
      fetch: fetchRec.fetcher,
      home,
      randomUUID: () => uuid,
    },
  };
}

// ---------------------------------------------------------------------------
// runSetup (Lite)
// ---------------------------------------------------------------------------

describe("runSetup (Lite)", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-lite-setup-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("greenfield: writes local-RPG config (rpg_enabled+hud on), calls installHooks, no fetch", async () => {
    const { deps, hookCalls } = makeLiteDeps(home);

    const result = await runSetup(deps);

    expect(result.config.features.rpg_enabled).toBe(true);
    expect(result.config.features.rpg_hud_enabled).toBe(true);
    expect(result.config.pet).toBe("maew");
    expect(result.config.profile_id).toBe(
      "11111111-2222-3333-4444-555555555555",
    );
    // local baseline — no handle, github, wakatime, convex written by setup
    expect("handle" in result.config).toBe(false);
    expect("convex_http_url" in result.config).toBe(false);

    // Config written to disk
    expect(existsSync(configPath(home))).toBe(true);
    const onDisk = await readConfig(home);
    expect(onDisk?.features.rpg_enabled).toBe(true);
    expect(onDisk?.features.rpg_hud_enabled).toBe(true);
    expect(onDisk?.profile_id).toBe("11111111-2222-3333-4444-555555555555");

    // Hooks installed exactly once, with home only
    expect(hookCalls).toHaveLength(1);
    expect(hookCalls[0]?.home).toBe(home);
  });

  it("refuses to overwrite existing config without force", async () => {
    const { deps: first } = makeLiteDeps(home, "aaaa-first");
    await runSetup(first);

    const { deps: second } = makeLiteDeps(home, "bbbb-second");
    await expect(runSetup(second)).rejects.toBeInstanceOf(ConfigExistsError);

    // Original config unchanged
    const onDisk = await readConfig(home);
    expect(onDisk?.profile_id).toBe("aaaa-first");
  });

  it("force: overwrites existing config", async () => {
    const { deps: first } = makeLiteDeps(home, "aaaa-first");
    await runSetup(first);

    const { deps: second } = makeLiteDeps(home, "bbbb-second");
    const result = await runSetup(second, { force: true });
    expect(result.config.profile_id).toBe("bbbb-second");

    const onDisk = await readConfig(home);
    expect(onDisk?.profile_id).toBe("bbbb-second");
  });

  it("installHooks is called after config is written", async () => {
    const hookCalls: { home: string }[] = [];
    const deps = {
      home,
      randomUUID: () => "test-uuid",
      installHooks: async (ctx: { home: string }) => {
        // Config must already exist when hooks are installed
        expect(existsSync(configPath(home))).toBe(true);
        hookCalls.push(ctx);
      },
    };

    await runSetup(deps);
    expect(hookCalls).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// runRpg (interactive Alive enrollment)
// ---------------------------------------------------------------------------

describe("runRpg", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-rpg-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("greenfield: writes RPG config with rpg_enabled=true, registers with Convex", async () => {
    const { deps, fetchRec, prompterRec } = makeRpgDeps(
      [
        "user-1",
        "cmejia",
        "ghp_secret",
        "waka_secret",
        "https://example.convex.site",
      ],
      home,
    );

    const result = await runRpg(deps);

    expect(result.config.features.rpg_enabled).toBe(true);
    expect(result.config.profile_id).toBe(
      "11111111-2222-3333-4444-555555555555",
    );
    // RPG-required fields present
    if (!result.config.features.rpg_enabled) throw new Error("type narrowing");
    expect(result.config.handle).toBe("user-1");
    expect(result.config.github_username).toBe("cmejia");
    expect(result.config.github_token).toBe("ghp_secret");
    expect(result.config.wakatime_key).toBe("waka_secret");
    expect(result.config.convex_http_url).toBe("https://example.convex.site");
    expect(result.config.health.timezone).toBeString();

    // Config persisted
    expect(existsSync(configPath(home))).toBe(true);
    const onDisk = await readConfig(home);
    expect(onDisk?.features.rpg_enabled).toBe(true);

    // Registered with Convex /sync
    expect(fetchRec.calls).toHaveLength(1);
    expect(fetchRec.calls[0]?.url).toBe("https://example.convex.site/sync");
    expect(fetchRec.calls[0]?.body?.handle).toBe("user-1");

    // Notice surfaced
    expect(prompterRec.notices.join("\n")).toMatch(/setup complete/i);
  });

  it("upgrades an existing Lite config to RPG shape", async () => {
    // Pre-condition: Lite config exists
    await writeConfig(home, {
      profile_id: "lite-id",
      pet: "maew",
      features: { rpg_enabled: false },
    });

    const { deps } = makeRpgDeps(
      ["rpg-handle", "", "", "", "https://example.convex.site"],
      home,
      "rpg-uuid",
    );

    const result = await runRpg(deps);

    expect(result.config.features.rpg_enabled).toBe(true);
    if (!result.config.features.rpg_enabled) throw new Error("type narrowing");
    expect(result.config.handle).toBe("rpg-handle");
    // profile_id freshly generated (new enrollment)
    expect(result.config.profile_id).toBe("rpg-uuid");
  });

  it("refuses to overwrite existing RPG config without force", async () => {
    const { deps: first } = makeRpgDeps(
      ["user-a", "", "", "", "https://example.convex.site"],
      home,
      "uuid-a",
    );
    await runRpg(first);

    const { deps: second } = makeRpgDeps(
      ["user-b", "", "", "", "https://example.convex.site"],
      home,
      "uuid-b",
    );
    await expect(runRpg(second)).rejects.toBeInstanceOf(ConfigExistsError);

    // Original RPG config unchanged
    const onDisk = await readConfig(home);
    if (!onDisk?.features.rpg_enabled) throw new Error("type narrowing");
    expect(onDisk.handle).toBe("user-a");
  });

  it("force: overwrites existing RPG config", async () => {
    const { deps: first } = makeRpgDeps(
      ["user-a", "", "", "", "https://example.convex.site"],
      home,
      "uuid-a",
    );
    await runRpg(first);

    const { deps: second } = makeRpgDeps(
      ["user-b", "", "", "", "https://example.convex.site"],
      home,
      "uuid-b",
    );
    const result = await runRpg(second, { force: true });
    if (!result.config.features.rpg_enabled) throw new Error("type narrowing");
    expect(result.config.handle).toBe("user-b");
    expect(result.config.profile_id).toBe("uuid-b");
  });

  it("does not write config when Convex /sync fails", async () => {
    const { prompter } = scriptedPrompter([
      "user-x",
      "",
      "",
      "",
      "https://example.convex.site",
    ]);
    const deps = {
      prompter,
      fetch: async () =>
        new Response("nope", { status: 500, statusText: "Error" }),
      home,
      randomUUID: () => "fff-uuid",
    };

    await expect(runRpg(deps)).rejects.toThrow(/Convex \/sync/);
    expect(existsSync(configPath(home))).toBe(false);
  });

  it("does NOT reinstall hooks (assumes hooks already installed)", async () => {
    // runRpg must not call installHooks — hooks are assumed to already be present
    // If it did call a hooks function, there would be no way to inject/spy on it.
    // We verify this structurally: RpgDeps has no installHooks field.
    // This test confirms rpg completes without any hooks side-effect.
    const { deps } = makeRpgDeps(
      ["no-hooks-user", "", "", "", "https://example.convex.site"],
      home,
    );
    // Just verifying no error is thrown from a missing installHooks
    const result = await runRpg(deps);
    expect(result.config.features.rpg_enabled).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// router-level rpg dispatch (smoke test via writeFile fixture)
// ---------------------------------------------------------------------------

describe("dispatch rpg command", () => {
  it("rpg command is wired in router USAGE", async () => {
    // Import router lazily so the import error above surfaces first in the test run
    const { USAGE } = await import("./router");
    expect(USAGE).toContain("rpg");
    // setup entry no longer describes RPG enrollment — Lite only
    expect(USAGE).not.toContain(
      "handle, GitHub username+PAT pair, Wakatime, Convex URL",
    );
    // rpg entry describes interactive enrollment
    expect(USAGE).toMatch(/rpg.*Interactive Alive enrollment/s);
  });
});
