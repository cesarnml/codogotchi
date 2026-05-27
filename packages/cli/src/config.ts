import { mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  type CodogotchiConfigShape,
  codogotchiConfigSchema,
} from "@codogotchi/contracts";

export type CodogotchiConfig = CodogotchiConfigShape;

export class ConfigReadError extends Error {
  constructor(
    message: string,
    public readonly exitCode = 2,
  ) {
    super(message);
    this.name = "ConfigReadError";
  }
}

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
    const parsed = codogotchiConfigSchema.safeParse(JSON.parse(raw));
    if (!parsed.success) {
      throw new ConfigReadError(
        `Invalid config at ${configPath(home)}: expected Lite/RPG schema with explicit features.rpg_enabled.`,
      );
    }
    return parsed.data;
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
