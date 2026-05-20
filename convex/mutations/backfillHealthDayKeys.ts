import { utcDayKey } from "@codogotchi/engine";
import { mutation } from "../_generated/server";

// One-shot migration for the decoupled decay/regen tick rollout.
//
// New profiles created after this deploy populate `last_decay_day` and
// `last_regen_day` themselves on first sync. Existing profiles in the DB
// have neither field, so the engine would evaluate decay and regen on the
// very next sync after deploy. For decay this is strictly less harmful
// than the prior per-sync behavior, but the user asked for an explicit
// "no double-tick on deploy day" backfill — so we set both keys to today's
// UTC day for any profile missing them. Subsequent same-day syncs skip both
// ticks; the day after, normal cadence resumes.
//
// Idempotent: a row that already has either key keeps its value.
export const backfillHealthDayKeys = mutation({
	args: {},
	handler: async (ctx): Promise<{ updated: number; total: number }> => {
		const today = utcDayKey(new Date());
		const all = await ctx.db.query("profiles").collect();
		let updated = 0;
		for (const row of all) {
			const patch: { last_decay_day?: string; last_regen_day?: string } = {};
			if (row.last_decay_day === undefined || row.last_decay_day === null) {
				patch.last_decay_day = today;
			}
			if (row.last_regen_day === undefined || row.last_regen_day === null) {
				patch.last_regen_day = today;
			}
			if (Object.keys(patch).length > 0) {
				await ctx.db.patch(row._id, patch);
				updated += 1;
			}
		}
		return { updated, total: all.length };
	},
});
