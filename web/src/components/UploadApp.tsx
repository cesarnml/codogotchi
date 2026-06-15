import { ConvexAuthProvider } from "@convex-dev/auth/react";
import {
  useAction,
  useConvexAuth,
  useMutation,
  useQuery,
} from "convex/react";
import JSZip from "jszip";
import { useState } from "react";
import { api } from "~convex/_generated/api";
import type { Id } from "~convex/_generated/dataModel";
import { convex } from "../lib/convex";
import { generateThumbnailBlob } from "../lib/thumbnail";
import {
  buildPetPackage,
  buildUploadArgs,
  mapUploadError,
  validateLooseSelection,
} from "../lib/uploadMapper";
import AuthModal from "./AuthModal";

// Codex base sheet layout (packages/pets/src/pet-contract.ts): 8 cols × 9 rows.
// The codex spritesheet.webp is always present, so idle frame 1 lives there.
const SHEET_COLS = 8;
const CODEX_ROWS = 9;
const CODEX_SHEET = "spritesheet.webp";

async function uploadBlob(uploadUrl: string, blob: Blob): Promise<string> {
  const res = await fetch(uploadUrl, {
    method: "POST",
    headers: { "Content-Type": blob.type || "application/octet-stream" },
    body: blob,
  });
  if (!res.ok) throw new Error(`Upload failed (${res.status})`);
  const { storageId } = (await res.json()) as { storageId: string };
  return storageId;
}

// Best-effort client thumbnail: decode the codex sheet from the package and crop
// idle frame 1. Returns null on any failure — the server treats the thumbnail
// as optional and cosmetic, so a missing one must not block a valid upload.
async function generateThumbnailFromZip(file: Blob): Promise<Blob | null> {
  try {
    const zip = await JSZip.loadAsync(file);
    const sheet = zip.file(CODEX_SHEET);
    if (!sheet) return null;
    const sheetBlob = await sheet.async("blob");
    const url = URL.createObjectURL(
      new Blob([sheetBlob], { type: "image/webp" }),
    );
    try {
      const image = await new Promise<HTMLImageElement>((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error("decode failed"));
        img.src = url;
      });
      return await generateThumbnailBlob(image, SHEET_COLS, CODEX_ROWS);
    } finally {
      URL.revokeObjectURL(url);
    }
  } catch {
    return null;
  }
}

type Mode = "create" | "update";

const TIER_LABELS: Record<string, string> = {
  codex: "Codex",
  liteBasic: "Lite-Basic",
  liteEnhanced: "Lite-Enhanced",
  soa: "SoA",
};

function UploadForm() {
  const generateUploadUrl = useMutation(api.pets.generateUploadUrl);
  const uploadPet = useAction(api.actions.uploadPet.uploadPet);
  const updatePetSheets = useAction(api.actions.uploadPet.updatePetSheets);
  const myPets = useQuery(api.pets.listMyPets);

  const [mode, setMode] = useState<Mode>("create");
  const [files, setFiles] = useState<File[]>([]);
  const [selectedPetId, setSelectedPetId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Default the picker to the first owned pet without an effect.
  const targetPetId = selectedPetId || myPets?.[0]?.petId || "";

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    if (files.length === 0) {
      setError(
        mode === "create"
          ? "Choose a .zip — or drop in pet.json and your spritesheet(s)."
          : "Choose the tier sheet(s) to add or replace.",
      );
      return;
    }
    if (mode === "update" && !targetPetId) {
      setError("Pick which pet to update.");
      return;
    }
    // In create mode, front-run the server's pet.json check for a friendlier,
    // round-trip-free message. Update mode needs no pet.json, so skip it.
    if (mode === "create") {
      const looseError = validateLooseSelection(files);
      if (looseError) {
        setError(looseError);
        return;
      }
    }
    setBusy(true);
    try {
      // Normalize loose files into the zip the server expects (or pass a single
      // .zip straight through), then stage it.
      const packageBlob = await buildPetPackage(files);
      const rawUrl = await generateUploadUrl();
      const rawZipStorageId = await uploadBlob(rawUrl, packageBlob);

      let petId: string;
      if (mode === "update") {
        // Identity = the selected pet; ownership = the session. No pet.json,
        // no thumbnail — the existing pet's metadata + thumbnail are preserved.
        const result = await updatePetSheets({
          petId: targetPetId,
          rawZipStorageId: rawZipStorageId as Id<"_storage">,
        });
        petId = result.petId;
      } else {
        // Best-effort client thumbnail (cosmetic, low-trust, server-capped).
        let thumbnailStorageId: string | undefined;
        const thumb = await generateThumbnailFromZip(packageBlob);
        if (thumb) {
          try {
            const thumbUrl = await generateUploadUrl();
            thumbnailStorageId = await uploadBlob(thumbUrl, thumb);
          } catch {
            thumbnailStorageId = undefined;
          }
        }
        // Identity + display fields are derived server-side from pet.json.
        const args = buildUploadArgs({ rawZipStorageId, thumbnailStorageId });
        const result = await uploadPet({
          ...args,
          rawZipStorageId: args.rawZipStorageId as Id<"_storage">,
          thumbnailStorageId: args.thumbnailStorageId as
            | Id<"_storage">
            | undefined,
        });
        petId = result.petId;
      }

      // Route to the pet's gallery detail view.
      window.location.href = `/gallery#${petId}`;
    } catch (err) {
      setError(mapUploadError(err));
      setBusy(false);
    }
  }

  const hasPets = (myPets?.length ?? 0) > 0;

  return (
    <form
      onSubmit={handleSubmit}
      className="max-w-xl mx-auto px-6 py-8 flex flex-col gap-5"
    >
      {/* Mode toggle */}
      <div className="flex rounded-xl border-2 border-charcoal-ink overflow-hidden text-sm font-bold">
        {(["create", "update"] as Mode[]).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => {
              setMode(m);
              setError(null);
            }}
            className={`flex-1 py-2.5 transition-colors ${
              mode === m
                ? "bg-primary-container text-on-primary-container"
                : "bg-surface-container-lowest text-on-surface-variant hover:bg-surface-container"
            }`}
          >
            {m === "create" ? "Create new pet" : "Update an existing pet"}
          </button>
        ))}
      </div>

      {error && (
        <p className="text-sm bg-error-container text-on-error-container border-2 border-charcoal-ink rounded-xl px-4 py-3">
          {error}
        </p>
      )}

      {/* Update mode: pick which owned pet to update */}
      {mode === "update" &&
        (hasPets ? (
          <label className="flex flex-col gap-1.5">
            <span className="font-bold text-sm">Which pet?</span>
            <select
              value={targetPetId}
              onChange={(e) => setSelectedPetId(e.target.value)}
              className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 focus:outline-none focus:border-secondary-container"
            >
              {myPets?.map((p) => (
                <option key={p.petId} value={p.petId}>
                  {p.displayName} —{" "}
                  {p.tiers
                    .map((t: string) => TIER_LABELS[t] ?? t)
                    .join(", ")}
                </option>
              ))}
            </select>
          </label>
        ) : (
          <p className="text-sm text-on-surface-variant bg-surface-container border-2 border-outline-variant rounded-xl px-4 py-3">
            You haven't published any pets yet. Switch to{" "}
            <strong>Create new pet</strong> to publish your first one.
          </p>
        ))}

      {/* File picker — hidden in update mode when the creator owns no pets */}
      {(mode === "create" || hasPets) && (
        <label className="flex flex-col gap-1.5">
          <span className="font-bold text-sm">
            {mode === "create" ? "Pet files" : "Tier sheet(s) to add or replace"}
          </span>
          <input
            type="file"
            multiple
            accept=".zip,application/zip,.json,application/json,.webp,image/webp"
            onChange={(e) => setFiles(Array.from(e.target.files ?? []))}
            className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-2.5 px-3 file:mr-3 file:rounded-lg file:border-0 file:bg-primary-container file:text-on-primary-container file:font-bold file:px-3 file:py-1.5"
          />
          {mode === "create" ? (
            <>
              <span className="text-xs text-on-surface-variant">
                Upload a <code className="font-mono">.zip</code>, or just select
                the loose files — we'll package them for you.
              </span>
              <ul className="text-xs text-on-surface-variant list-disc pl-4 space-y-0.5">
                <li>
                  <strong>Required:</strong>{" "}
                  <code className="font-mono">pet.json</code>,{" "}
                  <code className="font-mono">spritesheet.webp</code> (Codex), and{" "}
                  <code className="font-mono">
                    codogotchi-lite-basic-spritesheet.webp
                  </code>{" "}
                  (Lite-Basic).
                </li>
                <li>
                  <strong>Optional:</strong> the Lite-Enhanced and SoA tier sheets.
                </li>
                <li>
                  A Lite-Basic sheet is what makes a pet a true Codogotchi
                  companion — codex-only packages are rejected.
                </li>
                <li>
                  Your <code className="font-mono">pet.json</code> carries the{" "}
                  <strong>id</strong>, <strong>display name</strong>, and{" "}
                  <strong>description</strong> — no separate fields to fill in.
                </li>
              </ul>
            </>
          ) : (
            <ul className="text-xs text-on-surface-variant list-disc pl-4 space-y-0.5">
              <li>
                Drop in just the sheet(s) you want to add or replace — e.g.{" "}
                <code className="font-mono">
                  codogotchi-soa-spritesheet.webp
                </code>
                . We merge them into your existing pet.
              </li>
              <li>
                <strong>No <code className="font-mono">pet.json</code> needed</strong>{" "}
                — we already know the pet from your selection. (If you do include
                one, its id must match.)
              </li>
              <li>The pet's name and description stay as they are.</li>
            </ul>
          )}
          {files.length > 0 && (
            <span className="text-xs text-on-surface-variant">
              Selected: {files.map((f) => f.name).join(", ")}
            </span>
          )}
        </label>
      )}

      {(mode === "create" || hasPets) && (
        <button
          type="submit"
          disabled={busy}
          className="squishy-btn bg-primary-container text-on-primary-container font-display font-bold py-3 rounded-xl disabled:opacity-60"
        >
          {busy
            ? mode === "create"
              ? "Uploading…"
              : "Updating…"
            : mode === "create"
              ? "Publish pet"
              : "Update pet"}
        </button>
      )}
    </form>
  );
}

function UploadGate() {
  const { isAuthenticated, isLoading } = useConvexAuth();
  const [modalOpen, setModalOpen] = useState(true);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-24 text-on-surface-variant">
        Loading…
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <div className="flex flex-col items-center justify-center py-24 gap-4 text-center px-6">
        <span className="material-symbols-outlined text-5xl text-primary">lock</span>
        <h2 className="font-display text-2xl font-extrabold">Sign in to upload</h2>
        <p className="text-on-surface-variant max-w-sm">
          Browsing and installing pets is open to everyone — you only need an
          account to publish your own.
        </p>
        <button
          type="button"
          onClick={() => setModalOpen(true)}
          className="squishy-btn bg-primary-container text-on-primary-container font-display font-bold px-6 py-3 rounded-xl"
        >
          Sign in / Register
        </button>
        {modalOpen && <AuthModal onClose={() => setModalOpen(false)} />}
      </div>
    );
  }

  return <UploadForm />;
}

export default function UploadApp() {
  return (
    <ConvexAuthProvider client={convex}>
      <UploadGate />
    </ConvexAuthProvider>
  );
}
