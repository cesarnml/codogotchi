import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { configPath, readConfig } from "./config";
import { ConfigExistsError, runSetup } from "./setup";

type HookCall = { home: string };

function recordingHooks() {
  const calls: HookCall[] = [];
  const installHooks = async (ctx: HookCall): Promise<void> => {
    calls.push(ctx);
  };
  return { installHooks, calls };
}

function makeLiteDeps(
  home: string,
  uuid = "11111111-2222-3333-4444-555555555555",
) {
  const hooksRec = recordingHooks();
  return {
    hooksRec,
    deps: {
      home,
      randomUUID: () => uuid,
      installHooks: hooksRec.installHooks,
    },
  };
}

describe("runSetup (Lite)", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-setup-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("greenfield: writes Lite config, installs hooks, no network", async () => {
    const { deps, hooksRec } = makeLiteDeps(home);

    const result = await runSetup(deps);

    expect(result.config.features.rpg_enabled).toBe(false);
    expect(result.config.pet).toBe("maew");
    expect(result.config.profile_id).toBe(
      "11111111-2222-3333-4444-555555555555",
    );
    expect("handle" in result.config).toBe(false);
    expect("convex_http_url" in result.config).toBe(false);

    // Config persisted to disk under CODOGOTCHI_HOME
    expect(existsSync(configPath(home))).toBe(true);
    const onDisk = await readConfig(home);
    expect(onDisk?.features.rpg_enabled).toBe(false);
    expect(onDisk?.profile_id).toBe("11111111-2222-3333-4444-555555555555");

    // Hooks installed exactly once
    expect(hooksRec.calls).toHaveLength(1);
    expect(hooksRec.calls[0]?.home).toBe(home);
  });

  it("refuses to overwrite pre-existing config without force", async () => {
    const { deps: firstDeps } = makeLiteDeps(
      home,
      "aaaa-aaaa-aaaa-aaaa-aaaaaaaa",
    );
    await runSetup(firstDeps);

    const { deps: secondDeps } = makeLiteDeps(
      home,
      "bbbb-bbbb-bbbb-bbbb-bbbbbbbb",
    );
    await expect(runSetup(secondDeps)).rejects.toBeInstanceOf(
      ConfigExistsError,
    );

    // Underlying config unchanged
    const onDisk = await readConfig(home);
    expect(onDisk?.profile_id).toBe("aaaa-aaaa-aaaa-aaaa-aaaaaaaa");
  });

  it("force: overwrites existing config and re-installs hooks idempotently", async () => {
    const { deps: firstDeps, hooksRec: firstHooks } = makeLiteDeps(
      home,
      "aaaa-aaaa-aaaa-aaaa-aaaaaaaa",
    );
    await runSetup(firstDeps);
    expect(firstHooks.calls).toHaveLength(1);

    const { deps: secondDeps, hooksRec: secondHooks } = makeLiteDeps(
      home,
      "bbbb-bbbb-bbbb-bbbb-bbbbbbbb",
    );
    const result = await runSetup(secondDeps, { force: true });
    expect(result.config.profile_id).toBe("bbbb-bbbb-bbbb-bbbb-bbbbbbbb");
    expect(secondHooks.calls).toHaveLength(1);

    const onDisk = await readConfig(home);
    expect(onDisk?.profile_id).toBe("bbbb-bbbb-bbbb-bbbb-bbbbbbbb");
  });

  it("writes config before calling installHooks", async () => {
    let configExistedOnHooksInstall = false;
    const deps = {
      home,
      randomUUID: () => "test-uuid",
      installHooks: async (_ctx: HookCall) => {
        configExistedOnHooksInstall = existsSync(configPath(home));
      },
    };

    await runSetup(deps);
    expect(configExistedOnHooksInstall).toBe(true);
  });
});
