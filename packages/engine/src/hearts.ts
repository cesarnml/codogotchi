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
  /** When true, Sat/Sun hours are excluded from idle decay ("Skip Weekends"). */
  skipWeekends?: boolean;
  /** Idle hours per half-heart of decay. Defaults to HALF_HEART_DECAY_HOURS (8). */
  decayHours?: number;
  /** Active minutes per half-heart of heal. Defaults to ACTIVE_MINUTES_PER_HALF_HEART (60). */
  regenMinutes?: number;
};

/** Positive finite override or the compiled-in default. */
function positiveOr(value: number | undefined, fallback: number): number {
  return value !== undefined && Number.isFinite(value) && value > 0
    ? value
    : fallback;
}

/**
 * Milliseconds of `[startMs, endMs]` that fall on a Saturday or Sunday in the
 * machine's local time zone. Walks local day boundaries so a window spanning
 * several weeks charges exactly the weekday portion. Deliberately hardcodes
 * Sat/Sun to stay in lockstep with the menubar app's display-side decay
 * (HalfHeartDecayEngine.weekendSeconds) — if the two disagreed, displayed
 * hearts would drift from the written value on the next hook event.
 */
export function weekendMsBetween(startMs: number, endMs: number): number {
  if (endMs <= startMs) return 0;
  let total = 0;
  const cursor = new Date(startMs);
  cursor.setHours(0, 0, 0, 0);
  let dayStartMs = cursor.getTime();
  while (dayStartMs < endMs) {
    cursor.setDate(cursor.getDate() + 1);
    cursor.setHours(0, 0, 0, 0); // re-normalize across DST transitions
    const nextDayMs = cursor.getTime();
    const weekday = new Date(dayStartMs).getDay();
    if (weekday === 0 || weekday === 6) {
      const overlap =
        Math.min(endMs, nextDayMs) - Math.max(startMs, dayStartMs);
      if (overlap > 0) total += overlap;
    }
    dayStartMs = nextDayMs;
  }
  return total;
}

/**
 * Pure deterministic heart resolver. Accepts no `Date.now()` internally;
 * `now` is injected for testability and reuse by the Swift decay timer.
 *
 * Fresh state: `lastActivityAt === null` → returns `MAX_HALF_HEARTS`, never decays.
 * Decay: each full `decayHours` (default 8h) idle block costs one half-heart;
 * with `skipWeekends`, weekend hours don't count toward the idle block.
 * Heal: each full `regenMinutes` (default 60) active-minute block earns one half-heart.
 * Result is clamped to [0, MAX_HALF_HEARTS].
 */
export function resolveHalfHearts(
  {
    lastActivityAt,
    activeMinutes,
    currentHalfHearts,
    skipWeekends,
    decayHours,
    regenMinutes,
  }: HalfHeartsInput,
  now: Date,
): number {
  if (lastActivityAt === null) {
    return MAX_HALF_HEARTS;
  }

  const lastMs = Date.parse(lastActivityAt);
  // Malformed ISO → treat as no elapsed time (no decay from bad data; never NaN-propagate).
  let elapsedMs = Number.isFinite(lastMs)
    ? Math.max(0, now.getTime() - lastMs)
    : 0;
  if (skipWeekends === true && elapsedMs > 0) {
    elapsedMs -= weekendMsBetween(lastMs, now.getTime());
  }
  const elapsedHours = elapsedMs / 3_600_000;

  const safeMinutes = Number.isFinite(activeMinutes)
    ? Math.max(0, activeMinutes)
    : 0;
  const safeCurrent = Number.isFinite(currentHalfHearts)
    ? currentHalfHearts
    : 0;

  const idleDecay = Math.floor(
    elapsedHours / positiveOr(decayHours, HALF_HEART_DECAY_HOURS),
  );
  const healGain = Math.floor(
    safeMinutes / positiveOr(regenMinutes, ACTIVE_MINUTES_PER_HALF_HEART),
  );

  // Clamp decay first so a ghost at 0 can still recover by coding (no revive threshold).
  const afterDecay = Math.max(0, safeCurrent - idleDecay);
  return Math.min(MAX_HALF_HEARTS, afterDecay + healGain);
}
