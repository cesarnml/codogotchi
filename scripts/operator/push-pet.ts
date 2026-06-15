#!/usr/bin/env bun
/**
 * Operator script: pack a local pet directory and publish it to the gallery.
 *
 * Usage:
 *   bun scripts/operator/push-pet.ts <pet-dir> [--email <operator-email>]
 *
 * Example:
 *   bun scripts/operator/push-pet.ts ~/.codogotchi/pets/meaw
 *
 * The script:
 *   1. Reads pet.json + spritesheets from <pet-dir>
 *   2. Packs and validates via validateAndRepackPet
 *   3. Uploads the canonical zip + per-tier sheets to Convex storage in parallel
 *   4. Upserts the pet row via mutations/operatorUpload:upsertPet — re-running
 *      for an existing pet replaces its sheets (progressive add/replace tiers).
 */

import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { validateAndRepackPet } from "@codogotchi/pets";
import JSZip from "jszip";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const OPERATOR_EMAIL = (() => {
  const idx = process.argv.indexOf("--email");
  return idx !== -1 ? process.argv[idx + 1] : "cmejia@gmail.com";
})();

// ---------------------------------------------------------------------------
// Parse args
// ---------------------------------------------------------------------------

const petDir = process.argv[2];
if (!petDir) {
  console.error("Usage: bun push-pet.ts <pet-dir> [--email <email>]");
  process.exit(1);
}
const dir = resolve(petDir.replace(/^~/, process.env.HOME ?? "~"));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function readOptional(path: string): Uint8Array | null {
  try {
    return new Uint8Array(readFileSync(path));
  } catch {
    return null;
  }
}

async function convexRun(
  functionName: string,
  args: unknown,
): Promise<unknown> {
  // Write args to a temp file so large payloads (e.g. sizes map) don't hit
  // shell arg-length limits or stream-drain races when read via subprocess.
  const tmpFile = `/tmp/convex-args-${Date.now()}.json`;
  await Bun.write(tmpFile, JSON.stringify(args));

  const proc = Bun.spawn(
    ["sh", "-c", `npx convex run ${functionName} "$(cat ${tmpFile})"`],
    { stdout: "pipe", stderr: "pipe" },
  );
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;

  // Clean up temp file
  try {
    Bun.file(tmpFile);
  } catch {
    /* ignore */
  }

  if (exitCode !== 0) {
    throw new Error(`convex run ${functionName} failed:\n${stderr}`);
  }
  return JSON.parse(stdout.trim());
}

async function uploadToStorage(
  url: string,
  bytes: Uint8Array,
  mime: string,
): Promise<string> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": mime },
    body: bytes,
  });
  if (!res.ok) {
    throw new Error(
      `Storage upload failed (${res.status}): ${await res.text()}`,
    );
  }
  const { storageId } = (await res.json()) as { storageId: string };
  return storageId;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

console.log(`\n📦  Packing ${dir}...`);

// Read pet.json
const petJson = JSON.parse(readFileSync(join(dir, "pet.json"), "utf8")) as {
  id: string;
  displayName: string;
  description?: string;
};

const ALLOWED = [
  "pet.json",
  "spritesheet.webp",
  "codogotchi-lite-basic-spritesheet.webp",
  "codogotchi-lite-enhanced-spritesheet.webp",
  "codogotchi-soa-spritesheet.webp",
] as const;

// Build the input zip from the pet dir
const inputZip = new JSZip();
inputZip.file("pet.json", readFileSync(join(dir, "pet.json")));
for (const name of ALLOWED.slice(1)) {
  const bytes = readOptional(join(dir, name));
  if (bytes) {
    inputZip.file(name, bytes);
    console.log(`  ✓ ${name} (${(bytes.length / 1024).toFixed(1)} KB)`);
  }
}
const inputZipBytes = await inputZip.generateAsync({ type: "uint8array" });

// Validate + repack
console.log("\n🔍  Validating...");
const result = await validateAndRepackPet(inputZipBytes);
if (!result.ok) {
  console.error("Validation failed:");
  for (const e of result.errors) console.error(`  ✗ ${e}`);
  process.exit(1);
}
console.log(`  tiers: ${result.metadata.tiers.join(", ")}`);
console.log(`  total: ${(result.metadata.totalBytes / 1024).toFixed(1)} KB`);

// Extract all tier sheets from the canonical zip
const TIER_SHEET_FILES: Record<string, string> = {
  codexSheetStorageId: "spritesheet.webp",
  liteBasicSheetStorageId: "codogotchi-lite-basic-spritesheet.webp",
  liteEnhancedSheetStorageId: "codogotchi-lite-enhanced-spritesheet.webp",
  soaSheetStorageId: "codogotchi-soa-spritesheet.webp",
};

const canonical = await JSZip.loadAsync(result.canonicalZip);
const tierBytes: Record<string, Uint8Array> = {};
for (const [field, filename] of Object.entries(TIER_SHEET_FILES)) {
  const entry = canonical.file(filename);
  if (entry) tierBytes[field] = await entry.async("uint8array");
}

// Get upload URLs for zip + all sheets in parallel
console.log("\n☁️   Getting upload URLs...");
const urlKeys = ["zip", ...Object.keys(tierBytes)];
const uploadUrls = await Promise.all(
  urlKeys.map(
    () =>
      convexRun(
        "mutations/operatorUpload:generateUploadUrl",
        {},
      ) as Promise<string>,
  ),
);
const uploadUrlMap = Object.fromEntries(
  urlKeys.map((k, i) => [k, uploadUrls[i]]),
);

// Upload zip + all sheets in parallel
console.log("  Uploading zip + tier sheets in parallel...");
const uploadResults = await Promise.all([
  uploadToStorage(
    uploadUrlMap.zip,
    result.canonicalZip,
    "application/zip",
  ).then((id) => {
    console.log(
      `  ✓ zip (${(result.canonicalZip.length / 1024).toFixed(0)} KB) → ${id}`,
    );
    return id;
  }),
  ...Object.entries(tierBytes).map(async ([field, bytes]) => {
    const id = await uploadToStorage(uploadUrlMap[field], bytes, "image/webp");
    console.log(
      `  ✓ ${TIER_SHEET_FILES[field]} (${(bytes.length / 1024).toFixed(0)} KB) → ${id}`,
    );
    return { field, id };
  }),
]);

const zipStorageId = uploadResults[0] as string;
const sheetStorageIds: Record<string, string> = {};
for (const item of uploadResults.slice(1) as { field: string; id: string }[]) {
  sheetStorageIds[item.field] = item.id;
}

// Upsert pet row (create, or full-replace if the slug already exists)
console.log("\n🐾  Upserting pet row...");
const insertArgs: Record<string, unknown> = {
  petId: petJson.id,
  displayName: petJson.displayName,
  description:
    petJson.description ?? `${petJson.displayName} — a Codogotchi companion`,
  tiers: result.metadata.tiers,
  zipStorageId,
  sizes: { fileSizes: result.metadata.fileSizes },
  operatorEmail: OPERATOR_EMAIL,
  ...sheetStorageIds,
};

const upserted = (await convexRun(
  "mutations/operatorUpload:upsertPet",
  insertArgs,
)) as { _id: string; created: boolean };
console.log(
  `  ${upserted.created ? "created" : "updated"} _id: ${upserted._id}`,
);
console.log(
  `\n✅  ${petJson.id} (${upserted.created ? "created" : "updated"}, tiers: ${result.metadata.tiers.join(", ")}) is live at /gallery#${petJson.id}\n`,
);
