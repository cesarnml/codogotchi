import { v } from "convex/values";
import { internalMutation, query } from "./_generated/server";

// Internal mutation used by the auth createOrUpdateUser callback and tests.
// Enforces username uniqueness — throws if the username is already in use.
export const createUser = internalMutation({
  args: {
    username: v.string(),
    rpgHandle: v.union(v.string(), v.null()),
    name: v.optional(v.string()),
    email: v.optional(v.string()),
    image: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", args.username))
      .unique();
    if (existing !== null) {
      throw new Error(`Username "${args.username}" is already taken`);
    }
    return await ctx.db.insert("users", {
      username: args.username,
      rpgHandle: args.rpgHandle,
      name: args.name,
      email: args.email,
      image: args.image,
    });
  },
});

export const getUserByUsername = query({
  args: { username: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", args.username))
      .unique();
  },
});
