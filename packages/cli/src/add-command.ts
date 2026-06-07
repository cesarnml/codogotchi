import { mkdir, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { validateAndRepackPet } from "@codogotchi/pets";
import JSZip from "jszip";

export type AddDeps = {
  home: string;
  fetch: typeof globalThis.fetch;
  apiUrl: string;
};

export type AddOptions = {
  petId: string;
  force: boolean;
};

export type AddResult =
  | { ok: true; petDir: string }
  | {
      ok: false;
      code: "not_found" | "invalid_package" | "network_error";
      message: string;
    };

export async function runAdd(
  deps: AddDeps,
  opts: AddOptions,
): Promise<AddResult> {
  const { home, fetch, apiUrl } = deps;
  const { petId, force } = opts;

  let zipBytes: Uint8Array;
  try {
    const res = await fetch(`${apiUrl}/pets/${petId}/download`);
    if (res.status === 404) {
      return {
        ok: false,
        code: "not_found",
        message: `Pet '${petId}' not found in the marketplace.`,
      };
    }
    if (!res.ok) {
      return {
        ok: false,
        code: "network_error",
        message: `Download failed with status ${res.status}.`,
      };
    }
    zipBytes = new Uint8Array(await res.arrayBuffer());
  } catch (err) {
    return {
      ok: false,
      code: "network_error",
      message: `Network error: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  // Re-validate as defense-in-depth — validation happens before any FS writes
  // so a corrupt/invalid download never leaves a partial pet directory.
  const validation = await validateAndRepackPet(zipBytes);
  if (!validation.ok) {
    return {
      ok: false,
      code: "invalid_package",
      message: `Downloaded package failed validation:\n${validation.errors.join("\n")}`,
    };
  }

  const petDir = join(home, "pets", petId);
  await mkdir(petDir, { recursive: true });

  const canonical = await JSZip.loadAsync(validation.canonicalZip);
  for (const [filename, file] of Object.entries(canonical.files)) {
    if (file.dir) continue;
    const dest = join(petDir, filename);
    if (!force) {
      try {
        await stat(dest);
        continue; // file already exists — skip (no-overwrite semantics)
      } catch {
        // file absent — fall through to write
      }
    }
    await writeFile(dest, await file.async("uint8array"));
  }

  return { ok: true, petDir };
}
