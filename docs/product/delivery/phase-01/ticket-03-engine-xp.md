# P1.03 Engine: XP (`xp.ts`) — pure isomorphic

Size: 2 points
Type: feat
Scope: engine

## Outcome

- `packages/engine/src/xp.ts` exports pure functions for computing XP totals from a raw-signals payload: `computeXp(signals: RawSignals): XpTotals`, plus per-source helpers `xpFromClaudeTokens`, `xpFromCodexTokens`, `xpFromGithubPRs`, `xpFromWakatimeHours`.
- Stage curve and stage thresholds (Stage 1 → Stage 5) live here as `stageForXp(totalXp: number): Stage`.
- All functions are pure: no `fs`, no `process.env`, no `Date.now()` (time is always a parameter).
- Module imports only from `packages/contracts/`. No Node/Bun-only APIs.
- `bun test packages/engine/src/xp.test.ts` passes with table-driven fixtures covering: zero signals, single-source signals, multi-source aggregate, stage boundary crossings, monotonicity per source.
- Default XP curves match scaffold-v2 numerically (verify by porting fixture values).

## Red

- Write `packages/engine/src/xp.test.ts` with failing fixtures: aggregate XP from a known signal set, stage advancement at each boundary, per-source isolation (one source's input does not affect another source's contribution).
- Run `bun test` and confirm failure (module does not exist or returns zero).
- Commit: `test(P1.03): XP computation and stage advancement [red]`.

## Green

- Implement `computeXp`, per-source helpers, and `stageForXp` in `packages/engine/src/xp.ts`.
- Smallest implementation that makes fixtures green. Constants live as named exports at the top of the file (e.g. `export const XP_PER_CLAUDE_TOKEN = ...`) so they are reviewable and tunable later without code surgery.
- Re-export from `packages/engine/src/index.ts`.

## Refactor

- Extract constants if any duplication emerges between per-source helpers.
- Only refactor what this ticket touches.

## Review Focus

- Purity: grep for `node:`, `process.`, `Date.now()`, `Math.random()`, `bun:`. None should appear.
- Stage curve constants are exported as named constants, not magic numbers inside functions.
- Test fixtures cover stage boundaries (just-below, exactly-at, just-above each threshold).
- Per-source helpers are independently testable and pure.
- Tuning is explicitly out of scope — defaults should match scaffold-v2 and stay there. Reviewer should not request curve changes in this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.
