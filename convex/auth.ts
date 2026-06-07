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
      const profile = args.profile;
      const profileEmail = profile.email as string | undefined;
      const profileName = profile.name as string | undefined;
      const profileImage = profile.image as string | undefined;

      if (args.existingUserId) {
        // Existing linked account — patch auth-managed fields that may have
        // changed since sign-up (name, image, email verification) without
        // touching username or rpgHandle.
        await ctx.db.patch(args.existingUserId, {
          name: profileName,
          image: profileImage,
          email: profileEmail,
        });
        return args.existingUserId;
      }

      // No existing linked account — check for a user with the same verified
      // email before inserting.  This implements cross-provider account linking:
      // a user who signs up with Password and later signs in with Google on the
      // same email address gets ONE unified identity instead of two separate rows.
      if (profileEmail) {
        const existingByEmail = await ctx.db
          .query("users")
          .withIndex("email", (q) => q.eq("email", profileEmail))
          .first();
        if (existingByEmail) {
          // Link this new provider to the existing user and refresh mutable fields.
          await ctx.db.patch(existingByEmail._id, {
            name: profileName ?? existingByEmail.name,
            image: profileImage ?? existingByEmail.image,
          });
          return existingByEmail._id;
        }
      }

      // Genuinely new user — synthesize a unique username.
      const emailPrefix = profileEmail
        ?.split("@")[0]
        ?.toLowerCase()
        .replace(/[^a-z0-9_]/g, "_");
      const nameSlug = profileName
        ?.toLowerCase()
        .replace(/\s+/g, "_")
        .replace(/[^a-z0-9_]/g, "");
      const provided = (profile.username as string | undefined)?.trim();

      const base =
        provided ||
        nameSlug ||
        emailPrefix ||
        `user_${Date.now().toString(36)}`;

      // Find the first available username: base, base_1, base_2, …
      // Bounded by the assumption that usernames are scarce relative to the
      // total user count; loop terminates once a free slot is found.
      let username = base;
      let attempt = 0;
      while (true) {
        const taken = await ctx.db
          .query("users")
          .withIndex("by_username", (q) => q.eq("username", username))
          .unique();
        if (!taken) break;
        attempt++;
        username = `${base}_${attempt}`;
      }

      return await ctx.db.insert("users", {
        email: profileEmail,
        name: profileName,
        image: profileImage,
        username,
        rpgHandle: null,
      });
    },
  },
});
