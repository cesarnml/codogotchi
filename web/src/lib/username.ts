// Client-side mirror of the canonical username rules in
// packages/contracts/src/username.ts. The web subproject is not a workspace
// member, so — like spriteFrames — shared pure logic is duplicated rather than
// imported. The server (convex/users.setUsername) is authoritative; this copy
// is convenience validation only. Keep the two in sync.

export const USERNAME_MIN = 3;
export const USERNAME_MAX = 20;

const USERNAME_PATTERN = /^[a-z0-9_]+$/;

export function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase();
}

export type UsernameValidation =
  | { ok: true; value: string }
  | { ok: false; error: string };

export function validateUsername(raw: string): UsernameValidation {
  const value = normalizeUsername(raw);
  if (value.length < USERNAME_MIN) {
    return {
      ok: false,
      error: `Username must be at least ${USERNAME_MIN} characters`,
    };
  }
  if (value.length > USERNAME_MAX) {
    return {
      ok: false,
      error: `Username must be at most ${USERNAME_MAX} characters`,
    };
  }
  if (!USERNAME_PATTERN.test(value)) {
    return {
      ok: false,
      error: "Username may only contain letters, numbers, and underscores",
    };
  }
  return { ok: true, value };
}
