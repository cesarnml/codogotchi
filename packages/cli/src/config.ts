import { mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { HealthConfigPayload } from "@codogotchi/contracts";

export type CodogotchiConfig = {
  profile_id: string;
  handle: string;
  github_token: string | null;
  github_username?: string | null;
  wakatime_key: string | null;
  convex_http_url: string;
  health: HealthConfigPayload;
};

export function getCodogotchiHome(
  env: NodeJS.ProcessEnv = process.env,
): string {
  const override = env.CODOGOTCHI_HOME;
  if (override && override.length > 0) return override;
  return join(homedir(), ".codogotchi");
}

export function configPath(home: string): string {
  return join(home, "config.json");
}

export async function configExists(home: string): Promise<boolean> {
  try {
    await stat(configPath(home));
    return true;
  } catch {
    return false;
  }
}

export async function readConfig(
  home: string,
): Promise<CodogotchiConfig | null> {
  try {
    const raw = await readFile(configPath(home), "utf8");
    return JSON.parse(raw) as CodogotchiConfig;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
}

export async function writeConfig(
  home: string,
  config: CodogotchiConfig,
): Promise<void> {
  await mkdir(home, { recursive: true });
  const target = configPath(home);
  const tmp = `${target}.tmp-${process.pid}-${Date.now()}`;
  await writeFile(tmp, `${JSON.stringify(config, null, 2)}\n`, "utf8");
  await rename(tmp, target);
}
