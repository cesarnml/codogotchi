import {
  ACTIVE_MINUTES_PER_HALF_HEART,
  HALF_HEART_DECAY_HOURS,
  MAX_HALF_HEARTS,
} from "@codogotchi/contracts";

export {
  ACTIVE_MINUTES_PER_HALF_HEART,
  HALF_HEART_DECAY_HOURS,
  MAX_HALF_HEARTS,
};

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
  // Malformed ISO → treat as no elapsed time (no decay from bad data; never NaN-propagate).
  const elapsedHours = Number.isFinite(lastMs)
    ? Math.max(0, (now.getTime() - lastMs) / 3_600_000)
    : 0;

  const safeMinutes = Number.isFinite(activeMinutes)
    ? Math.max(0, activeMinutes)
    : 0;
  const safeCurrent = Number.isFinite(currentHalfHearts)
    ? currentHalfHearts
    : 0;

  const idleDecay = Math.floor(elapsedHours / HALF_HEART_DECAY_HOURS);
  const healGain = Math.floor(safeMinutes / ACTIVE_MINUTES_PER_HALF_HEART);

  // Clamp decay first so a ghost at 0 can still recover by coding (no revive threshold).
  const afterDecay = Math.max(0, safeCurrent - idleDecay);
  return Math.min(MAX_HALF_HEARTS, afterDecay + healGain);
}
