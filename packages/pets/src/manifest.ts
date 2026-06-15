import JSZip from "jszip";
import { ALLOWLISTED_FILES } from "./pet-contract";

// pet.json is the single source of truth for a pet's identity and display
// metadata. The upload flow derives `petId` (from `id`), `displayName`, and
// `description` from here rather than from separate user-submitted form fields,
// so the package and the gallery row can never drift apart.
export type PetManifest = {
  id: string;
  displayName: string;
  description: string;
};

/**
 * Extracts and validates the pet.json manifest from a pet zip. Returns null when
 * pet.json is absent, unparseable, or missing a required string `id`/`displayName`.
 * `description` is optional and defaults to "".
 *
 * This is a lightweight peek used before full validation (e.g. to resolve the
 * petId and look up an existing pet for the create-vs-update decision). The
 * authoritative package check still runs through `validateAndRepackPet`.
 */
export async function parsePetManifest(
  zipBuffer: Uint8Array | ArrayBuffer,
): Promise<PetManifest | null> {
  let zip: JSZip;
  try {
    zip = await JSZip.loadAsync(zipBuffer);
  } catch {
    return null;
  }

  const entry = zip.file("pet.json");
  if (!entry) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(await entry.async("string"));
  } catch {
    return null;
  }

  if (typeof parsed !== "object" || parsed === null) return null;
  const obj = parsed as Record<string, unknown>;
  if (typeof obj.id !== "string" || obj.id.length === 0) return null;
  if (typeof obj.displayName !== "string" || obj.displayName.length === 0) {
    return null;
  }

  return {
    id: obj.id,
    displayName: obj.displayName,
    description: typeof obj.description === "string" ? obj.description : "",
  };
}

/**
 * Merges two pet packages, with `overlay` taking precedence over `base` on a
 * per-file basis across the allowlisted file set. Non-allowlisted entries are
 * dropped. Used by the progressive-upload path: a creator can re-upload a
 * partial package (e.g. just pet.json + the SoA sheet) and have it merged into
 * their existing canonical package before validation, so the required Codex and
 * Lite-Basic sheets carried by the existing pet are preserved.
 *
 * Add-or-replace semantics: a tier present in `overlay` replaces the base copy;
 * a tier only present in `base` is carried forward; pet.json from `overlay`
 * wins (it is the refreshed source of truth for metadata).
 *
 * The returned buffer is NOT validated — callers must pass it to
 * `validateAndRepackPet` to enforce the contract and produce the canonical zip.
 */
export async function mergePetPackages(
  base: Uint8Array | ArrayBuffer,
  overlay: Uint8Array | ArrayBuffer,
): Promise<Uint8Array> {
  const [baseZip, overlayZip] = await Promise.all([
    JSZip.loadAsync(base),
    JSZip.loadAsync(overlay),
  ]);

  const out = new JSZip();
  for (const name of ALLOWLISTED_FILES) {
    const overlayEntry = overlayZip.file(name);
    const baseEntry = baseZip.file(name);
    const source = overlayEntry ?? baseEntry;
    if (!source) continue;
    out.file(name, await source.async("uint8array"));
  }
  return out.generateAsync({ type: "uint8array" });
}
