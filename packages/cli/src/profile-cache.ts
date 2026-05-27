import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { ProfileResponse } from "@codogotchi/contracts";

export function profileCachePath(home: string): string {
  return join(home, "profile.json");
}

export async function readProfileCache(
  home: string,
): Promise<ProfileResponse | null> {
  try {
    const raw = await readFile(profileCachePath(home), "utf8");
    return JSON.parse(raw) as ProfileResponse;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
}

export async function writeProfileCache(
  home: string,
  profile: ProfileResponse,
): Promise<void> {
  await mkdir(home, { recursive: true });
  const target = profileCachePath(home);
  const tmp = `${target}.tmp-${process.pid}-${Date.now()}`;
  await writeFile(tmp, `${JSON.stringify(profile, null, 2)}\n`, "utf8");
  await rename(tmp, target);
}
