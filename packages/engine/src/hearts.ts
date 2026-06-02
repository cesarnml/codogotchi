export const MAX_HALF_HEARTS = 6;

/** One half-heart decays per this many idle hours since last activity. */
export const HALF_HEART_DECAY_HOURS = 8;

/** One half-heart heals per this many active coding minutes. */
export const ACTIVE_MINUTES_PER_HALF_HEART = 60;

export type HalfHeartsInput = {
  lastActivityAt: string | null;
  activeMinutes: number;
  currentHalfHearts: number;
};

/**
 * Pure deterministic heart resolver. Accepts no `Date.now()` internally;
 * `now` is injected for testability and reuse by the Swift decay timer.
 *
 * Fresh state: `lastActivityAt === null` → returns `MAX_HALF_HEARTS`, never decays.
 * Decay: each full 8h idle block costs one half-heart.
 * Heal: each full 60 active-minute block earns one half-heart.
 * Result is clamped to [0, MAX_HALF_HEARTS].
 */
export function resolveHalfHearts(
  { lastActivityAt, activeMinutes, currentHalfHearts }: HalfHeartsInput,
  now: Date,
): number {
  if (lastActivityAt === null) {
    return MAX_HALF_HEARTS;
  }

  const lastMs = Date.parse(lastActivityAt);
  const elapsedHours = Math.max(0, (now.getTime() - lastMs) / 3_600_000);

  const idleDecay = Math.floor(elapsedHours / HALF_HEART_DECAY_HOURS);
  const healGain = Math.floor(activeMinutes / ACTIVE_MINUTES_PER_HALF_HEART);

  // Clamp decay first so a ghost at 0 can still recover by coding (no revive threshold).
  const afterDecay = Math.max(0, currentHalfHearts - idleDecay);
  return Math.min(MAX_HALF_HEARTS, afterDecay + healGain);
}
