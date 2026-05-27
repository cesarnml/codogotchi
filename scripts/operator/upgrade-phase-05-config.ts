#!/usr/bin/env bun
// operator-only, not user-facing
//
// upgrade-phase-05-config.ts — add `features.rpg_enabled: true` to the
// developer's ~/.codogotchi/config.json when upgrading from the pre-phase-05
// schema (which had no `features` key).
//
// Preserves: handle, convex_http_url, github_token, github_username,
// wakatime_key, health, pet, profile_id.
//
// Usage:
//   bun scripts/operator/upgrade-phase-05-config.ts
//   bun scripts/operator/upgrade-phase-05-config.ts --dry-run

import { readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const DRY_RUN = process.argv.includes("--dry-run");
const HOME = process.env.CODOGOTCHI_HOME ?? join(homedir(), ".codogotchi");
const CONFIG_PATH = join(HOME, "config.json");

async function main() {
  let raw: string;
  try {
    raw = await readFile(CONFIG_PATH, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      console.error(
        `No config found at ${CONFIG_PATH}. Run 'codogotchi setup' first.`,
      );
      process.exit(2);
    }
    throw err;
  }

  const config = JSON.parse(raw) as Record<string, unknown>;

  if (config.features !== undefined) {
    const features = config.features as Record<string, unknown>;
    if (features.rpg_enabled === true) {
      console.log(
        "Config already has features.rpg_enabled=true — no change needed.",
      );
      return;
    }
  }

  const upgraded: Record<string, unknown> = {
    ...config,
    features: { rpg_enabled: true },
  };

  const output = `${JSON.stringify(upgraded, null, 2)}\n`;

  if (DRY_RUN) {
    console.log("-- DRY RUN: would write the following config --");
    console.log(output);
    return;
  }

  const tmp = `${CONFIG_PATH}.tmp-upgrade-${process.pid}-${Date.now()}`;
  await writeFile(tmp, output, "utf8");
  await rename(tmp, CONFIG_PATH);
  console.log(`Upgraded ${CONFIG_PATH}: features.rpg_enabled=true`);
}

main().catch((err) => {
  console.error("Upgrade failed:", err);
  process.exit(1);
});
