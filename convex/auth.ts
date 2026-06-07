import GitHub from "@auth/core/providers/github";
import Google from "@auth/core/providers/google";
import { Password } from "@convex-dev/auth/providers/Password";
import { convexAuth } from "@convex-dev/auth/server";
import type { DataModel } from "./_generated/dataModel";

// Credentials read from Convex environment variables at runtime — never
// hardcode secrets in source. Required vars:
//   AUTH_GOOGLE_ID, AUTH_GOOGLE_SECRET
//   AUTH_GITHUB_ID, AUTH_GITHUB_SECRET
// Actual OAuth app creation + Resend domain auth is deferred to P11.07.
// This ticket wires the providers; credentials can be absent in dev/test.

export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [
    Google,
    GitHub,
    Password<DataModel>({
      profile(params) {
        // For password sign-up, derive username from the provided email.
        // A unique suffix is appended in createOrUpdateUser if needed.
        const rawUsername = (params.email as string)
          .split("@")[0]
          .toLowerCase()
          .replace(/[^a-z0-9_]/g, "_");
        return {
          email: params.email as string,
          username: (params.username as string | undefined) ?? rawUsername,
          rpgHandle: null as string | null,
        };
      },
    }),
  ],
  callbacks: {
    async createOrUpdateUser(ctx, args) {
      if (args.existingUserId) {
        // Existing user — no username change, just allow auth system to update
        // base fields (name, image, etc.) via the default path.
        return args.existingUserId;
      }

      // New user — determine a unique username.
      const profile = args.profile;
      const emailPrefix = (profile.email as string | undefined)
        ?.split("@")[0]
        ?.toLowerCase()
        .replace(/[^a-z0-9_]/g, "_");
      const nameSlug = (profile.name as string | undefined)
        ?.toLowerCase()
        .replace(/\s+/g, "_")
        .replace(/[^a-z0-9_]/g, "");
      const provided = (profile.username as string | undefined)?.trim();

      const base =
        provided ||
        nameSlug ||
        emailPrefix ||
        `user_${Date.now().toString(36)}`;

      // Find a unique username: base, base_1, base_2, …
      let username = base;
      let attempt = 0;
      while (true) {
        const existing = await ctx.db
          .query("users")
          .withIndex("by_username", (q) => q.eq("username", username))
          .unique();
        if (!existing) break;
        attempt++;
        username = `${base}_${attempt}`;
      }

      return await ctx.db.insert("users", {
        email: profile.email as string | undefined,
        name: profile.name as string | undefined,
        image: profile.image as string | undefined,
        username,
        rpgHandle: null,
      });
    },
  },
});
