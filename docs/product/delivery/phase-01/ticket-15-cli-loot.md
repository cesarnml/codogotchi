# P1.15 CLI `codogotchi loot`

Size: 2 points
Type: feat
Scope: cli

## Outcome

- `codogotchi loot` prints the full loot history from `~/.codogotchi/profile.json` (or a separate `loot.log` cache, whichever stores it — choice locked in P1.13 Rationale).
- Output: tier + name + source + timestamp + (optionally) the `score_explanation` for PR-quality drops.
- `--limit N` flag shows only the last N events (default: all).
- `--tier <tier>` flag filters to a single tier.
- Does NOT render sprite art. Text/icons only — visible loot rendering is explicitly deferred.
- Tests cover: empty loot history, populated list, `--limit` truncation, `--tier` filter, missing cache (helpful message).

## Red

- Write failing tests for output shape, flag handling, empty list.
- Commit: `test(P1.15): codogotchi loot output and flags [red]`.

## Green

- Implement reader + formatter. Reuse the formatter helper from P1.14 if extracted.

## Refactor

- Consolidate display formatter with `status` if overlap is real.
- Only refactor what this ticket touches.

## Review Focus

- No sprite rendering attempted (explicit deferral).
- Empty-state message is helpful, not a blank screen.
- `score_explanation` displayed when available — this is the human-readable trace the user uses to understand why a PR scored as it did.
- `--limit` and `--tier` work together (filter then limit, in that order).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **Source of truth: `~/.codogotchi/loot.log`** (JSONL), as locked in P1.13 Rationale. `profile.json` does not carry loot history; the log is the canonical local archive.
- **Filter-then-limit order.** `--tier` filters first, then `--limit N` slices the last N. This matches the review focus ("filter then limit, in that order") and the test exercises the composition.
- **Empty vs. missing.** A missing `loot.log` returns `missingCache: true` and the same empty-state message as an empty file. The empty-state hint points the user at `codogotchi sync`. Router prints to stdout in both cases (exit 0) — loot is not a configuration failure.
- **Per-line validation.** Reuses the same `isValidLootEvent` shape as `status` (typeof checks plus `Number.isFinite(ts)`) so a malformed JSONL line or an invalid `ts` is silently skipped rather than crashing `toISOString()`.
- **Module split.** `lootLogPath` and `lootLogExists` now live in `loot.ts` (canonical owner). The previous private `lootLogPath` in `status.ts` was kept (used by `readRecentLoot`) but is no longer re-exported, so `index.ts` `export *` from both files does not collide. Tests import `lootLogPath` from `./loot`.
- **No sprite art.** Explicit deferral honored — text + bracket-tagged tier only.
- **Subagent-review patches.** Cross-model adversarial review confirmed all three invariants hold and patched four real correctness gaps:
  1. `limit: 0` rendered all events because `Array.slice(-0)` returns the full array. Now short-circuits to `[]`.
  2. `runLoot` had no direct-call validation for `limit`. Negative or non-integer limits now throw a clear error (so library callers don't silently corrupt output).
  3. `isValidLootEvent` rejects events whose `source` is outside the canonical `claude_code|codex|github|wakatime` enum and whose `ts` produces an out-of-range `Date` (e.g. `1e16`). This stops malformed JSONL from crashing `formatLoot` with `RangeError`.
  4. Router `--limit` was parsed with `parseInt`, silently truncating `3.7` to `3`. Now rejects fractional and non-integer values with a clear error message.
  Regression coverage added for each.
