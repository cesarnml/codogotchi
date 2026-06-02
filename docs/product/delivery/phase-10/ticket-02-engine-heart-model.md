# P10.02 Engine — local heart model

Size: 2 points
Type: feat
Scope: engine
Red: required

## Outcome

- `@codogotchi/engine` exports a pure heart model: given `{ lastActivityAt: string | null, activeMinutes: number, currentHalfHearts: number }` and `now: Date`, returns the resolved `half_hearts` as an integer `0..6`.
- Rules implemented from named constants: `MAX_HALF_HEARTS = 6`, `HALF_HEART_DECAY_HOURS = 8` (−½ heart per 8h idle since `lastActivityAt`), `ACTIVE_MINUTES_PER_HALF_HEART = 60` (+½ heart per active coding-hour), `ACTIVE_HOUR_TOKEN_FLOOR` (or event floor) documented.
- Fresh state: `lastActivityAt === null` ⇒ returns `MAX_HALF_HEARTS`, never decays.
- Floors at 0 (ghost) and caps at 6; ghost recovers purely by accruing active minutes (no separate revive threshold).
- Decay constants are exported so `@codogotchi/contracts` (and Swift, via contracts) reference one definition.

## Red

- Failing `vitest` scenarios: fresh (null) ⇒ 6, no decay; idle 8h ⇒ −1 half-heart; idle 48h ⇒ 0 (ghost); ghost + 1 active hour ⇒ 1 half-heart; cap at 6 with surplus active minutes; floor at 0 with surplus idle; partial idle (<8h) ⇒ no change.
- Confirm failures; commit `test(P10.02): local heart decay/heal model [red]`.

## Green

- Implement decay from elapsed hours since `lastActivityAt` and heal from `activeMinutes`, combine, clamp `0..6`. Smallest passing change.

## Refactor

- Co-locate and export the constants cleanly; ensure no overlap/duplication with the dormant `health.ts` model (do not modify `tickHealth`).

## Review Focus

- The model is **pure and deterministic** (no `Date.now()` inside; `now` injected) for testability and reuse by the Swift decay timer via shared constants.
- Interaction of simultaneous idle+active inputs; clamping order; floor/cap correctness.
- Confirms the old `tickHealth`/`HealthConfig` path is untouched (dormant), not deleted.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: ghost + 60 active minutes → expected 1, got 0 (clamping order wrong on first pass).
Why this path: fresh `hearts.ts` with three exported constants and one pure function; smallest acceptable — no touch to `tickHealth`/`HealthConfig`.
Alternative considered: reusing `tickHealth` — rejected because the per-day / weekend / vacation / grace model is orthogonal and would require stripping most of it; a new file keeps the two models isolated.
Deferred: removal of dormant health model — Phase: sync rebuild (per grill-me ruling).
Contract note: clamping order is decay-floor-first then heal, so a ghost at 0 half-hearts recovers by coding without a separate revive threshold. This is intentionally different from `tickHealth`'s `revive_threshold` gate.
