import { ConvexAuthProvider } from "@convex-dev/auth/react";
import { useAction, useConvexAuth, useMutation } from "convex/react";
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

function UploadForm() {
  const generateUploadUrl = useMutation(api.pets.generateUploadUrl);
  const uploadPet = useAction(api.actions.uploadPet.uploadPet);

  const [files, setFiles] = useState<File[]>([]);
  const [displayName, setDisplayName] = useState("");
  const [description, setDescription] = useState("");
  const [petId, setPetId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    if (files.length === 0) {
      setError("Choose a .zip — or drop in pet.json and your spritesheet(s).");
      return;
    }
    // Front-run the server's required-sheet check for loose selections so the
    // user gets an immediate, product-framed message (no upload round-trip).
    const looseError = validateLooseSelection(files);
    if (looseError) {
      setError(looseError);
      return;
    }
    setBusy(true);
    try {
      // 0. Normalize loose files into the zip the server expects (or pass a
      //    single .zip straight through).
      const packageBlob = await buildPetPackage(files);

      // 1. Stage the raw package.
      const rawUrl = await generateUploadUrl();
      const rawZipStorageId = await uploadBlob(rawUrl, packageBlob);

      // 2. Best-effort client thumbnail (cosmetic, low-trust, server-capped).
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

      // 3. Validate + repack + store via the P11.03 action.
      const args = buildUploadArgs(
        { displayName, description, petId },
        { rawZipStorageId, thumbnailStorageId },
      );
      // Storage ids come back from the upload POST as plain strings; they are
      // genuine _storage ids, so brand them for the action's validators.
      const result = await uploadPet({
        ...args,
        rawZipStorageId: args.rawZipStorageId as Id<"_storage">,
        thumbnailStorageId: args.thumbnailStorageId as
          | Id<"_storage">
          | undefined,
      });

      // 4. Route to the new pet's gallery detail view.
      window.location.href = `/gallery#${result.petId}`;
    } catch (err) {
      setError(mapUploadError(err));
      setBusy(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="max-w-xl mx-auto px-6 py-8 flex flex-col gap-5"
    >
      {error && (
        <p className="text-sm bg-error-container text-on-error-container border-2 border-charcoal-ink rounded-xl px-4 py-3">
          {error}
        </p>
      )}

      <label className="flex flex-col gap-1.5">
        <span className="font-bold text-sm">Pet files</span>
        <input
          type="file"
          multiple
          accept=".zip,application/zip,.json,application/json,.webp,image/webp"
          onChange={(e) => setFiles(Array.from(e.target.files ?? []))}
          className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-2.5 px-3 file:mr-3 file:rounded-lg file:border-0 file:bg-primary-container file:text-on-primary-container file:font-bold file:px-3 file:py-1.5"
        />
        <span className="text-xs text-on-surface-variant">
          Upload a <code className="font-mono">.zip</code>, or just select the
          loose files — we'll package them for you.
        </span>
        <ul className="text-xs text-on-surface-variant list-disc pl-4 space-y-0.5">
          <li>
            <strong>Required:</strong> <code className="font-mono">pet.json</code>,{" "}
            <code className="font-mono">spritesheet.webp</code> (Codex), and{" "}
            <code className="font-mono">codogotchi-lite-basic-spritesheet.webp</code>{" "}
            (Lite-Basic).
          </li>
          <li>
            <strong>Optional:</strong> the Lite-Enhanced and SoA tier sheets.
          </li>
          <li>
            A Lite-Basic sheet is what makes a pet a true Codogotchi companion —
            codex-only packages are rejected.
          </li>
        </ul>
        {files.length > 0 && (
          <span className="text-xs text-on-surface-variant">
            Selected: {files.map((f) => f.name).join(", ")}
          </span>
        )}
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="font-bold text-sm">Display name</span>
        <input
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          placeholder="Maew the Cat"
          className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 focus:outline-none focus:border-secondary-container"
        />
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="font-bold text-sm">Pet ID (URL slug)</span>
        <input
          value={petId}
          onChange={(e) => setPetId(e.target.value)}
          placeholder="maew"
          className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 font-mono focus:outline-none focus:border-secondary-container"
        />
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="font-bold text-sm">Description</span>
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="A chibi companion for your menubar."
          rows={3}
          className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 focus:outline-none focus:border-secondary-container resize-none"
        />
      </label>

      <button
        type="submit"
        disabled={busy}
        className="squishy-btn bg-primary-container text-on-primary-container font-display font-bold py-3 rounded-xl disabled:opacity-60"
      >
        {busy ? "Uploading…" : "Publish pet"}
      </button>
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
