import { syncProfileRequestSchema } from "@codogotchi/contracts";
import { httpRouter } from "convex/server";
import { api } from "./_generated/api";
import { httpAction } from "./_generated/server";

const http = httpRouter();

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
