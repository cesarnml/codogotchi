import { v } from "convex/values";
import { internalMutation } from "../_generated/server";

/// Writes one snapshot row per tracked release asset, all sharing a single
/// `recordedAt` so a snapshot is diffable against the previous one as a unit.
export const recordReleaseDownloads = internalMutation({
  args: {
    rows: v.array(
      v.object({
        tagName: v.string(),
        assetName: v.string(),
        downloadCount: v.number(),
      }),
    ),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const recordedAt = Date.now();
    for (const row of args.rows) {
      await ctx.db.insert("release_asset_downloads", { ...row, recordedAt });
    }
  },
});
