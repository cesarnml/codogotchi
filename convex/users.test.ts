import { describe, expect, test } from "bun:test";
import { convexTest } from "convex-test";
import { convexTestModules } from "../test/convex-modules";
import { internal } from "./_generated/api";
import schema from "./schema";

describe("users — identity + uniqueness", () => {
  test("username uniqueness is enforced — second insert with same username throws", async () => {
    const t = convexTest(schema, convexTestModules);
    await t.mutation(internal.users.createUser, {
      username: "alice",
      rpgHandle: null,
    });
    await expect(
      t.mutation(internal.users.createUser, {
        username: "alice",
        rpgHandle: null,
      }),
    ).rejects.toThrow();
  });
});

describe("migrations/p11_02 — idempotency", () => {
  test("migration is idempotent — no-op on already-migrated deployment", async () => {
    const t = convexTest(schema, convexTestModules);
    const r1 = await t.mutation(
      internal.migrations.p11_02.migrateDropLegacyUsers,
      {},
    );
    const r2 = await t.mutation(
      internal.migrations.p11_02.migrateDropLegacyUsers,
      {},
    );
    // Both runs should succeed and return the same status.
    expect(r1).toMatchObject({ status: "clean" });
    expect(r2).toMatchObject({ status: "clean" });
  });
});
