import { syncProfileRequestSchema } from "@codogotchi/contracts";
import { httpRouter } from "convex/server";
import { api, internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import { auth } from "./auth";

const http = httpRouter();

// Mount @convex-dev/auth HTTP routes (sign-in, sign-out, session refresh, etc.)
auth.addHttpRoutes(http);

http.route({
  path: "/sync",
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

    // Atomic check: verifies listed + increments downloadCount in one mutation.
    // Returns null for unlisted or missing pets; returns { zipStorageId } otherwise.
    const claim = await ctx.runMutation(internal.pets.claimDownload, { petId });
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
      },
    });
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
