// Public authorship handle rules — shared by the Convex server (uniqueness
// enforcement in the auth callback) and the web client (signup form). Keeping
// one source of truth means client-side validation can never drift from the
// shape the server actually accepts.

export const USERNAME_MIN = 3;
export const USERNAME_MAX = 20;

// Allowed characters: lowercase letters, digits, underscore. Case is folded in
// normalizeUsername so uniqueness compares case-insensitively ("Maew" === "maew").
const USERNAME_PATTERN = /^[a-z0-9_]+$/;

/** Folds a raw handle to its canonical comparison form: trimmed + lowercased. */
export function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase();
}

export type UsernameValidation =
  | { ok: true; value: string }
  | { ok: false; error: string };

/**
 * Normalizes then validates a public username. Returns the canonical value on
 * success, or a specific, user-fixable message on failure.
 */
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

/** Canonical collision message, naming the handle that is already in use. */
export function usernameTakenMessage(username: string): string {
  return `Username "${username}" is already taken`;
}

/**
 * Coerces an arbitrary string into a guaranteed-valid username. Unlike
 * {@link validateUsername} (which rejects), this always returns a conformant
 * handle — used server-side where a username MUST be produced (e.g. synthesizing
 * one for social signups, or hardening a directly-submitted password signup that
 * bypassed client validation). Strips disallowed characters, clamps length, and
 * falls back to a unique-ish handle when nothing usable remains.
 */
export function coerceUsername(raw: string): string {
  let value = normalizeUsername(raw).replace(/[^a-z0-9_]/g, "");
  if (value.length === 0) {
    value = `user_${Date.now().toString(36)}`;
  }
  if (value.length > USERNAME_MAX) {
    value = value.slice(0, USERNAME_MAX);
  }
  if (value.length < USERNAME_MIN) {
    value = value.padEnd(USERNAME_MIN, "0");
  }
  return value;
}
