# P10.01 Engine — 1–100 level curve

Size: 2 points
Type: feat
Scope: engine
Red: required

## Outcome

- `@codogotchi/engine` exports `levelForXp(totalXp: number): number` returning an integer `1..100` per the calibrated curve.
- Exports `levelProgress(totalXp: number): { level: number; into: number; span: number; fraction: number }` where `fraction` is `into/span` clamped `0..1` (and `1` at level 100).
- A frozen `LEVEL_THRESHOLDS` array of 100 cumulative-XP entries is derived from `C(L) = T × ((L−1)/99)^2.5`, `T = 68_000_000_000`. `LEVEL_THRESHOLDS[0] === 0`; `LEVEL_THRESHOLDS[99] === T` (or the rounded constant).
- Thresholds are monotonically increasing; `levelForXp` is monotonic non-decreasing.
- `STAGE_THRESHOLDS` and `stageForXp` remain exported and unchanged; `stageForXp` gains a `@deprecated` JSDoc pointing to `levelForXp`.

## Red

- Write failing `vitest` cases: `levelForXp(0) === 1`; `levelForXp(T) === 100`; `levelForXp(T * 2) === 100` (cap); a mid-curve boundary (just below vs at `LEVEL_THRESHOLDS[50]`) flips 50→51; `levelProgress` returns `fraction` near 0 at the bottom of a level and near 1 just below the next; monotonicity over a sampled sweep.
- Confirm the new tests fail (functions/exports absent).
- Commit `test(P10.01): level curve thresholds and progress [red]`.

## Green

- Generate `LEVEL_THRESHOLDS` once at module load from the formula (rounded to integers); implement `levelForXp` via binary/linear search over the table and `levelProgress` from neighboring thresholds. Smallest change to pass.

## Refactor

- Share the curve constants (`T`, exponent `2.5`, level count `100`) as named exports so contracts/tests reference them rather than magic numbers. No opportunistic cleanup elsewhere.

## Review Focus

- Curve constants match the locked calibration (`T = 68e9`, `p = 2.5`); document they are **provisional**.
- Boundary/rounding behavior at level edges; cap at 100; behavior for negative/NaN input (clamp to level 1).
- `stageForXp` left functionally intact for the dormant sync path.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Import of `./level` failed (module not found) — all 18 tests failed at module resolution.
Why this path: Precomputed frozen table + binary search is O(log 100) = O(1) in practice, avoids floating-point inverse root on every call, and makes boundaries crystal-clear for tests. One frozen array, one search.
Alternative considered: Analytic inverse `((xp/T)^(1/2.5) * 99 + 1)` avoids storage but requires `Math.pow` on every call and rounds differently at boundaries — table is more testable and matches the spec's threshold language directly.
Deferred: Per-user recalibration; re-validation of constants against real token distribution when sync ships.
Contract note: `LEVEL_T`, `LEVEL_EXPONENT`, `LEVEL_COUNT` exported as named constants per ticket scope. Non-null assertions replaced with `?? 0` / `?? LEVEL_T` fallbacks to satisfy biome linter (`noNonNullAssertion` rule).
