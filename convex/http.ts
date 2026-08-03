import { syncProfileRequestSchema } from "@codogotchi/contracts";
import { httpRouter } from "convex/server";
import { api, internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import { auth } from "./auth";

const ALLOWED_ORIGINS = [
  "https://codogotchi.app",
  "https://www.codogotchi.app",
];

const http = httpRouter();

// Mount @convex-dev/auth HTTP routes (sign-in, sign-out, session refresh, etc.)
auth.addHttpRoutes(http);

http.route({
  path: "/sync",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const requiredSecret = process.env.SYNC_SHARED_SECRET;
    if (requiredSecret) {
      const provided = request.headers.get("x-codogotchi-sync-secret") ?? "";
      if (provided !== requiredSecret) {
        return jsonError(401, {
          error: "unauthorized",
          message: "Missing or invalid x-codogotchi-sync-secret header.",
        });
      }
    }

    let raw: unknown;
    try {
      raw = await request.json();
    } catch {
      return jsonError(400, {
        error: "invalid_json",
        message: "Request body must be valid JSON.",
      });
    }

    const parsed = syncProfileRequestSchema.safeParse(raw);
    if (!parsed.success) {
      // Include the zod issue paths so a buddy onboarding badly can
      // self-diagnose without server logs.
      const issues = parsed.error.issues.map((i) => ({
        path: i.path.join("."),
        message: i.message,
        code: i.code,
      }));
      return jsonError(400, {
        error: "invalid_payload",
        issues,
      });
    }

    const result = await ctx.runMutation(
      api.mutations.syncProfile.syncProfile,
      parsed.data,
    );
    return jsonOk(result);
  }),
});

// GET /pets/<petId>/download — streams the canonical zip and increments downloadCount.
// All three install paths (npx, curl, direct download) hit this single endpoint.
// claimDownload atomically checks listed + increments count, eliminating TOCTOU.
http.route({
  pathPrefix: "/pets/",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const segments = url.pathname.split("/").filter(Boolean);
    // Expect: ["pets", "<petId>", "download"]
    if (
      segments.length !== 3 ||
      segments[0] !== "pets" ||
      segments[2] !== "download"
    ) {
      return jsonError(404, { error: "not_found" });
    }
    const petId = segments[1];

    // ?preview=1 — in-browser animation previews (gallery cards, detail page).
    // Skips the downloadCount increment so page views never skew install
    // metrics, and is cacheable since it's a pure read.
    const isPreview = url.searchParams.get("preview") === "1";
    const claim = isPreview
      ? await ctx.runQuery(internal.pets.getZipForPreview, { petId })
      : await ctx.runMutation(internal.pets.claimDownload, { petId });
    if (!claim) {
      return jsonError(404, { error: "not_found" });
    }

    const blob = await ctx.storage.get(claim.zipStorageId);
    if (!blob) {
      return jsonError(500, { error: "storage_error" });
    }

    return new Response(blob, {
      status: 200,
      headers: {
        "content-type": "application/zip",
        "content-disposition": `attachment; filename="${petId}.codogotchi-pet.zip"`,
        // Public, unauthenticated asset: lets the gallery pages fetch the zip
        // in-browser to render animation previews.
        "access-control-allow-origin": "*",
        ...(isPreview ? { "cache-control": "public, max-age=3600" } : {}),
      },
    });
  }),
});

// POST /track-dmg-download — fire-and-forget counter for DMG installs.
// No auth required; no personal data collected.
http.route({
  path: "/track-dmg-download",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const origin = request.headers.get("origin") ?? "";
    const corsHeaders: Record<string, string> = {
      "access-control-allow-origin": ALLOWED_ORIGINS.includes(origin)
        ? origin
        : ALLOWED_ORIGINS[0],
      "access-control-allow-methods": "POST, OPTIONS",
    };
    await ctx.runMutation(
      internal.mutations.trackDmgDownload.trackDmgDownload,
      {},
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }),
});

http.route({
  path: "/track-dmg-download",
  method: "OPTIONS",
  handler: httpAction(async (_ctx, request) => {
    const origin = request.headers.get("origin") ?? "";
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": ALLOWED_ORIGINS.includes(origin)
          ? origin
          : ALLOWED_ORIGINS[0],
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-max-age": "86400",
      },
    });
  }),
});

// POST /track-update-install — fire-and-forget counter for successful Sparkle
// auto-updates, called directly by the menubar app (not a browser). No auth
// required; no personal data collected, just app/previous version + platform.
http.route({
  path: "/track-update-install",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    let raw: unknown;
    try {
      raw = await request.json();
    } catch {
      return jsonError(400, {
        error: "invalid_json",
        message: "Request body must be valid JSON.",
      });
    }

    const MAX_FIELD_LENGTH = 32;
    const isShortString = (value: unknown): value is string =>
      typeof value === "string" &&
      value.length > 0 &&
      value.length <= MAX_FIELD_LENGTH;

    if (
      typeof raw !== "object" ||
      raw === null ||
      !isShortString((raw as Record<string, unknown>).appVersion) ||
      !isShortString((raw as Record<string, unknown>).platform)
    ) {
      return jsonError(400, {
        error: "invalid_payload",
        message: `appVersion and platform are required strings (max ${MAX_FIELD_LENGTH} chars).`,
      });
    }
    const rawBody = raw as Record<string, unknown>;
    if (
      rawBody.previousVersion !== undefined &&
      !isShortString(rawBody.previousVersion)
    ) {
      return jsonError(400, {
        error: "invalid_payload",
        message: `previousVersion must be a string (max ${MAX_FIELD_LENGTH} chars) when present.`,
      });
    }

    await ctx.runMutation(
      internal.mutations.trackUpdateInstall.trackUpdateInstall,
      {
        appVersion: rawBody.appVersion as string,
        previousVersion: rawBody.previousVersion as string | undefined,
        platform: rawBody.platform as string,
      },
    );
    return new Response(null, { status: 204 });
  }),
});

export default http;

function jsonOk(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

function jsonError(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
