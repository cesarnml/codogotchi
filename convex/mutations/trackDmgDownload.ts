import { internalMutation } from "../_generated/server";

export const trackDmgDownload = internalMutation({
  args: {},
  handler: async (ctx) => {
    await ctx.db.insert("dmg_downloads", { downloadedAt: Date.now() });
  },
});
