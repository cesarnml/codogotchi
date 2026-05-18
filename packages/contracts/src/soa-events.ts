import { z } from "zod";
import type { ActivityState } from "./animation-state";

/**
 * SoA gate event names recognized by the codogotchi mapping. The list mirrors
 * the SoA-sourced rows in `docs/contracts/animation-state-vocabulary.md` and
 * `docs/contracts/soa-event-feed.md`.
 */
export const SOA_EVENT_NAMES = [
	"ticket_started",
	"flow_state_entered",
	"risky_diff_detected",
	"pr_review_window_opened",
	"ticket_completed",
	"review_clean_recorded",
	"stage_advanced",
	"subagent_invoked",
	"verification_failed",
] as const;

export const soaEventNameSchema = z.enum(SOA_EVENT_NAMES);
export type SoaEventName = z.infer<typeof soaEventNameSchema>;

/**
 * One line from `.soa/events.ndjson`. Unknown event names are tolerated at the
 * schema layer so the parser does not throw — the consumer (hook binary)
 * decides whether to ignore them.
 */
export const soaEventLineSchema = z
	.object({
		name: z.string().min(1),
		ts: z.string().min(1),
		plan_key: z.string().optional(),
		ticket_id: z.string().optional(),
		payload: z.record(z.string(), z.unknown()).optional(),
	})
	.passthrough();
export type SoaEventLine = z.infer<typeof soaEventLineSchema>;

/**
 * Canonical mapping from SoA event name → animation activity state. Mirrors
 * the table in `docs/contracts/soa-event-feed.md` and the SoA rows in
 * `docs/contracts/animation-state-vocabulary.md`.
 */
export const SOA_EVENT_TO_ACTIVITY_STATE: Record<SoaEventName, ActivityState> =
	{
		ticket_started: "hyped",
		flow_state_entered: "focused",
		risky_diff_detected: "nervous",
		pr_review_window_opened: "waiting",
		ticket_completed: "celebrating",
		review_clean_recorded: "celebrating",
		stage_advanced: "ascended",
		subagent_invoked: "calling_for_backup",
		verification_failed: "panicking",
	};

export function mapSoaEventToActivityState(
	name: string,
): ActivityState | undefined {
	const parsed = soaEventNameSchema.safeParse(name);
	if (!parsed.success) return undefined;
	return SOA_EVENT_TO_ACTIVITY_STATE[parsed.data];
}
