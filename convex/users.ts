import {
  normalizeUsername,
  usernameTakenMessage,
  validateUsername,
} from "@codogotchi/contracts";
import { getAuthUserId } from "@convex-dev/auth/server";
import { ConvexError, v } from "convex/values";
import {
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";

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
      throw new Error(usernameTakenMessage(args.username));
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

export const getUserById = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.userId);
  },
});

// One-off / maintenance backfill: stamp emailVerificationTime for a user whose
// email is already proven (e.g. a password account that completed the Resend
// OTP round-trip before the auth callback persisted the timestamp). Idempotent
// — leaves an already-stamped user untouched. Returns what it did.
export const backfillEmailVerification = internalMutation({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("email", (q) => q.eq("email", args.email))
      .first();
    if (!user) return { found: false as const };
    if (user.emailVerificationTime !== undefined) {
      return {
        found: true as const,
        alreadySet: true,
        at: user.emailVerificationTime,
      };
    }
    const at = user._creationTime;
    await ctx.db.patch(user._id, { emailVerificationTime: at });
    return { found: true as const, alreadySet: false, at };
  },
});

export const getUserByUsername = query({
  args: { username: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("users")
      .withIndex("by_username", (q) =>
        q.eq("username", normalizeUsername(args.username)),
      )
      .unique();
  },
});

// The signed-in user's public profile, or null when anonymous. Drives the
// nav auth state and the "choose a username" prompt after social sign-up.
export const currentUser = query({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx);
    if (!userId) return null;
    const user = await ctx.db.get(userId);
    if (!user) return null;
    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      name: user.name,
      image: user.image,
      usernameSet: user.usernameSet ?? false,
    };
  },
});

// Sets the signed-in user's public username. Authoritative server-side
// uniqueness + shape enforcement — the client validation is convenience only.
export const setUsername = mutation({
  args: { username: v.string() },
  handler: async (ctx, args) => {
    const userId = await getAuthUserId(ctx);
    if (!userId) {
      throw new ConvexError("Not authenticated");
    }
    const result = validateUsername(args.username);
    if (!result.ok) {
      throw new ConvexError(result.error);
    }
    const normalized = result.value;
    const existing = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", normalized))
      .unique();
    if (existing !== null && existing._id !== userId) {
      throw new ConvexError(usernameTakenMessage(normalized));
    }
    await ctx.db.patch(userId, { username: normalized, usernameSet: true });
    return { username: normalized };
  },
});
