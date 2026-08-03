import { v } from "convex/values";
import { internalMutation } from "../_generated/server";

export const trackUpdateInstall = internalMutation({
  args: {
    appVersion: v.string(),
    previousVersion: v.optional(v.string()),
    platform: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await ctx.db.insert("update_install_events", {
      ...args,
      installedAt: Date.now(),
    });
  },
});
