/** Total XP required to reach level 100. Provisional — re-validate when sync ships. */
export const LEVEL_T = 68_000_000_000;

/** Curve exponent for C(L) = T × ((L−1)/99)^p. Provisional. */
export const LEVEL_EXPONENT = 2.5;

/** Number of levels in the 1–100 progression. */
export const LEVEL_COUNT = 100;

/**
 * Cumulative-XP thresholds for each level.
 * LEVEL_THRESHOLDS[i] is the XP required to reach level (i + 1).
 * LEVEL_THRESHOLDS[0] === 0, LEVEL_THRESHOLDS[99] === LEVEL_T.
 */
export const LEVEL_THRESHOLDS: readonly number[] = Object.freeze(
  Array.from({ length: LEVEL_COUNT }, (_, i) => {
    if (i === 0) return 0;
    if (i === LEVEL_COUNT - 1) return LEVEL_T;
    return Math.round(LEVEL_T * (i / (LEVEL_COUNT - 1)) ** LEVEL_EXPONENT);
  }),
);

export type LevelProgress = {
  level: number;
  into: number;
  span: number;
  fraction: number;
};

function safeXp(totalXp: number): number {
  return Number.isFinite(totalXp) && totalXp > 0 ? totalXp : 0;
}

/**
 * Returns the current level (1–100) for a given cumulative XP total.
 * Negative or NaN input clamps to level 1; XP beyond T clamps to level 100.
 */
export function levelForXp(totalXp: number): number {
  const xp = safeXp(totalXp);
  if (xp >= LEVEL_T) return LEVEL_COUNT;
  let lo = 0;
  let hi = LEVEL_COUNT - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if ((LEVEL_THRESHOLDS[mid] ?? 0) <= xp) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo + 1;
}

/**
 * Returns progress within the current level.
 * `into` is XP accumulated since the level's threshold;
 * `span` is the total XP distance of this level;
 * `fraction` = into / span, clamped 0..1 (always 1 at level 100).
 *
 * At level 100, `fraction` is always 1 and `span` is the width of the last
 * level interval. `into` reflects raw excess XP beyond LEVEL_T and may exceed
 * `span` when xp > LEVEL_T — callers should use `fraction`, not `into`, to
 * drive visual fill at the cap.
 */
export function levelProgress(totalXp: number): LevelProgress {
  const xp = safeXp(totalXp);
  const level = levelForXp(xp);

  if (level === LEVEL_COUNT) {
    const lo = LEVEL_THRESHOLDS[LEVEL_COUNT - 1] ?? LEVEL_T;
    const prev = LEVEL_THRESHOLDS[LEVEL_COUNT - 2] ?? 0;
    return {
      level,
      into: xp - lo > 0 ? xp - lo : 0,
      span: lo - prev,
      fraction: 1,
    };
  }

  const lo = LEVEL_THRESHOLDS[level - 1] ?? 0;
  const hi = LEVEL_THRESHOLDS[level] ?? LEVEL_T;
  const span = hi - lo;
  const into = Math.max(0, xp - lo);
  const fraction = span > 0 ? Math.min(1, into / span) : 1;
  return { level, into, span, fraction };
}
